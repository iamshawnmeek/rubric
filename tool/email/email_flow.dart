// End-to-end test of Rubric's account emails against a running server whose
// mail goes to tool/email/smtp_sink.py. Run it through test_email_flow.sh,
// which starts both.
//
//   tool/dart run tool/email/email_flow.dart <server url> <mail dir> [<site url>]
//
// It signs up a throwaway account and proves, through the mail actually
// sent, that:
//   - verification mail links to the website's /verify-email page, and its
//     token verifies the account;
//   - password-reset mail links to /reset-password, its token sets a new
//     password, the old password stops working and the new one works;
//   - a reset for an address with no account sends nothing (zonai must not
//     reveal which addresses have accounts).
// The token goes to the server exactly as the website's pages send it (a
// plain POST to /auth/confirm), so this also pins their wire format.
//
// Given a <site url> (tool/email/site_server.py), it then follows fresh links
// through the real pages in headless Chrome (tool/email/page_flow.mjs) and
// checks the outcome on the server: opening the verify page alone verifies
// nothing, its button does, and the reset page's new password signs in.
import 'dart:convert';
import 'dart:io';

import 'package:rubric/sync/account_tables.dart';
import 'package:zonai_client/zonai_client.dart';
import 'package:zonai_schema/payloads.dart'
    show SendResetPasswordAuthBody, VerifyEmailAuthBody;

const site = 'https://yourrubric.com';

