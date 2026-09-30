import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:rubric/app/app.dart';
import 'package:rubric/app/settings.dart';
import 'package:rubric/data/database.dart';
import 'package:rubric/data/providers.dart';
import 'package:rubric/sync/secure_token_storage.dart';
import 'package:rubric/sync/sync_service.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:zonai_client/zonai_client.dart';
import 'package:zonai_sync/zonai_sync.dart';

/// The sync server. `--dart-define=RUBRIC_SERVER=https://...` in a build; in
/// development the local zonai server (see server/README.md) — reached from
/// the Android emulator through its host alias 10.0.2.2.
Uri serverUrl() {
  const configured = String.fromEnvironment('RUBRIC_SERVER');
  if (configured.isNotEmpty) return Uri.parse(configured);
  final host = defaultTargetPlatform == TargetPlatform.android
      ? '10.0.2.2'
      : 'localhost';
  return Uri.parse('http://$host:8792');
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.light,
      statusBarBrightness: Brightness.dark,
      systemNavigationBarColor: Color(0xff2F035F),
    ),
  );
  final prefs = await SharedPreferences.getInstance();
  final db = AppDatabase();
  const keychain = FlutterSecureStorage();
  final client = ZonaiClient(
    baseUrl: serverUrl(),
    storage: SecureTokenStorage(keychain),
  );
  final sync = await SyncService.open(
    db: db,
    remote: ZonaiSyncRemote(client),
    auth: ZonaiAuthGateway(client),
    session: KeyValueSessionStore(
      read_: (key) => keychain.read(key: key),
      write_: (key, value) => value == null
          ? keychain.delete(key: key)
          : keychain.write(key: key, value: value),
    ),
  );
  sync.start();

  runApp(
    ProviderScope(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        databaseProvider.overrideWithValue(db),
        syncServiceProvider.overrideWithValue(sync),
        syncWriterProvider.overrideWithValue(sync),
      ],
      child: const RubricApp(),
    ),
  );
}
