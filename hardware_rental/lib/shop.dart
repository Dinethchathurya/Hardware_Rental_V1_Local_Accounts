import 'dart:convert';
import 'package:uuid/uuid.dart';

import 'local_credentials.dart';
import 'shop_storage.dart';

typedef RowData = Map<String, dynamic>;

class Shop {
  Shop(this.database) : _data = database.read();

  final ShopStorage database;
  RowData _data;
  String? _sessionUserId;
  List<RowData> get _accounts => _rows(_data, 'accounts');
  bool get hasOwner => _accounts.isNotEmpty;
  RowData? get _sessionAccount => _accounts
      .where(
        (account) =>
            account['id'] == _sessionUserId && account['active'] == true,
      )
      .firstOrNull;
  bool get signedIn => _sessionAccount != null;
  bool get isOwner => _sessionAccount?['role'] == 'Owner';
  List<RowData> get staff => isOwner
      ? [
          for (final account in _accounts)
            {
              'id': account['id'],
              'name': account['name'],
              'username': account['username'],
              'role': account['role'],
              'active': account['active'],
            },
        ]
      : [];

  void _requireOwner() {
    if (!isOwner) throw StateError('Only the shop owner can make this change.');
  }

  Future<RowData> _newAccount(
    String name,
    String username,
    String password,
    String role,
  ) async {
    final normalized = username.trim().toLowerCase();
    if (name.trim().isEmpty ||
        !RegExp(r'^[a-z0-9][a-z0-9_.@+-]{2,79}$').hasMatch(normalized)) {
      throw StateError('Enter a name and a username of 3 to 80 characters.');
    }
    if (_accounts.any((account) => account['username'] == normalized)) {
      throw StateError('This username is already in use.');
    }
    final credential = await createPassword(password);
    return {
      'id': _uuid.v4(),
      'name': name.trim(),
      'username': normalized,
      'role': role,
      'active': true,
      'salt': credential.salt,
      'passwordHash': credential.hash,
      'iterations': credential.iterations,
    };
  }

  Future<void> registerOwner(
    String shopName,
    String deviceName,
    String name,
    String username,
    String password,
  ) async {
    if (hasOwner) throw StateError('This workspace already has an owner.');
    if (shopName.trim().isEmpty || deviceName.trim().isEmpty) {
      throw StateError('Enter the shop and computer names.');
    }
    final account = await _newAccount(name, username, password, 'Owner');
    if (hasOwner) throw StateError('This workspace already has an owner.');
    _save(
      'Registered local owner',
      (next) => next.addAll({
        'name': shopName.trim(),
        'device': deviceName.trim(),
        'deviceId': _uuid.v4(),
        'accounts': [account],
      }),
      actor: account,
      deviceName: deviceName.trim(),
    );
    _sessionUserId = account['id'] as String;
  }

  Future<void> signIn(String username, String password) async {
    // Load the latest snapshot before authenticating, including local staff changes.
    _data = database.read();
    final account = _accounts
        .where(
          (row) =>
              row['username'] == username.trim().toLowerCase() &&
              row['active'] == true,
        )
        .firstOrNull;
    if (account == null ||
        !await verifyPassword(password, (
          salt: account['salt'] as String,
          hash: account['passwordHash'] as String,
          iterations: account['iterations'] as int,
        ))) {
      throw StateError('Username or password is incorrect.');
    }
    _save('Signed in', (_) {}, actor: account);
    _sessionUserId = account['id'] as String;
  }

  void signOut() => _sessionUserId = null;

  Future<void> addStaff(String name, String username, String password) async {
    _requireOwner();
    final account = await _newAccount(name, username, password, 'Staff');
    _requireOwner();
    if (_accounts.any((row) => row['username'] == account['username'])) {
      throw StateError('This username is already in use.');
    }
    _save('Created staff account for ${account['name']}', (next) {
      next['accounts'] = [..._rows(next, 'accounts'), account];
    });
  }

  void setStaffActive(String id, bool active) {
    _requireOwner();
    final account = _accounts.firstWhere(
      (row) => row['id'] == id && row['role'] == 'Staff',
    );
    _save(
      '${active ? 'Reactivated' : 'Deactivated'} staff account for ${account['name']}',
      (next) {
        _rows(next, 'accounts').firstWhere((row) => row['id'] == id)['active'] =
            active;
      },
    );
  }

  final _uuid = const Uuid();

  String get name => _data['name'] as String? ?? 'Hardware Rental';
  String get device => _data['device'] as String? ?? 'Front counter';
  String get operatorName =>
      _sessionAccount?['name'] as String? ?? 'Local operator';
  List<RowData> get equipment => _rows(_data, 'equipment');
  List<RowData> get customers => _rows(_data, 'customers');
  List<RowData> get rentals => _rows(_data, 'rentals');
  List<RowData> get activity => _rows(_data, 'activity');

  List<RowData> _rows(RowData data, String key) =>
      ((data[key] as List?) ?? []).cast<RowData>();

  int available(RowData item) =>
      (item['stock'] as int) - checkedOut(item['id'] as String);

  int checkedOut(String equipmentId) => rentals
      .where((rental) => rental['equipmentId'] == equipmentId)
      .fold(0, (sum, rental) => sum + remaining(rental));

  int remaining(RowData rental) =>
      (rental['quantity'] as int) - (rental['returned'] as int);
  int balance(RowData rental) =>
      (rental['total'] as int) - (rental['paid'] as int);

