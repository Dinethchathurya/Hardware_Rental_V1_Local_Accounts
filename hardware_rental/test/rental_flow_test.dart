import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hardware_rental/local_database.dart';
import 'package:hardware_rental/shop.dart';

void main() {
  test('rental, partial return and payment persist after reopening', () async {
    final folder = Directory.systemTemp.createTempSync('rental-flow-');
    addTearDown(() => folder.deleteSync(recursive: true));
    final path = '${folder.path}/shop.sqlite';
    final shop = Shop(LocalDatabase(path));
    try {
      await shop.registerOwner(
        'Demo shop',
        'Counter A',
        'Demo operator',
        'owner',
        'test-password-123',
      );
      shop.saveEquipment(null, 'DRILL', 'Hammer drill', 3, 150000);
      shop.saveCustomer(null, "O'Neil පාරිභෝගිකයා", '0700000000');
      shop.issue(
        shop.equipment.single,
        shop.customers.single,
        2,
        DateTime.now(),
      );
      expect(shop.available(shop.equipment.single), 1);
      expect(
        () => shop.issue(
          shop.equipment.single,
          shop.customers.single,
          2,
          DateTime.now(),
        ),
        throwsStateError,
      );
      final tomorrow = DateTime.now().add(const Duration(days: 1));
      shop.extendRental(shop.rentals.single, tomorrow, 50000);
      shop.returnItems(shop.rentals.single, 1, 'Good');
      shop.pay(shop.rentals.single, 100000, 'Cash');
      expect(
        () => shop.pay(shop.rentals.single, 260000, 'Cash'),
        throwsStateError,
      );
    } finally {
      shop.dispose();
    }

    final reopened = Shop(LocalDatabase(path));
    addTearDown(reopened.dispose);
    expect(reopened.customers.single['name'], "O'Neil පාරිභෝගිකයා");
    expect(reopened.available(reopened.equipment.single), 2);
    expect(reopened.remaining(reopened.rentals.single), 1);
    expect(reopened.balance(reopened.rentals.single), 250000);
    expect(reopened.activity.first['device'], 'Counter A');
    expect(reopened.activity.first['operator'], 'Demo operator');
  });

  test('a stale window cannot overwrite a saved transaction', () async {
    final folder = Directory.systemTemp.createTempSync('rental-writers-');
    addTearDown(() => folder.deleteSync(recursive: true));
    final path = '${folder.path}/shop.sqlite';
    final first = Shop(LocalDatabase(path));
    addTearDown(first.dispose);
    await first.registerOwner(
      'Shop',
      'Counter A',
      'Owner',
      'owner',
      'test-password-123',
    );
    final second = Shop(LocalDatabase(path));
    addTearDown(second.dispose);
    await second.signIn('owner', 'test-password-123');
    await first.signIn('owner', 'test-password-123');
    first.saveCustomer(null, 'Alice', '0111111111');
    expect(
      () => second.saveCustomer(null, 'Bob', '0222222222'),
      throwsStateError,
    );
    expect(second.customers, isEmpty);
    final reopened = Shop(LocalDatabase(path));
    addTearDown(reopened.dispose);
    expect(reopened.customers.single['name'], 'Alice');
  });
  test(
    'existing local data survives registration and staff permissions persist',
    () async {
      final folder = Directory.systemTemp.createTempSync('rental-accounts-');
      addTearDown(() => folder.deleteSync(recursive: true));
      final path = '${folder.path}/shop.sqlite';
      final legacy = LocalDatabase(path);
      legacy.write({
        'name': 'Existing hardware shop',
        'customers': [
          {'id': 'customer-a', 'name': 'Alice', 'phone': '001'},
        ],
      });
      legacy.close();
      final shop = Shop(LocalDatabase(path));
      addTearDown(shop.dispose);
      expect(shop.hasOwner, false);
      expect(() => shop.saveCustomer(null, 'Bob', '002'), throwsStateError);
      await shop.registerOwner(
        shop.name,
        'PC One',
        'Owner',
        'owner',
        'owner-password-123',
      );
      await shop.addStaff('Cashier', 'cashier', 'staff-password-123');
      final staffId = shop.staff.last['id'] as String;
      shop.signOut();
      await expectLater(
        shop.signIn('cashier', 'wrong-password'),
        throwsStateError,
      );
      await shop.signIn(' CASHIER ', 'staff-password-123');
      expect(shop.operatorName, 'Cashier');
      expect(() => shop.saveSettings('Renamed', 'PC Two'), throwsStateError);
      shop.saveCustomer(null, 'Bob', '002');
      expect(shop.activity.first['userId'], staffId);
      expect(shop.activity.first['device'], 'PC One');
      shop.signOut();
      await shop.signIn('owner', 'owner-password-123');
      shop.setStaffActive(staffId, false);

      final reopened = Shop(LocalDatabase(path));
      addTearDown(reopened.dispose);
      expect(reopened.signedIn, false);
      await expectLater(
        reopened.signIn('cashier', 'staff-password-123'),
        throwsStateError,
      );
      await reopened.signIn('owner', 'owner-password-123');
      expect(reopened.customers.map((row) => row['name']).toList(), [
        'Alice',
        'Bob',
      ]);
    },
  );
}
