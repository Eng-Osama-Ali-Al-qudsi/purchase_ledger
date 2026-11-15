# Purchase Ledger V2 — Implementation Report

**Application:** دفتر المشتريات — Purchase Ledger  
**Source package version:** `2.0.0+6`  
**SQLite schema version:** `4`  
**Status:** Updated source package; Flutter SDK and Android-device verification remain pending.

## 1. Scope

The application maintains two separate purchase-accounting workflows:

- **Supplier account:** supplier registration, opening balances, credit invoices, invoice items, partial payments, payment allocation across invoices, supplier advances, advance allocation, returns, adjustments, payment reversals, and period-based supplier statements.
- **Daily purchases:** daily sheets with multiple operations and items, cash/partial/credit purchase records, later settlement of daily outstanding amounts, or direct posting to an existing supplier account without duplicating the same liability.

## 2. V4 implementation changes

### 2.1 Daily purchase item integrity and reporting

- Added the category name to the daily item domain model.
- Live detail and immutable handover-snapshot reads now join `purchase_categories` to expose the category label rather than exporting the database ID.
- Daily item persistence includes product ID, category ID, item name, quantity, unit, price, discount, tax, line total, seller, and item notes.
- Handover snapshots preserve the category label, seller, and item notes.
- Daily-sheet list totals now distinguish the amount paid at purchase from the amount paid later, and use the same basis as sheet details.

### 2.2 Payment method and receipt references

- Added `payment_method` to `daily_purchase_operations` with a safe `unspecified` default.
- The daily operation dialog now allows the method to be selected and edited while the sheet is still a draft.
- PDF and CSV handover reports display the saved method and distinguish cash, bank transfer, e-wallet, cheque, other, and unspecified.
- V4 backfills the initial method from a legacy cash-purchase payment only when its record is explicitly marked `Initial payment`; supplier-account daily operations use their linked initial supplier-payment record.
- Older supplier payments with a blank receipt number receive an ID-derived reference such as `PAY-00000001`; existing nonblank receipt numbers are preserved.

### 2.3 Idempotency and accounting integrity

- Daily operation idempotency retries compare the sheet, currency, total, accounting mode, supplier, amount paid, payment method, due date, notes, and all item fields.
- Supplier payment and daily outstanding payment retries compare the relevant financial and allocation inputs.
- Supplier-payment, invoice-payment, daily-operation, and daily-outstanding dialogs retain one idempotency key for the lifetime of the current save attempt instead of generating a new key on every retry.
- Database controls protect daily items and operation identity after handover, preserve handover snapshots as write-once, prevent deletion/rewrite of supplier payments and allocations, protect returns and opening balances, and prevent rewriting posted invoice financial fields. Invoice attachment metadata remains writable.
- The V4 backfill temporarily removes the V2 operation-update guard and restores it in `finally`, allowing existing handed-over records to be backfilled without weakening post-migration immutability.

### 2.4 Reports and business profile

- Added CSV export actions to supplier statements and daily handover reports.
- Supplier CSV includes shop name/number/address/phone, branch, manager, buyer, supplier details, movements, running balance, and totals.
- Daily PDF/CSV reports include category labels; operation-level payment and remaining amounts are shown once per operation rather than repeated on every item row. The CSV also separates item details from one-row-per-operation financial summaries.
- Supplier statement archives now include the business-profile snapshot used for the exported report.
- Editing the business profile preserves its original `created_at` timestamp.
- Added a first-run widget smoke test for the business-profile setup gate.
- Added mounted-context guards around asynchronous report sharing/printing paths.

### 2.5 Windows analyzer source corrections — revision 2.0.0+6

Based on the Windows `flutter analyze` output supplied after revision 2.0.0+5:

- Corrected both relative imports of `supplier_accounting_models.dart` to the `domain` directory.
- Added the missing `dart:convert` import for `jsonEncode`.
- Removed unresolved PDF shaper direction/alignment identifiers; the shaper now infers script direction and is right-aligned by the PDF layout widget.
- Passed `BuildContext` explicitly into daily-sheet theme helper methods.
- Added a `mounted` guard after the asynchronous supplier-invoice detail load.
- Removed the unused imports and redundant string interpolation reported by the analyzer.

The source patch has passed a repository-wide relative-import existence check. Flutter analysis, tests, and APK compilation have not yet been rerun on the owner's Windows machine.

## 3. Database architecture

Fresh-install sequence is base schema → V2 → V3 → V4. Existing databases use sequential versioned upgrades. The V4 migration is additive and repeatable.

The SQLite harness executed the actual fresh-install SQL in order and produced:

| Item | Result |
|---|---:|
| Application tables | 34 |
| Triggers | 52 |
| SQL migration errors | 0 |
| Foreign-key violations | 0 |

The V4 upgrade simulation against a V3 database verified legacy payment-method backfill, missing receipt-number backfill, restoration of the V2 post-handover update guard, and safe re-execution of the migration.

## 4. Accounting principles retained

- Store money as integer minor units and quantities as thousandths.
- Never aggregate different currencies into one balance.
- Positive supplier movement balance means amount due to supplier; negative balance means supplier advance/credit due to the business.
- Unallocated payments remain advances until allocated.
- Supplier-account daily purchases post once to the supplier movement ledger and do not create a duplicate daily-outstanding row.
- Posted financial history is reversed or amended through explicit append-only records rather than silently deleted.
- A handed-over daily sheet is frozen; later corrections are separate amendments.

## 5. Verification performed

The detailed results are in `Test_Report.md`. In summary:

- Fresh-install base + V2 + V3 + V4 SQL executed successfully in migration order.
- Existing V3 → V4 upgrade simulation passed, including legacy data backfill and repeatability.
- Acceptance scenarios A–D passed for supplier balances, advances, daily multi-item purchases, later settlement, and separation of supplier-account daily purchases from daily outstanding.
- Integrity scenario E passed for handover item locks, write-once snapshots, invoice financial immutability, supplier-payment no-delete behavior, and draft-only payment-method correction.
- Idempotency scenario F passed for supplier payments, daily operations, and daily outstanding payments.
- Foreign-key checks returned no violations.
- Static checks found no missing relative imports, stale `MyApp` reference, deprecated direct `DropdownButtonFormField.value` use, or `.withOpacity` calls in the scanned source.

## 6. Not yet verified

The packaging environment did not contain Flutter or Dart executables and could not reach package hosts. Therefore the following have **not** been run on this package:

- `flutter pub get` — the lockfile is stale and needs to be regenerated from the current `pubspec.yaml`.
- `dart format lib test`.
- `flutter analyze`.
- `flutter test` (including the newly added widget smoke test).
- `flutter build apk --debug`.
- Installation and end-to-end validation on an Android device.
- Real V1/V2/V3 database-file upgrade on a device and independent manual reconciliation of supplier statements.

No APK is included. The project remains a source implementation pending the above verification; it is not represented as production-certified.

## 7. Release notes

- Package version: `2.0.0+6`.
- SQLite schema version: `4`.
- Android application ID remains `com.example.purchase_ledger`; choose the official ID before publication.
- Preserve the approved Flutter/Gradle/AGP/Kotlin baseline. No framework or build-tool upgrade was made as part of this patch.
