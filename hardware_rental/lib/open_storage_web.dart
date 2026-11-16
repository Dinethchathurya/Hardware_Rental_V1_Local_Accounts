import 'dart:convert';
import 'dart:js_interop';

import 'package:uuid/uuid.dart';

import 'shop_storage.dart';

@JS('localStorage')
external _BrowserStorage get _localStorage;

extension type _BrowserStorage(JSObject _) implements JSObject {
  external String? getItem(String key);
  external void setItem(String key, String value);
}

Future<ShopStorage> openStorage() async => _WebStorage(_localStorage);

class _WebStorage implements ShopStorage {
  _WebStorage(this._storage);

  static const _key = 'lk.dineth.hardware_rental.preview.v1';
  final _BrowserStorage _storage;
  String? _snapshot;

  @override
  Map<String, dynamic> read() {
    _snapshot = _storage.getItem(_key);
    final snapshot = _snapshot;
    if (snapshot == null) return {};
    final envelope = jsonDecode(snapshot) as Map<String, dynamic>;
    return envelope['data'] as Map<String, dynamic>;
  }

  @override
  void write(Map<String, dynamic> data) {
    if (_storage.getItem(_key) != _snapshot) {
      throw StateError(
        'Another browser tab changed this data. Reload this tab before trying again.',
      );
    }
    final next = jsonEncode({'revision': const Uuid().v4(), 'data': data});
    try {
      _storage.setItem(_key, next);
    } catch (_) {
      throw StateError(
        'The browser could not save the data. Check whether storage is blocked or full.',
      );
    }
    _snapshot = next;
  }

  @override
  void close() {}
}
