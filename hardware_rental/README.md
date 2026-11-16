# Hardware Rental Desktop

First V1 milestone for a single shop and computer. Windows is the target. A macOS runner is included for development.

## Test in Chrome on macOS

Open a terminal in this directory. Flutter and Google Chrome must be installed.

```sh
flutter pub get
```

```sh
flutter run -d chrome --web-hostname=localhost --web-port=8080
```

Chrome opens the same rental workflow as the desktop app. Use sample customers and
transactions. Data stays in the browser profile at this address and survives a
reload. Use the same host and port on later runs to see it again. Clearing site
data or using another profile starts a separate workspace. The browser preview
does not access the desktop SQLite database.

If port 8080 is busy, choose a free port and reuse it on later runs.

## Open the prebuilt browser preview

From the extracted ZIP's top-level folder (the folder containing
`hardware_rental` and `web_preview`), run:

```sh
python3 -m http.server 8080 --bind 127.0.0.1 --directory web_preview
```

Open `http://127.0.0.1:8080` in your browser. Stop the server with Ctrl+C.
The prebuilt preview and the Chrome development command use different hostnames
by default, so each has its own browser data.

## Run the desktop app locally

Install Flutter with desktop support. On Windows, configure Visual Studio with the Desktop development with C++ workload. On macOS, configure Xcode. Run these commands from this directory.

```sh
flutter pub get
```

```sh
flutter run -d windows
```

For macOS development, use `flutter run -d macos`.

## Try the rental workflow

1. Register the shop and its first owner account. Sign in again after restarting. Owners can add, deactivate, and reactivate staff under Settings.
2. Register an equipment item with a code, quantity, and daily rate in LKR.
3. Register a customer with a phone number.
4. Issue a rental for one equipment type. Select a due date and the quantity.
5. Open the rental action menu to extend the due date with an agreed charge, record a partial or full return, or take a payment. Open the rental details to view its history.
6. Use Overview for due and overdue counts, Rentals for search and filters, and Activity for saved actions.

The rental estimate counts both issue and due dates. Extensions add the agreed amount entered by the operator. All returned units go back into available stock. Condition text is recorded for reference. This milestone supports quantity-based inventory and payments against a fixed rental amount.

Data is stored in `hardware_rental.sqlite` in the operating system's application support directory. Each save is atomic, with protection against stale writes from a second instance. Accounts and their assigned roles are local. Audit events record the signed-in user and computer. Future work includes cross-device account and device registration, PostgreSQL tenant schemas, synchronization and conflict review, multi-item checkout, stock condition management, deposits, late fees, receipt printing, and the owner dashboard.

## Verify

```sh
flutter analyze
```

```sh
flutter test
```
