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

/// Production: one Oracle Cloud Always Free host (docs/DEPLOY.md).
const productionServer = 'https://147-224-152-185.sslip.io';

/// The sync server. `--dart-define=RUBRIC_SERVER=https://...` always wins.
/// Otherwise a release build talks to [productionServer] (a shipped app
/// must never point at localhost), and a debug or profile build talks to
/// the local zonai server (server/README.md), which the Android emulator
/// reaches through its host alias 10.0.2.2.
Uri serverUrl({
  bool release = kReleaseMode,
  TargetPlatform platform = TargetPlatform.iOS,
}) {
  const configured = String.fromEnvironment('RUBRIC_SERVER');
  if (configured.isNotEmpty) return Uri.parse(configured);
  if (release) return Uri.parse(productionServer);
  final host = platform == TargetPlatform.android ? '10.0.2.2' : 'localhost';
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
    baseUrl: serverUrl(platform: defaultTargetPlatform),
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
