import 'dart:async';

// Keep compatibility with stable Flutter SDKs that bundle Material.
// ignore: deprecated_member_use
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb;

import 'open_storage.dart';
import 'shop.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    final storage = await openStorage();
    try {
      runApp(RentalApp(shop: Shop(storage)));
    } catch (_) {
      storage.close();
      rethrow;
    }
  } catch (error) {
    runApp(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: Text(
              'Unable to open the local workspace.\n$error',
              textAlign: TextAlign.center,
            ),
          ),
        ),
      ),
    );
  }
}

class RentalApp extends StatefulWidget {
  const RentalApp({super.key, required this.shop});
  final Shop shop;

  @override
  State<RentalApp> createState() => _RentalAppState();
}

class _RentalAppState extends State<RentalApp> {
  @override
  Widget build(BuildContext context) => MaterialApp(
    debugShowCheckedModeBanner: false,
    title: kIsWeb ? 'Hardware Rental Preview' : 'Hardware Rental',
    theme: ThemeData(
      useMaterial3: true,
      colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF006451)),
      scaffoldBackgroundColor: const Color(0xFFF5F7F6),
      inputDecorationTheme: const InputDecorationTheme(
        border: OutlineInputBorder(),
      ),
    ),
    home: widget.shop.signedIn
        ? Workspace(
            shop: widget.shop,
            onSignOut: () => setState(widget.shop.signOut),
          )
        : AccountGate(
            shop: widget.shop,
            onAuthenticated: () => setState(() {}),
          ),
  );

  @override
  void dispose() {
    widget.shop.dispose();
    super.dispose();
  }
}

typedef FieldSpec = ({
  String label,
  String initial,
  List<String> choices,
  bool secret,
});

FieldSpec field(
  String label, [
  String initial = '',
  List<String> choices = const [],
]) => (label: label, initial: initial, choices: choices, secret: false);

FieldSpec passwordField(String label) =>
    (label: label, initial: '', choices: const [], secret: true);

class AccountGate extends StatelessWidget {
  const AccountGate({
    super.key,
    required this.shop,
    required this.onAuthenticated,
  });
  final Shop shop;
  final VoidCallback onAuthenticated;

