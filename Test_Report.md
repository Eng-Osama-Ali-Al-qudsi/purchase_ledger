# Purchase Ledger V2 — Test and Verification Report

**Package version:** `2.0.0+6`  
**SQLite schema:** `4`  
**Overall status:** Database-level checks passed; Flutter/Dart and Android validation remain pending.

## Windows validation output received for revision 2.0.0+5

The owner supplied the following command results on 2026-11-12:

- `flutter pub get`: PASS — dependencies resolved successfully.
- `dart format`: NOT RUN — the command was issued without paths. Use `dart format lib test`.
- `flutter analyze`: FAIL — 39 reported issues. The primary errors were incorrect relative
  imports for the supplier accounting models, missing `dart:convert`, unsupported PDF
  shaper enum identifiers, and helper methods referencing an out-of-scope `context`.
  Revision 2.0.0+6 includes source corrections for these reported issues.
- `flutter test`: BLOCKED before test execution — `harfbuzz_ffi` could not build its
  Windows native asset because the Visual Studio C++ compiler component is missing.
  This is a host toolchain setup failure, not a failed test assertion.
- `flutter build apk --debug`: the supplied output ends at `Running Gradle task
  'assembleDebug'...`; no final success or failure line was included, so the APK result
  remains UNKNOWN.

The corrective source patch has not yet been verified by a fresh Windows run.

## 1. Fresh-install migration test

The test harness executed the SQL statements from the base schema, V2, V3, and V4 in the same order used by the application. The V2 allocation-trigger replacement and V3 trigger replacements were applied explicitly; the V4 operation-update guard drop/restore was also represented.

| Check | Result |
|---|---|
| Base schema SQL | PASS |
| V2 migration SQL | PASS |
| V3 migration SQL | PASS |
| V4 migration SQL | PASS |
| Application tables | 34 |
| Triggers after V4 | 52 |
| Foreign-key check | PASS — no violations |

## 2. Existing V3 → V4 upgrade test

A V3-shaped database was seeded with handed-over daily operations and supplier payments, then upgraded through V4.

| Check | Result |
|---|---|
| Legacy cash-purchase initial method recovered from `cash_purchase_payments` | PASS — `wallet` |
| Supplier-account initial method recovered from linked `supplier_payments` | PASS — `cheque` |
| Blank supplier receipt assigned ID-derived reference | PASS — `PAY-00000001` in the test fixture |
| Existing nonblank receipt preserved | PASS |
| V2 post-handover operation-update guard restored | PASS |
| V4 migration re-execution | PASS — no duplicate column/trigger failure and no overwrite of recovered values |
| Foreign-key check | PASS — no violations |

## 3. Accounting acceptance scenarios

All monetary values below are stored as integer minor units in the test database; the displayed scenario labels are in YER.

### A — Partial supplier payments

- Supplier invoice: 1,000,000 YER.
- Three payments: 100,000 + 200,000 + 150,000 YER.
- Expected supplier liability: 550,000 YER.
- Result: **PASS**.

### B — Supplier advance and later invoice

- Existing liability after scenario A: 550,000 YER.
- New advance: 600,000 YER.
- Later invoice: 200,000 YER, with 200,000 allocated from the advance.
- Remaining net supplier liability after the unallocated 400,000 advance offsets the existing liability: 150,000 YER.
- Result: **PASS**.

### C — Multi-item daily purchase and later settlement

- One daily operation with 10 items.
- Total: 10,000 YER; amount paid at purchase: 2,000 YER; initial daily outstanding: 8,000 YER.
- Later settlement: 3,000 YER; remaining daily outstanding: 5,000 YER.
- Payment method `bank_transfer` persisted.
- Result: **PASS**.

### D — Daily purchase posted to supplier account

- Daily operation total: 2,000 YER; initial payment: 1,000 YER.
- Exactly one supplier-account purchase movement was recorded.
- No duplicate `daily_purchase_outstandings` row was created for the same operation.
- A correction to the linked initial payment method is permitted while the sheet is still `DRAFT`.
- Result: **PASS**.

### E — Database integrity after handover

- Editing daily item details after handover is blocked.
- Rewriting an already captured snapshot, including a partial snapshot rewrite, is blocked.
- Rewriting a posted invoice's financial total or primary key is blocked.
- Changing a linked initial supplier-payment method after handover is blocked.
- Deleting a supplier payment is blocked; reversal records remain the correction path.
- Attachment metadata can still be added to supplier payments and invoices.
- Result: **PASS**.

### F — Idempotency uniqueness

- Duplicate supplier-payment idempotency keys are rejected by the database unique index.
- Duplicate daily-operation idempotency keys are rejected.
- Duplicate daily-outstanding-payment idempotency keys are rejected.
- Result: **PASS**.

## 4. Static source checks

A targeted scan covered the 52 Dart files for relative imports, declared external packages, and selected deprecated/starter-code patterns. This scan is not a Dart parser.

| Check | Result |
|---|---|
| Relative imports | PASS — no missing relative paths |
| Starter `MyApp` reference | PASS — none found |
| Direct deprecated `DropdownButtonFormField.value` argument | PASS — none found |
| `.withOpacity` usage | PASS — none found |
| `pubspec.yaml` parse | PASS |
| Source review: daily PDF/CSV operation totals are not repeated on each item row | PASS |
| Flutter/Dart SDK execution in this environment | NOT AVAILABLE |

The SQL checks used Python's SQLite engine against the project's migration SQL. They are database-level tests, not a substitute for running the Flutter application through `sqflite` on Android.

## 5. Required local verification

Run these commands from the project directory on the approved Windows environment (Flutter 3.47.2 / Dart 3.13.2):

```powershell
flutter pub get
dart format lib test
flutter analyze
flutter test
flutter build apk --debug
```

`pubspec.lock` is stale relative to the current `pubspec.yaml` and is missing several direct dependencies; `flutter pub get` is therefore required to regenerate/resolve it before relying on the lockfile or building.

Then install the debug APK and verify at minimum:

1. Fresh installation and business-profile setup.
2. Supplier invoice, multiple partial payments, advance allocation, return, adjustment, and reversal.
3. Daily sheet with multiple operations and items, including all payment methods.
4. `daily_outstanding` versus `supplier_account` separation.
5. Prepare handover, hand over, print/share PDF, export CSV, and create amendments.
6. Upgrade an actual V3 database file containing handed-over operations and blank historical receipt numbers.
7. Compare supplier statements and daily totals against an independent manual calculation.

**No Flutter test result, APK build result, device test, or production certification is claimed in this report.**
