# One-command local validation for ventoy_sort_test.exe.
# Requires Python 3 and clang at C:\Program Files\LLVM\bin\clang.exe
# (the clang found on this machine).
#
# Usage:
#   python build_sort_test.py              # correctness tests
#   python build_sort_test.py --perf       # correctness + perf comparison
#   .\run_sort_test.cmd                    # correctness (Windows batch)
#   .\run_sort_test.cmd --perf            # correctness + perf (Windows batch)
#   make test_sort                         # correctness (if GNU make available)
#   make test_sort_perf                    # correctness + perf (if GNU make available)
#   make test_sort_perf SEED=42            # vary the rand() seed for variance studies

CLANG ?= C:\Program Files\LLVM\bin\clang.exe
PYTHON ?= python
SEED ?= 1

SRCDIR := $(shell dirname $(abspath $(lastword $(MAKEFILE_LIST))))
OUT := $(SRCDIR)/_build_sort_test/ventoy_sort_test.exe

.PHONY: test_sort test_sort_perf clean_sort

# Default correctness tests
test_sort: $(OUT)
	@echo "[run] $(OUT) --seed $(SEED)"
	@$(OUT) --seed $(SEED)

# Correctness + perf comparison
test_sort_perf:
	@$(PYTHON) $(SRCDIR)/build_sort_test.py --perf --seed $(SEED)

# Build the EXE (without perf) — used by test_sort
$(OUT): $(SRCDIR)/ventoy_sort_test.c $(SRCDIR)/build_sort_test.py
	@$(PYTHON) $(SRCDIR)/build_sort_test.py

clean_sort:
	-rm -f $(OUT)
