import 'package:rubric_server/src/email/email_env.dart';
import 'package:test/test.dart';

void main() {
  const smtp = {
    'SMTP_HOST': 'smtp.example.test',
    'SMTP_USERNAME': 'user',
    'SMTP_PASSWORD': 'secret',
  };

  test('a release server without mail settings refuses to start', () {
    expect(
      () => emailConfigFrom(const {}, release: true),
      throwsA(isA<StateError>()),
    );
  });

  test('a development server without them sends no mail', () {
    expect(emailConfigFrom(const {}, release: false), isNull);
  });

  test('half a configuration is refused in development too, naming what '
      'is missing', () {
    expect(
      () => emailConfigFrom(const {'SMTP_HOST': 'h'}, release: false),
      throwsA(
        isA<StateError>().having(
          (e) => e.message,
          'message',
          allOf(contains('SMTP_USERNAME'), contains('SMTP_PASSWORD')),
        ),
      ),
    );
  });

  test('blank values count as missing', () {
    expect(
      () => emailConfigFrom({...smtp, 'SMTP_PASSWORD': '  '}, release: true),
      throwsA(isA<StateError>()),
    );
  });

  test('defaults to STARTTLS on 587, from the approved sender', () {
    final config = emailConfigFrom(smtp, release: true)!;
    expect(config.host, 'smtp.example.test');
    expect(config.port, 587);
    expect(config.ssl, isFalse);
    expect(config.allowInsecure, isFalse);
    expect(config.from.address, 'noreply@yourrubric.com');
  });

  test('465 is implicit TLS', () {
    expect(
      emailConfigFrom({...smtp, 'SMTP_PORT': '465'}, release: true)!.ssl,
      isTrue,
    );
  });

  test('a bad port is refused', () {
    expect(
      () => emailConfigFrom({...smtp, 'SMTP_PORT': 'smtp'}, release: true),
      throwsA(isA<StateError>()),
    );
  });

  test('plain SMTP to a local catcher only outside release', () {
    final insecure = {...smtp, 'SMTP_ALLOW_INSECURE': 'true'};
    expect(emailConfigFrom(insecure, release: false)!.allowInsecure, isTrue);
    expect(emailConfigFrom(insecure, release: true)!.allowInsecure, isFalse);
  });
}
