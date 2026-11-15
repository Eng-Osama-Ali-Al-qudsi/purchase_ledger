Purchase Ledger — source correction patch 2.0.0+6

Apply this patch to the existing project root:
C:\Users\MC\StudioProjects\purchase_ledger

1. Close Android Studio/VS Code or stop any active Flutter build.
2. Extract this ZIP into the project root and allow the included files to overwrite.
3. Do NOT replace or delete your locally generated pubspec.lock. This patch intentionally
   excludes pubspec.lock because you already ran `flutter pub get` on the Windows machine.
4. Open PowerShell in the project root and run:

   dart format lib test
   flutter analyze

5. If analysis succeeds, run `flutter test`.
   If tests stop at harfbuzz_ffi/native_toolchain_c with a missing compiler, install
   Visual Studio's "Desktop development with C++" workload, including the MSVC x64/x86
   build tools, C++ CMake tools, and a Windows 10/11 SDK, then retry.
6. Run `flutter build apk --debug` and capture the complete final output.

Files included are only the files changed by this correction. No database schema,
accounting workflow, or application architecture was intentionally changed.

Verification status:
- Static path check: no missing relative Dart imports in the patched source tree.
- Flutter analyze/test/APK build: not run in this packaging environment.
