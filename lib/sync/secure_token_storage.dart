import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:revali_client/revali_client.dart' show Storage;

/// zonai_client's token [Storage] on the platform keychain, so a teacher
/// stays signed in across launches without the token sitting in plain
/// preferences.
final class SecureTokenStorage implements Storage {
  new(this._keychain);

  final FlutterSecureStorage _keychain;

  static const _prefix = 'rubric.zonai.';

  @override
  Future<Object?> operator [](String key) async {
    final raw = await _keychain.read(key: '$_prefix$key');
    return raw == null ? null : jsonDecode(raw);
  }

  @override
  Future<void> save(String key, Object? value) => value == null
      ? _keychain.delete(key: '$_prefix$key')
      : _keychain.write(key: '$_prefix$key', value: jsonEncode(value));

  @override
  Future<void> saveAll(Map<String, Object?> values) async {
    for (final e in values.entries) {
      await save(e.key, e.value);
    }
  }

  @override
  Future<void> clear() async {
    for (final key in (await _keychain.readAll()).keys) {
      if (key.startsWith(_prefix)) await _keychain.delete(key: key);
    }
  }

  @override
  Future<void> remove(String key) => _keychain.delete(key: '$_prefix$key');
}