  @override
  Widget build(BuildContext context) {
    final register = !shop.hasOwner;
    final action = register ? 'Register shop' : 'Sign in';
    return Scaffold(
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: SizedBox(
            width: 460,
            child: Card(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Align(
                      alignment: Alignment.centerLeft,
                      child: Icon(Icons.storefront, size: 36),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      shop.name,
                      style: Theme.of(context).textTheme.headlineMedium,
                    ),
                    const SizedBox(height: 12),
                    Text(
                      register
                          ? 'Set up this computer and create the owner account.'
                          : 'Sign in with your local owner or staff account.',
                    ),
                    if (kIsWeb)
                      const Padding(
                        padding: EdgeInsets.only(top: 12),
                        child: Text(
                          'Browser preview. Use sample data and a test password.',
                        ),
                      ),
                    const SizedBox(height: 24),
                    FilledButton(
                      onPressed: () async {
                        final done = await showDialog<bool>(
                          context: context,
                          barrierDismissible: false,
                          builder: (_) => EntryDialog(
                            title: action,
                            submitLabel: action,
                            fields: [
                              if (register) ...[
                                field('Shop name', shop.name),
                                field('Computer name', shop.device),
                                field('Owner name'),
                              ],
                              field('Username'),
                              passwordField('Password'),
                              if (register) passwordField('Confirm password'),
                            ],
                            save: (v) async {
                              if (!register) return shop.signIn(v[0], v[1]);
                              if (v[4] != v[5]) {
                                throw StateError('Passwords do not match.');
                              }
                              return shop.registerOwner(
                                v[0],
                                v[1],
                                v[2],
                                v[3],
                                v[4],
                              );
                            },
                          ),
                        );
                        if (done == true && context.mounted) onAuthenticated();
                      },
                      child: Text(action),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class Workspace extends StatefulWidget {
  const Workspace({super.key, required this.shop, required this.onSignOut});
  final VoidCallback onSignOut;
  final Shop shop;

  @override
  State<Workspace> createState() => _WorkspaceState();
}

class _WorkspaceState extends State<Workspace> {
  static const pages = [
    'Overview',
    'Equipment',
    'Customers',
    'Rentals',
    'Activity',
    'Settings',
  ];
  static const icons = [
    Icons.dashboard_outlined,
    Icons.handyman_outlined,
    Icons.people_outline,
    Icons.receipt_long_outlined,
    Icons.history,
    Icons.settings_outlined,
  ];

  int page = 0;
  String search = '';
  String rentalFilter = 'All';
  Shop get shop => widget.shop;

  String money(int cents) => 'LKR ${(cents / 100).toStringAsFixed(2)}';
  String date(DateTime day) => day.toIso8601String().substring(0, 10);
  bool overdue(RowData rental) =>
      shop.remaining(rental) > 0 &&
      DateTime.parse(
        rental['due'] as String,
      ).isBefore(DateUtilsLocal.day(DateTime.now()));

  int integer(String value) {
    final number = int.tryParse(value);
    if (number == null || number < 0 || number > 99999) {
      throw const FormatException('Enter a whole quantity from 0 to 99,999.');
    }
    return number;
  }

  int cents(String value) {
    if (!RegExp(r'^\d{1,9}(\.\d{1,2})?$').hasMatch(value)) {
      throw const FormatException(
        'Enter an amount with up to two decimal places.',
      );
    }
    final parts = value.split('.');
    return int.parse(parts[0]) * 100 +
        (parts.length == 2 ? int.parse(parts[1].padRight(2, '0')) : 0);
  }

  Future<void> form(
    String title,
    List<FieldSpec> fields,
    FutureOr<void> Function(List<String>) save,
  ) async {
    final done = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => EntryDialog(title: title, fields: fields, save: save),
    );
    if (done == true && mounted) setState(() {});
  }

  void equipment([RowData? item]) => form(
    item == null ? 'Add equipment' : 'Edit equipment',
    [
      field('Item code', item?['code'] as String? ?? ''),
      field('Equipment name', item?['name'] as String? ?? ''),
      field('Stock quantity', item?['stock']?.toString() ?? '1'),
      field(
        'Daily rate (LKR)',
        item == null ? '' : ((item['rate'] as int) / 100).toStringAsFixed(2),
      ),
    ],
    (v) => shop.saveEquipment(
      item?['id'] as String?,
      v[0],
      v[1],
      integer(v[2]),
      cents(v[3]),
    ),
  );

  void customer([RowData? customer]) =>
      form(customer == null ? 'Add customer' : 'Edit customer', [
        field('Customer name', customer?['name'] as String? ?? ''),
        field('Phone number', customer?['phone'] as String? ?? ''),
      ], (v) => shop.saveCustomer(customer?['id'] as String?, v[0], v[1]));

  void issue() {
    final items = shop.equipment
        .where((item) => shop.available(item) > 0)
        .toList();
    final customers = shop.customers;
    if (items.isEmpty || customers.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Add a customer and equipment with available stock first.',
          ),
        ),
      );
      return;
    }
    final itemChoices = items
        .map(
          (item) =>
              '${item['code']} · ${item['name']} (${shop.available(item)} available)',
        )
        .toList();
    final customerChoices = [
      for (final (index, row) in customers.indexed)
        '${index + 1}. ${row['name']} · ${row['phone']}',
    ];
    form(
      'Issue rental',
      [
        field('Customer', customerChoices.first, customerChoices),
        field('Equipment', itemChoices.first, itemChoices),
        field('Quantity', '1'),
        field('Due date (YYYY-MM-DD)', date(DateTime.now())),
      ],
      (v) {
        final due = DateTime.tryParse(v[3]);
        if (due == null || date(due) != v[3]) {
          throw const FormatException('Enter a valid date as YYYY-MM-DD.');
        }
        shop.issue(
          items[itemChoices.indexOf(v[1])],
          customers[customerChoices.indexOf(v[0])],
          integer(v[2]),
          due,
        );
      },
    );
  }

  void extendRental(RowData rental) => form(
    'Extend rental',
    [
      field('New due date (YYYY-MM-DD)'),
      field('Additional agreed charge (LKR)', '0.00'),
    ],
    (v) {
      final due = DateTime.tryParse(v[0]);
      if (due == null || date(due) != v[0]) {
        throw const FormatException('Enter a valid date as YYYY-MM-DD.');
      }
      shop.extendRental(rental, due, cents(v[1]));
    },
  );

  void returnItems(RowData rental) => form('Record return', [
    field('Quantity returned', shop.remaining(rental).toString()),
    field('Return condition', 'Good'),
  ], (v) => shop.returnItems(rental, integer(v[0]), v[1]));

  void payment(RowData rental) => form('Record payment', [
    field('Amount (LKR)', (shop.balance(rental) / 100).toStringAsFixed(2)),
    field('Payment method', 'Cash', ['Cash', 'Card', 'Bank transfer', 'Other']),
  ], (v) => shop.pay(rental, cents(v[0]), v[1]));

  void details(RowData rental) {
    final payments = (rental['payments'] as List).cast<RowData>();
    final returns = (rental['returns'] as List).cast<RowData>();
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Rental ${rental['reference']}'),
        content: SizedBox(
          width: 460,
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('${rental['customer']} · ${rental['equipment']}'),
                Text(
                  'Issued ${(rental['issued'] as String).substring(0, 10)} · Due ${(rental['due'] as String).substring(0, 10)}',
                ),
                Text(
                  'Quantity ${rental['quantity']} · Returned ${rental['returned']}',
                ),
                Text(
                  'Total ${money(rental['total'] as int)} · Balance ${money(shop.balance(rental))}',
                ),
                const Divider(height: 28),
                const Text(
                  'Returns',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                if (returns.isEmpty) const Text('No returns recorded.'),
                for (final row in returns)
                  Text(
                    '${row['quantity']} · ${row['condition']} · ${date(DateTime.parse(row['at'] as String).toLocal())}',
                  ),
                const SizedBox(height: 16),
                const Text(
                  'Payments',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                if (payments.isEmpty) const Text('No payments recorded.'),
                for (final row in payments)
                  Text(
                    '${money(row['amount'] as int)} · ${row['method']} · ${date(DateTime.parse(row['at'] as String).toLocal())}',
                  ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  bool matches(Iterable<Object?> values) =>
      values.any((value) => value.toString().toLowerCase().contains(search));

  Widget rows(Iterable<Widget> children, String empty) {
    final items = children.toList();
    if (items.isEmpty) {
      return Padding(padding: const EdgeInsets.all(24), child: Text(empty));
    }
    return Column(children: items);
  }

  Widget overview() {
    final active = shop.rentals
        .where((row) => shop.remaining(row) > 0)
        .toList();
    final dueToday = active
        .where(
          (row) =>
              row['due'] ==
              DateUtilsLocal.day(DateTime.now()).toIso8601String(),
        )
        .length;
    final outstanding = shop.rentals.fold(
      0,
      (total, row) => total + shop.balance(row),
    );
    final metrics = {
      'Active rentals': '${active.length}',
      'Due today': '$dueToday',
      'Overdue': '${active.where(overdue).length}',
      'Outstanding': money(outstanding),
    };
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            for (final metric in metrics.entries)
              Card(
                child: SizedBox(
                  width: 166,
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(metric.key),
                        const SizedBox(height: 8),
                        Text(
                          metric.value,
                          style: Theme.of(context).textTheme.titleLarge,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: 24),
        Text('Recent activity', style: Theme.of(context).textTheme.titleLarge),
        rows(shop.activity.take(5).map(activityTile), 'No activity yet.'),
      ],
    );
  }

  Widget activityTile(RowData row) => ListTile(
    leading: const Icon(Icons.history),
    title: Text(row['event'] as String),
    subtitle: Text(
      '${row['operator']} · ${row['device']} · ${DateTime.parse(row['at'] as String).toLocal().toString().substring(0, 16)}',
    ),
  );

  Widget rentalTile(RowData rental) {
    final status = shop.remaining(rental) == 0
        ? 'Returned'
        : overdue(rental)
        ? 'Overdue'
        : 'Active';
    return Card(
      child: ListTile(
        onTap: () => details(rental),
        title: Text('${rental['equipment']} · ${rental['customer']}'),
        subtitle: Text(
          '${rental['reference']} · $status · Due ${(rental['due'] as String).substring(0, 10)}\n'
          '${shop.remaining(rental)} of ${rental['quantity']} out · Balance ${money(shop.balance(rental))}',
        ),
        isThreeLine: true,
        trailing: PopupMenuButton<String>(
          tooltip: 'Rental actions',
          onSelected: (action) {
            switch (action) {
              case 'return':
                returnItems(rental);
              case 'pay':
                payment(rental);
              case 'extend':
                extendRental(rental);
              case 'details':
                details(rental);
            }
          },
          itemBuilder: (_) => [
            const PopupMenuItem(value: 'details', child: Text('View details')),
            if (shop.remaining(rental) > 0)
              const PopupMenuItem(
                value: 'return',
                child: Text('Record return'),
              ),
            if (shop.remaining(rental) > 0)
              const PopupMenuItem(
                value: 'extend',
                child: Text('Extend rental'),
              ),
            if (shop.balance(rental) > 0)
              const PopupMenuItem(value: 'pay', child: Text('Record payment')),
          ],
        ),
      ),
    );
  }

  Widget content() => switch (page) {
    0 => overview(),
    1 => rows(
      shop.equipment
          .where((row) => matches([row['name'], row['code']]))
          .map(
            (row) => Card(
              child: ListTile(
                leading: const Icon(Icons.handyman_outlined),
                title: Text(row['name'] as String),
                subtitle: Text(
                  '${row['code']} · ${shop.available(row)} of ${row['stock']} available · ${money(row['rate'] as int)} / day',
                ),
                trailing: IconButton(
                  tooltip: 'Edit equipment',
                  icon: const Icon(Icons.edit_outlined),
                  onPressed: () => equipment(row),
                ),
              ),
            ),
          ),
      'No matching equipment.',
    ),
    2 => rows(
      shop.customers
          .where((row) => matches([row['name'], row['phone']]))
          .map(
            (row) => Card(
              child: ListTile(
                leading: const Icon(Icons.person_outline),
                title: Text(row['name'] as String),
                subtitle: Text(row['phone'] as String),
                trailing: IconButton(
                  tooltip: 'Edit customer',
                  icon: const Icon(Icons.edit_outlined),
                  onPressed: () => customer(row),
                ),
              ),
            ),
          ),
      'No matching customers.',
    ),
    3 => Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 8,
          children: [
            for (final filter in [
              'All',
              'Active',
              'Due today',
              'Overdue',
              'Unpaid',
            ])
              ChoiceChip(
                label: Text(filter),
                selected: rentalFilter == filter,
                onSelected: (_) => setState(() => rentalFilter = filter),
              ),
          ],
        ),
        rows(
          shop.rentals
              .where((row) {
                final included = switch (rentalFilter) {
                  'Active' => shop.remaining(row) > 0,
                  'Due today' =>
                    shop.remaining(row) > 0 &&
                        row['due'] ==
                            DateUtilsLocal.day(
                              DateTime.now(),
                            ).toIso8601String(),
                  'Overdue' => overdue(row),
                  'Unpaid' => shop.balance(row) > 0,
                  _ => true,
                };
                return included &&
                    matches([
                      row['reference'],
                      row['customer'],
                      row['equipment'],
                    ]);
              })
              .map(rentalTile),
          'No matching rentals.',
        ),
      ],
    ),
    4 => rows(shop.activity.map(activityTile), 'No activity yet.'),
    _ => Card(
      child: Column(
        children: [
          ListTile(title: const Text('Shop name'), subtitle: Text(shop.name)),
          ListTile(
            title: const Text('Device name'),
            subtitle: Text(shop.device),
          ),
          ListTile(
            title: const Text('Signed in as'),
            subtitle: Text(shop.operatorName),
          ),
          ListTile(title: const Text('Currency'), subtitle: const Text('LKR')),
          if (shop.isOwner) ...[
            const Divider(),
            ListTile(
              title: const Text('Staff accounts'),
              trailing: TextButton.icon(
                onPressed: () => form(
                  'Add staff',
                  [
                    field('Staff name'),
                    field('Username'),
                    passwordField('Password'),
                    passwordField('Confirm password'),
                  ],
                  (v) {
                    if (v[2] != v[3]) {
                      throw StateError('Passwords do not match.');
                    }
                    return shop.addStaff(v[0], v[1], v[2]);
                  },
                ),
                icon: const Icon(Icons.person_add_alt),
                label: const Text('Add staff'),
              ),
            ),
            for (final account in shop.staff.where(
              (row) => row['role'] == 'Staff',
            ))
              SwitchListTile(
                title: Text(account['name'] as String),
                subtitle: Text(account['username'] as String),
                value: account['active'] as bool,
                onChanged: (active) {
                  try {
                    shop.setStaffActive(account['id'] as String, active);
                    setState(() {});
                  } on StateError catch (error) {
                    ScaffoldMessenger.of(
                      context,
                    ).showSnackBar(SnackBar(content: Text(error.message)));
                  }
                },
              ),
          ],
        ],
      ),
    ),
  };

  Widget action() => switch (page) {
    1 => FilledButton.icon(
      onPressed: () => equipment(),
      icon: const Icon(Icons.add),
      label: const Text('Add equipment'),
    ),
    2 => FilledButton.icon(
      onPressed: () => customer(),
      icon: const Icon(Icons.person_add_alt),
      label: const Text('Add customer'),
    ),
    3 || 0 => FilledButton.icon(
      onPressed: issue,
      icon: const Icon(Icons.add),
      label: const Text('Issue rental'),
    ),
    5 when shop.isOwner => OutlinedButton(
      onPressed: () => form('Edit shop settings', [
        field('Shop name', shop.name),
        field('Device name', shop.device),
      ], (v) => shop.saveSettings(v[0], v[1])),
      child: const Text('Edit settings'),
    ),
    _ => const SizedBox.shrink(),
  };

  @override
  Widget build(BuildContext context) {
    final wide = MediaQuery.sizeOf(context).width >= 950;
    return Scaffold(
      body: SafeArea(
        child: Row(
          children: [
            NavigationRail(
              backgroundColor: const Color(0xFFE8F1EE),
              extended: wide,
              selectedIndex: page,
              leading: const Padding(
                padding: EdgeInsets.symmetric(vertical: 16),
                child: Icon(Icons.storefront),
              ),
              onDestinationSelected: (index) => setState(() {
                page = index;
                search = '';
              }),
              destinations: [
                for (var i = 0; i < pages.length; i++)
                  NavigationRailDestination(
                    icon: Icon(icons[i]),
                    label: Text(pages[i]),
                  ),
              ],
            ),
            Expanded(
              child: ListView(
                key: PageStorageKey(page),
                padding: const EdgeInsets.all(24),
                children: [
                  Wrap(
                    spacing: 16,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      Text(
                        '${shop.name} / ${shop.device} / ${shop.operatorName}',
                        style: Theme.of(context).textTheme.labelLarge,
                      ),
                      TextButton.icon(
                        onPressed: widget.onSignOut,
                        icon: const Icon(Icons.logout),
                        label: const Text('Sign out'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  Wrap(
                    alignment: WrapAlignment.spaceBetween,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    spacing: 12,
                    runSpacing: 12,
                    children: [
                      Text(
                        pages[page],
                        style: Theme.of(context).textTheme.headlineMedium,
                      ),
                      action(),
                    ],
                  ),
                  const SizedBox(height: 16),
                  if (page >= 1 && page <= 3) ...[
                    TextField(
                      key: ValueKey(page),
                      onChanged: (value) =>
                          setState(() => search = value.trim().toLowerCase()),
                      decoration: InputDecoration(
                        prefixIcon: const Icon(Icons.search),
                        hintText: 'Search ${pages[page].toLowerCase()}',
                      ),
                    ),
                    const SizedBox(height: 12),
                  ],
                  if (kIsWeb)
                    const Padding(
                      padding: EdgeInsets.only(bottom: 12),
                      child: Text(
                        'Browser preview • Data stays in this browser. Use sample data.',
                      ),
                    ),
                  content(),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class EntryDialog extends StatefulWidget {
  const EntryDialog({
    super.key,
    required this.title,
    required this.fields,
    required this.save,
    this.submitLabel = 'Save',
  });
  final String title;
  final List<FieldSpec> fields;
  final FutureOr<void> Function(List<String>) save;
  final String submitLabel;

  @override
  State<EntryDialog> createState() => _EntryDialogState();
}

class _EntryDialogState extends State<EntryDialog> {
  late final controllers = widget.fields
      .map((field) => TextEditingController(text: field.initial))
      .toList();
  String? error;

  bool busy = false;

  Future<void> submit() async {
    if (busy) return;
    final values = [
      for (final (index, controller) in controllers.indexed)
        widget.fields[index].secret ? controller.text : controller.text.trim(),
    ];
    if (values.any((value) => value.isEmpty)) {
      setState(() => error = 'Complete all fields.');
      return;
    }
    setState(() {
      busy = true;
      error = null;
    });
    try {
      await widget.save(values);
      if (mounted) Navigator.pop(context, true);
    } catch (exception) {
      if (!mounted) return;
      setState(() {
        busy = false;
        error = switch (exception) {
          FormatException(:final message) => message,
          StateError(:final message) => message,
          _ => 'Unable to save this change.',
        };
      });
    }
  }

  @override
  void dispose() {
    for (final controller in controllers) {
      controller.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !busy,
    child: AlertDialog(
      title: Text(widget.title),
      content: SizedBox(
        width: 400,
        child: SingleChildScrollView(
          child: Column(
            children: [
              for (final (index, field) in widget.fields.indexed)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: field.choices.isEmpty
                      ? TextField(
                          controller: controllers[index],
                          enabled: !busy,
                          obscureText: field.secret,
                          autocorrect: !field.secret,
                          enableSuggestions: !field.secret,
                          onSubmitted: index == controllers.length - 1
                              ? (_) => submit()
                              : null,
                          decoration: InputDecoration(labelText: field.label),
                        )
                      : DropdownButtonFormField<String>(
                          initialValue: field.initial,
                          isExpanded: true,
                          decoration: InputDecoration(labelText: field.label),
                          items: field.choices
                              .map(
                                (value) => DropdownMenuItem(
                                  value: value,
                                  child: Text(
                                    value,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              )
                              .toList(),
                          onChanged: busy
                              ? null
                              : (value) =>
                                    controllers[index].text = value ?? '',
                        ),
                ),
              if (error != null)
                Text(
                  error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: busy ? null : () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: busy ? null : submit,
          child: Text(busy ? 'Saving…' : widget.submitLabel),
        ),
      ],
    ),
  );
}