Future<void> main(List<String> args) async {
  if (args.length < 2 || args.length > 3) {
    stderr.writeln(
      'usage: email_flow.dart <server url> <mail dir> [<site url>]',
    );
    exit(64);
  }
  final base = Uri.parse(args[0]);
  final mail = Directory(args[1]);
  final localSite = args.length > 2 ? args[2] : null;
  final stamp = DateTime.now().millisecondsSinceEpoch;
  final email = 'flow-$stamp@rubric.invalid';
  const oldPassword = 'first-password-1';
  const newPassword = 'second-password-2';
  var failures = 0;

  void check(String what, {required bool ok, Object? detail}) {
    stdout.writeln('${ok ? 'ok  ' : 'FAIL'} $what${ok ? '' : ': $detail'}');
    if (!ok) failures++;
  }

  int seen() => mail.existsSync()
      ? mail.listSync().where((f) => f.path.endsWith('.eml')).length
      : 0;

  /// The next message after [before] arrived, decoded, or null on timeout.
  Future<String?> nextMail(int before) async {
    for (var i = 0; i < 60; i++) {
      final file = File('${mail.path}/$before.eml');
      if (file.existsSync()) return decodeMail(file.readAsStringSync());
      await Future<void>.delayed(const Duration(milliseconds: 250));
    }
    return null;
  }

  Future<int> confirm(Map<String, Object?> body) async {
    final client = HttpClient();
    try {
      final request = await client.postUrl(base.resolve('/auth/confirm'));
      request.headers.contentType = ContentType.json;
      request.write(jsonEncode(body));
      final response = await request.close();
      await response.drain<void>();
      return response.statusCode;
    } finally {
      client.close();
    }
  }

  Future<AuthSession?> signInAs(String address, String password) =>
      ZonaiClient(baseUrl: base).auth.signIn(
        body: SignInAuthBody(
          table: accountTable,
          email: address,
          password: password,
        ),
      );
  Future<AuthSession?> signIn(String password) => signInAs(email, password);

  bool verified(AuthSession? session) =>
      session?.user['is_verified'] == 1 || session?.user['is_verified'] == true;

  /// Runs one page_flow.mjs mode; its ok/FAIL lines join ours.
  Future<void> page(List<String> modeArgs) async {
    final run = await Process.run('node', [
      'tool/email/page_flow.mjs',
      ...modeArgs,
    ]);
    stdout.write(run.stdout);
    if (run.exitCode != 0) {
      failures++;
      if ((run.stderr as String).isNotEmpty) stderr.write(run.stderr);
    }
  }

  /// A production link from [body], pointed at the local copy of the site.
  String? localLink(String? body, String path) =>
      linkIn(body, '$site$path')?.toString().replaceFirst(site, localSite!);

  try {
    final client = ZonaiClient(baseUrl: base);
    final session = await client.auth.signUp(
      body: SignUpAuthBody(
        table: accountTable,
        email: email,
        password: oldPassword,
      ),
    );
    check(
      'a new account starts unverified',
      ok:
          session?.user['is_verified'] == 0 ||
          session?.user['is_verified'] == false,
      detail: session?.user['is_verified'],
    );

    // Verification.
    var before = seen();
    await client.auth.sendVerifyEmail(
      body: VerifyEmailAuthBody(email: email, table: accountTable),
    );
    final verifyMail = await nextMail(before);
    final verifyLink = linkIn(verifyMail, '$site/verify-email');
    check(
      'verification mail links to the website',
      ok: verifyLink != null,
      detail: verifyMail ?? 'no mail arrived',
    );
    if (verifyLink != null) {
      final status = await confirm({
        'type': 'confirmVerifyEmail',
        'token': verifyLink.queryParameters['s'],
      });
      check('its token is accepted', ok: status == 200, detail: status);
      final after = await signIn(oldPassword);
      check(
        'the account is now verified',
        ok:
            after?.user['is_verified'] == 1 ||
            after?.user['is_verified'] == true,
        detail: after?.user['is_verified'],
      );
    }

    // Password reset.
    before = seen();
    await ZonaiClient(baseUrl: base).auth.sendResetPassword(
      body: SendResetPasswordAuthBody(email: email, table: accountTable),
    );
    final resetMail = await nextMail(before);
    final resetLink = linkIn(resetMail, '$site/reset-password');
    check(
      'reset mail links to the website',
      ok: resetLink != null,
      detail: resetMail ?? 'no mail arrived',
    );
    if (resetLink != null) {
      final status = await confirm({
        'type': 'confirmResetPassword',
        'token': resetLink.queryParameters['s'],
        'newPassword': newPassword,
      });
      check('its token sets a new password', ok: status == 200, detail: status);
      final reused = await confirm({
        'type': 'confirmResetPassword',
        'token': resetLink.queryParameters['s'],
        'newPassword': 'third-password-3',
      });
      check('the link works only once', ok: reused >= 400, detail: reused);

      var oldRefused = false;
      try {
        await signIn(oldPassword);
      } on Object {
        oldRefused = true;
      }
      check('the old password no longer signs in', ok: oldRefused);
      final fresh = await signIn(newPassword);
      check('the new password signs in', ok: fresh != null);
    }

    // No account, no mail: the response must not reveal the difference.
    before = seen();
    await ZonaiClient(baseUrl: base).auth.sendResetPassword(
      body: SendResetPasswordAuthBody(
        email: 'nobody-$stamp@rubric.invalid',
        table: accountTable,
      ),
    );
    await Future<void>.delayed(const Duration(seconds: 2));
    check('an unknown address gets no mail', ok: seen() == before);

    if (localSite != null) {
      // A second account, through the website's pages.
      final other = 'pages-$stamp@rubric.invalid';
      final pagesClient = ZonaiClient(baseUrl: base);
      final pagesSession = await pagesClient.auth.signUp(
        body: SignUpAuthBody(
          table: accountTable,
          email: other,
          password: oldPassword,
        ),
      );
      final pagesId = pagesSession!.user['id']! as String;
      final firstId = session!.user['id']! as String;
      await page(['missing', '$localSite/reset-password']);

      before = seen();
      await pagesClient.auth.sendVerifyEmail(
        body: VerifyEmailAuthBody(email: other, table: accountTable),
      );
      final verifyPage = localLink(await nextMail(before), '/verify-email');
      check('a verify link for the pages', ok: verifyPage != null);
      if (verifyPage != null) {
        await page(['verify-open', verifyPage]);
        check(
          'opening the verify page alone verifies nothing',
          ok: !verified(await signInAs(other, oldPassword)),
        );
        await page(['verify-confirm', verifyPage]);
        check(
          "the page's button verifies the account",
          ok: verified(await signInAs(other, oldPassword)),
        );

        // The app's own check (ZonaiAuthGateway.isVerified): a teacher reads
        // their users row, and nobody else's.
        final mine = await pagesClient.db.get(
          body: GetBody(table: accountTable, where: Eq('id', pagesId)),
          fromJson: (row) => row['is_verified'],
        );
        check(
          'a teacher can read their own verified flag',
          ok: mine == 1 || mine == true,
          detail: mine,
        );
        var hidden = false;
        try {
          await pagesClient.db.get(
            body: GetBody(table: accountTable, where: Eq('id', firstId)),
            fromJson: (row) => row,
          );
        } on Object {
          hidden = true;
        }
        check("another teacher's row stays hidden", ok: hidden);
      }

      before = seen();
      await ZonaiClient(baseUrl: base).auth.sendResetPassword(
        body: SendResetPasswordAuthBody(email: other, table: accountTable),
      );
      final resetPage = localLink(await nextMail(before), '/reset-password');
      check('a reset link for the pages', ok: resetPage != null);
      if (resetPage != null) {
        const pagePassword = 'page-password-4';
        await page(['reset', resetPage, pagePassword]);
        check(
          "the reset page's new password signs in",
          ok: await signInAs(other, pagePassword) != null,
        );
      }
    }
  } on Object catch (e) {
    check('email flow', ok: false, detail: e);
  }

  stdout.writeln(
    failures == 0 ? 'EMAIL FLOW PASSED' : 'EMAIL FLOW FAILED ($failures)',
  );
  exit(failures == 0 ? 0 : 1);
}

