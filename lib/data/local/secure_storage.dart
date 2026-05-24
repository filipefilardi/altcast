import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter/services.dart';

final secureStorageProvider = Provider<SecureStorage>((ref) {
  return SecureStorage(
    const FlutterSecureStorage(
      iOptions: IOSOptions(accessibility: KeychainAccessibility.first_unlock),
    ),
  );
});

class SecureStorage {
  SecureStorage(this._storage);

  final FlutterSecureStorage _storage;

  Future<String?> read(String key) async {
    try {
      return await _storage.read(key: key);
    } on PlatformException catch (error) {
      if (_isMissingMacOsKeychainEntitlement(error)) {
        debugPrint(
          'SecureStorage read failed on macOS due to missing keychain entitlement (-34018).',
        );
        return null;
      }
      rethrow;
    }
  }

  Future<void> write(String key, String value) async {
    try {
      await _storage.write(key: key, value: value);
    } on PlatformException catch (error) {
      if (_isMissingMacOsKeychainEntitlement(error)) {
        debugPrint(
          'SecureStorage write failed on macOS due to missing keychain entitlement (-34018).',
        );
        return;
      }
      rethrow;
    }
  }

  Future<void> delete(String key) async {
    try {
      await _storage.delete(key: key);
    } on PlatformException catch (error) {
      if (_isMissingMacOsKeychainEntitlement(error)) {
        debugPrint(
          'SecureStorage delete failed on macOS due to missing keychain entitlement (-34018).',
        );
        return;
      }
      rethrow;
    }
  }

  bool _isMissingMacOsKeychainEntitlement(PlatformException error) {
    if (defaultTargetPlatform != TargetPlatform.macOS) {
      return false;
    }

    final message = error.message ?? '';
    return error.code == '-34018' ||
        message.contains('A required entitlement isn\'t present');
  }
}
