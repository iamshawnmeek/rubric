import 'dart:async';
import 'dart:io';

import 'package:zonai_client/zonai_client.dart' show ServerException;
import 'package:zonai_sync/zonai_sync.dart';

/// Why signing in or creating an account failed, as far as the teacher needs
/// to know. Each one gets its own message, because the remedy differs: a
/// single catch-all once told a teacher whose phone could not reach the server
/// at all that their account "may already exist".
enum AuthFailure {
  /// The request never got an answer: no connection, DNS, TLS, a timeout.
  offline,

  /// The server answered 401. Signing in, the email and password don't
  /// match. Creating, the email already has an account with another
  /// password: zonai signs you in when the password matches.
  rejected,

  /// The server answered 429.
  rateLimited,

  /// Anything else, a server error included.
  unknown,
}

/// Classifies what signing in or up threw (zonai, or a test's fake). Measured
/// against zonai 0.10.1: a wrong password and a taken email both answer 401;
/// an unreachable host throws package:http's ClientException, which also
/// implements [SocketException].
AuthFailure classifyAuthFailure(Object error) => switch (error) {
  IOException() || TimeoutException() => AuthFailure.offline,
  ServerException(statusCode: 401 || 403) => AuthFailure.rejected,
  ServerException(statusCode: 429) => AuthFailure.rateLimited,
  SyncRemoteException(kind: FailureKind.offline) => AuthFailure.offline,
  SyncRemoteException(kind: FailureKind.unauthorized) => AuthFailure.rejected,
  SyncRemoteException(kind: FailureKind.rateLimited) => AuthFailure.rateLimited,
  _ => AuthFailure.unknown,
};
