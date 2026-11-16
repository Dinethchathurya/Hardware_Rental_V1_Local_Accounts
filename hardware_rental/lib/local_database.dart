import 'dart:convert';
import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';

import 'shop_storage.dart';

typedef _RowCallback =
    Int32 Function(
      Pointer<Void>,
      Int32,
      Pointer<Pointer<Utf8>>,
      Pointer<Pointer<Utf8>>,
    );

class LocalDatabase implements ShopStorage {
  LocalDatabase(String path) {
    final library = DynamicLibrary.open(
      Platform.isWindows ? 'winsqlite3.dll' : '/usr/lib/libsqlite3.dylib',
    );
    final open = library
        .lookupFunction<
          Int32 Function(Pointer<Utf8>, Pointer<Pointer<Void>>),
          int Function(Pointer<Utf8>, Pointer<Pointer<Void>>)
        >('sqlite3_open');
    _close = library
        .lookupFunction<
          Int32 Function(Pointer<Void>),
          int Function(Pointer<Void>)
        >('sqlite3_close');
    _exec = library
        .lookupFunction<
          Int32 Function(
            Pointer<Void>,
            Pointer<Utf8>,
            Pointer<NativeFunction<_RowCallback>>,
            Pointer<Void>,
            Pointer<Pointer<Utf8>>,
          ),
          int Function(
            Pointer<Void>,
            Pointer<Utf8>,
            Pointer<NativeFunction<_RowCallback>>,
            Pointer<Void>,
            Pointer<Pointer<Utf8>>,
          )
        >('sqlite3_exec');
    _changes = library
        .lookupFunction<
          Int32 Function(Pointer<Void>),
          int Function(Pointer<Void>)
        >('sqlite3_changes');
    _error = library
        .lookupFunction<
          Pointer<Utf8> Function(Pointer<Void>),
          Pointer<Utf8> Function(Pointer<Void>)
        >('sqlite3_errmsg');
    final output = calloc<Pointer<Void>>();
    final filename = path.toNativeUtf8();
    try {
      final code = open(filename, output);
      _handle = output.value;
      if (code != 0) {
        throw StateError('Could not open the local database ($code).');
      }
      _run('PRAGMA busy_timeout = 3000');
      _run('PRAGMA synchronous = FULL');
      _run(
        'CREATE TABLE IF NOT EXISTS shop_snapshot '
        '(id INTEGER PRIMARY KEY CHECK (id = 1), revision INTEGER NOT NULL, payload TEXT NOT NULL)',
      );
      _run("INSERT OR IGNORE INTO shop_snapshot VALUES (1, 0, '{}')");
    } catch (_) {
      if (_handle != nullptr) _close(_handle);
      rethrow;
    } finally {
      calloc.free(output);
      malloc.free(filename);
    }
  }

  Pointer<Void> _handle = nullptr;
  late final int Function(Pointer<Void>) _close;
  late final int Function(Pointer<Void>) _changes;
  late final Pointer<Utf8> Function(Pointer<Void>) _error;
  late final int Function(
    Pointer<Void>,
    Pointer<Utf8>,
    Pointer<NativeFunction<_RowCallback>>,
    Pointer<Void>,
    Pointer<Pointer<Utf8>>,
  )
  _exec;

  void _run(String sql, [Pointer<NativeFunction<_RowCallback>>? callback]) {
    final statement = sql.toNativeUtf8();
    try {
      if (_exec(_handle, statement, callback ?? nullptr, nullptr, nullptr) !=
          0) {
        throw StateError(_error(_handle).toDartString());
      }
    } finally {
      malloc.free(statement);
    }
  }

  int _revision = 0;

  @override
  Map<String, dynamic> read() {
    late Map<String, dynamic> data;
    Object? decodeError;
    final callback = NativeCallable<_RowCallback>.isolateLocal((
      Pointer<Void> _,
      int count,
      Pointer<Pointer<Utf8>> values,
      Pointer<Pointer<Utf8>> _,
    ) {
      try {
        data = jsonDecode(values[1].toDartString()) as Map<String, dynamic>;
        _revision = int.parse(values[0].toDartString());
        return 0;
      } catch (error) {
        decodeError = error;
        return 1;
      }
    }, exceptionalReturn: 1);
    try {
      _run(
        'SELECT revision, payload FROM shop_snapshot WHERE id = 1',
        callback.nativeFunction,
      );
      return data;
    } catch (_) {
      if (decodeError != null) {
        throw StateError('Local data could not be read.');
      }
      rethrow;
    } finally {
      callback.close();
    }
  }

  @override
  void write(Map<String, dynamic> data) {
    // Encode the payload as a hex literal so user text never enters SQL syntax.
    final hex = utf8
        .encode(jsonEncode(data))
        .map((byte) => byte.toRadixString(16).padLeft(2, '0'))
        .join();
    _run(
      "UPDATE shop_snapshot SET payload = CAST(X'$hex' AS TEXT), "
      'revision = revision + 1 WHERE id = 1 AND revision = $_revision',
    );
    if (_changes(_handle) != 1) {
      throw StateError(
        'Another app window changed the data. Restart this window before trying again.',
      );
    }
    _revision++;
  }

  @override
  void close() => _close(_handle);
}