/// The first link in [body] that starts with [prefix] and carries `?s=`.
Uri? linkIn(String? body, String prefix) {
  if (body == null) return null;
  // Mustache HTML-escapes variables (`/` becomes `&#x2F;`); a mail client
  // decodes entities in an href before following it, so decode them too.
  final decoded = body
      .replaceAllMapped(
        RegExp('&#x([0-9A-Fa-f]+);'),
        (m) => String.fromCharCode(int.parse(m.group(1)!, radix: 16)),
      )
      .replaceAllMapped(
        RegExp('&#([0-9]+);'),
        (m) => String.fromCharCode(int.parse(m.group(1)!)),
      )
      .replaceAll('&amp;', '&');
  final match = RegExp('${RegExp.escape(prefix)}\\?s=[^"\'\\s<>]+')
      .firstMatch(decoded);
  return match == null ? null : Uri.parse(match.group(0)!);
}

/// Undoes the transfer encodings a mailer uses: base64 parts and
/// quoted-printable (soft line breaks and =XX escapes). Good enough to find
/// links in what our own server sent; not a MIME parser.
String decodeMail(String raw) {
  final out = StringBuffer();
  final parts = raw.split(RegExp(r'\r?\n--'));
  for (final part in parts) {
    final split = part.indexOf(RegExp(r'\r?\n\r?\n'));
    if (split < 0) {
      out.writeln(part);
      continue;
    }
    final headers = part.substring(0, split).toLowerCase();
    final body = part.substring(split).trim();
    if (headers.contains('content-transfer-encoding: base64')) {
      try {
        out.writeln(
          utf8.decode(base64.decode(body.replaceAll(RegExp(r'\s'), ''))),
        );
        continue;
      } on FormatException {
        // Not base64 after all; fall through.
      }
    }
    if (headers.contains('quoted-printable')) {
      out.writeln(
        body
            .replaceAll(RegExp(r'=\r?\n'), '')
            .replaceAllMapped(
              RegExp('=([0-9A-Fa-f]{2})'),
              (m) => String.fromCharCode(int.parse(m.group(1)!, radix: 16)),
            ),
      );
      continue;
    }
    out.writeln(body);
  }
  return out.toString();
}