  void _save(
    String event,
    void Function(RowData) change, {
    RowData? actor,
    String? deviceName,
  }) {
    final account = actor ?? _sessionAccount;
    if (account == null) throw StateError('Sign in to make changes.');
    final next = jsonDecode(jsonEncode(_data)) as RowData;
    change(next);
    next['activity'] = [
      {
        'event': event,
        'operator': account['name'],
        'userId': account['id'],
        'device': deviceName ?? device,
        'deviceId': next['deviceId'],
        'at': DateTime.now().toUtc().toIso8601String(),
      },
      ..._rows(next, 'activity'),
    ];
    database.write(next);
    _data = next;
  }

  void saveSettings(String name, String device) {
    _requireOwner();
    _save(
      'Updated shop settings',
      (next) => next.addAll({'name': name, 'device': device}),
    );
  }

  void saveEquipment(
    String? id,
    String code,
    String name,
    int stock,
    int rate,
  ) {
    if (equipment.any(
      (item) =>
          item['id'] != id &&
          (item['code'] as String).toLowerCase() == code.toLowerCase(),
    )) {
      throw StateError('This equipment code is already in use.');
    }
    if (id != null && stock < checkedOut(id)) {
      throw StateError(
        'Stock cannot be less than the quantity currently rented out.',
      );
    }
    _save('Saved equipment $code', (next) {
      next['equipment'] = [
        ..._rows(next, 'equipment').where((item) => item['id'] != id),
        {
          'id': id ?? _uuid.v4(),
          'code': code,
          'name': name,
          'stock': stock,
          'rate': rate,
        },
      ];
    });
  }

  void saveCustomer(String? id, String name, String phone) {
    _save('Saved customer $name', (next) {
      next['customers'] = [
        ..._rows(next, 'customers').where((customer) => customer['id'] != id),
        {'id': id ?? _uuid.v4(), 'name': name, 'phone': phone},
      ];
    });
  }

  void issue(RowData item, RowData customer, int quantity, DateTime due) {
    if (quantity < 1 || quantity > available(item)) {
      throw StateError('There is insufficient stock for this rental.');
    }
    final today = DateUtilsLocal.day(DateTime.now());
    final dueDay = DateUtilsLocal.day(due);
    if (dueDay.isBefore(today)) {
      throw StateError('The due date cannot be in the past.');
    }
    final days = dueDay.difference(today).inDays + 1;
    final id = _uuid.v4();
    final reference = id.substring(0, 8).toUpperCase();
    _save('Issued rental $reference', (next) {
      next['rentals'] = [
        {
          'id': id,
          'reference': reference,
          'equipmentId': item['id'],
          'equipment': item['name'],
          'customerId': customer['id'],
          'customer': customer['name'],
          'quantity': quantity,
          'issued': today.toIso8601String(),
          'due': dueDay.toIso8601String(),
          'total': days * quantity * (item['rate'] as int),
          'paid': 0,
          'returned': 0,
          'payments': <RowData>[],
          'returns': <RowData>[],
        },
        ..._rows(next, 'rentals'),
      ];
    });
  }

  void extendRental(RowData rental, DateTime newDue, int agreedCharge) {
    final due = DateUtilsLocal.day(newDue);
    final existing = DateTime.parse(rental['due'] as String);
    if (remaining(rental) == 0 ||
        !due.isAfter(existing) ||
        due.isBefore(DateUtilsLocal.day(DateTime.now())) ||
        agreedCharge < 0) {
      throw StateError(
        'Enter a later due date and a valid additional charge for an active rental.',
      );
    }
    _save('Extended rental ${rental['reference']}', (next) {
      final current = _rows(
        next,
        'rentals',
      ).singleWhere((row) => row['id'] == rental['id']);
      current['due'] = due.toIso8601String();
      current['total'] = (current['total'] as int) + agreedCharge;
      current['extensions'] = [
        ..._rows(current, 'extensions'),
        {
          'previousDue': existing.toIso8601String(),
          'due': due.toIso8601String(),
          'charge': agreedCharge,
          'at': DateTime.now().toUtc().toIso8601String(),
        },
      ];
    });
  }

  void returnItems(RowData rental, int quantity, String condition) {
    if (quantity < 1 || quantity > remaining(rental)) {
      throw StateError('Enter a quantity within the outstanding quantity.');
    }
    _save('Returned $quantity on ${rental['reference']}', (next) {
      final current = _rows(
        next,
        'rentals',
      ).singleWhere((row) => row['id'] == rental['id']);
      current['returned'] = (current['returned'] as int) + quantity;
      current['returns'] = [
        ..._rows(current, 'returns'),
        {
          'quantity': quantity,
          'condition': condition,
          'at': DateTime.now().toUtc().toIso8601String(),
        },
      ];
    });
  }

  void pay(RowData rental, int amount, String method) {
    if (amount < 1 || amount > balance(rental)) {
      throw StateError('Enter an amount within the outstanding balance.');
    }
    _save('Recorded payment on ${rental['reference']}', (next) {
      final current = _rows(
        next,
        'rentals',
      ).singleWhere((row) => row['id'] == rental['id']);
      current['paid'] = (current['paid'] as int) + amount;
      current['payments'] = [
        ..._rows(current, 'payments'),
        {
          'amount': amount,
          'method': method,
          'at': DateTime.now().toUtc().toIso8601String(),
        },
      ];
    });
  }

  void dispose() => database.close();
}

class DateUtilsLocal {
  static DateTime day(DateTime date) =>
      DateTime.utc(date.year, date.month, date.day);
}
