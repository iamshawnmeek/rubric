import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:rubric/sync/auth_failure.dart';
import 'package:zonai_client/zonai_client.dart';
import 'package:zonai_sync/zonai_sync.dart';

void main() {
  test('an unreachable server is "offline", not a refusal', () async {
    // The real client against a closed port: what a phone without network
    // access threw (package:http's ClientException, not a SocketException
    // subclass you would guess from its name).
    final client = ZonaiClient(baseUrl: Uri.parse('http://127.0.0.1:1'));
    final error = await client.auth
        .signIn(
          body: const SignInAuthBody(
            table: 'users',
            email: 'a@b.c',
            password: 'x',
          ),
        )
        .then<Object?>((_) => null, onError: (Object e) => e);

    expect(error, isNotNull);
    expect(classifyAuthFailure(error!), AuthFailure.offline);
  });

  test('timeouts and TLS failures are offline too', () {
    expect(classifyAuthFailure(TimeoutException('')), AuthFailure.offline);
    expect(
      classifyAuthFailure(const HandshakeException()),
      AuthFailure.offline,
    );
  });

  test('server answers map by status', () {
    ServerException status(int code) =>
        ServerException(message: '', statusCode: code);
    expect(classifyAuthFailure(status(401)), AuthFailure.rejected);
    expect(classifyAuthFailure(status(429)), AuthFailure.rateLimited);
    expect(classifyAuthFailure(status(500)), AuthFailure.unknown);
  });

  test("the sync layer's own failures map the same way", () {
    expect(
      classifyAuthFailure(const SyncRemoteException(FailureKind.offline)),
      AuthFailure.offline,
    );
    expect(
      classifyAuthFailure(const SyncRemoteException(FailureKind.unauthorized)),
      AuthFailure.rejected,
    );
    expect(classifyAuthFailure(StateError('x')), AuthFailure.unknown);
  });
}
