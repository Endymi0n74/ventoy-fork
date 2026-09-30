@echo off
rem // One-command local validation for the Ventoy sort test harness.
rem // Compiles and runs ventoy_sort_test.exe using the clang found on
rem // this machine (C:\Program Files\LLVM\bin\clang.exe).
rem //
rem // Usage:   run_sort_test.cmd          # correctness tests only
rem //    or:   run_sort_test.cmd --perf   # also run perf comparison
rem //    or:   python build_sort_test.py
rem //
rem // Pass --perf to enable the optional VENTOY_SORT_TEST_PERF build path.
rem // The script path is hardcoded relative to the workspace root to avoid
rem // cmd /c mangling %~dp0.

python "ventoy\build_sort_test.py" %*

