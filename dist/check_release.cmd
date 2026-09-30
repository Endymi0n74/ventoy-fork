@echo off
setlocal EnableExtensions

rem // ============================================================
rem // check_release.cmd - end-to-end validation of a GitHub release
rem // of ventoy-fork, in one command:
rem //
rem //   1. download the release archives + SHA256SUMS (gh CLI)
rem //   2. verify the SHA256 checksums (all SHA256SUMS entries)
rem //   3. extract the zip
rem //   4. run the perf sweep --sweep 30 from the extraction and
rem //      archive the reference log into the release check dir
rem //      (set SKIP_SWEEP=1 to skip - it takes several minutes)
rem //   5. run the sort-test harness from the extraction (RC=0)
rem //
rem // Usage (from the repo root or the workspace root):
rem //   dist\check_release.cmd
rem //   set SKIP_SWEEP=1
rem //   set SWEEP_OUT=D:\somewhere   (keep the sweep reference log)
rem //   set GH_REPO=owner/name
rem //   set TAG=v1.2.0
rem //   dist\check_release.cmd
rem //
rem // Requires: gh (GitHub CLI), python 3, clang (see
rem // build_sort_test.py for the CLANG lookup order: $CLANG, then
rem // the default LLVM path, then PATH). The temp dir is always
rem // removed on exit. Exits 0 on PASS, 1 on any failure.
rem // ============================================================

if not defined GH_REPO set "GH_REPO=Endymi0n74/ventoy-fork"
if not defined TAG set "TAG=v1.1.17-ventoy-sort"

set "WORKDIR=%TEMP%\check_release_%RANDOM%"

echo [check_release] repo=%GH_REPO% tag=%TAG%
echo [check_release] workdir=%WORKDIR%
echo.

where gh >nul 2>nul
if errorlevel 1 (
    echo [check_release] ERROR: gh CLI not found on PATH.
    goto :fail
)
where python >nul 2>nul
if errorlevel 1 (
    echo [check_release] ERROR: python not found on PATH.
    goto :fail
)

mkdir "%WORKDIR%" 2>nul
if not exist "%WORKDIR%" (
    echo [check_release] ERROR: cannot create workdir.
    goto :fail
)

rem // ---- 1. download ------------------------------------------------
echo [check_release] 1/5 downloading release assets...
gh release download "%TAG%" --repo "%GH_REPO%" --dir "%WORKDIR%" --clobber
if errorlevel 1 (
    echo [check_release] ERROR: download failed.
    goto :fail
)

if not exist "%WORKDIR%\SHA256SUMS" (
    echo [check_release] ERROR: SHA256SUMS missing from the release assets.
    goto :fail
)
set "ZIPNAME=Ventoy-%TAG%.zip"
if not exist "%WORKDIR%\%ZIPNAME%" (
    echo [check_release] ERROR: %ZIPNAME% missing from the release assets.
    goto :fail
)

rem // ---- 2. checksums (all entries of SHA256SUMS) -------------------
echo [check_release] 2/5 verifying SHA256 checksums...
python -c "import hashlib,sys; sd,base=open(sys.argv[1]),sys.argv[2]; rows=[l.split(None,1) for l in sd if l.strip()]; bad=[n.strip().lstrip('*') for h,n in rows if hashlib.sha256(open(base+'\\\\'+n.strip().lstrip('*'),'rb').read()).hexdigest()!=h.lower()]; print('\n'.join('MISMATCH: '+n for n in bad) if bad else 'all %%d checksum(s) OK' %% len(rows)); sys.exit(1 if bad or not rows else 0)" "%WORKDIR%\SHA256SUMS" "%WORKDIR%"
if errorlevel 1 (
    echo [check_release] FAIL: checksum verification failed.
    goto :fail
)

rem // ---- 3. extract -------------------------------------------------
echo [check_release] 3/5 extracting %ZIPNAME%...
python -c "import zipfile,sys; zipfile.ZipFile(sys.argv[1]).extractall(sys.argv[2])" "%WORKDIR%\%ZIPNAME%" "%WORKDIR%"
if errorlevel 1 (
    echo [check_release] ERROR: extraction failed.
    goto :fail
)
set "SRCDIR=%WORKDIR%\Ventoy-%TAG%"
if not exist "%SRCDIR%\build_sort_test.py" (
    echo [check_release] ERROR: harness not found in the extraction.
    goto :fail
)

rem // ---- 4. perf sweep (optional, several minutes) -------------------
rem // --sweep needs the perf build path, so this step rebuilds via
rem // build_sort_test.py --perf (its own mechanism, same output exe)
set "SWEEP_RC=0"
if defined SKIP_SWEEP goto :skip_sweep
echo [check_release] 4/5 building the perf variant and running --sweep 30...
pushd "%SRCDIR%"
python build_sort_test.py --perf --sweep 30 1>sweep30_e2e_stdout.txt 2> sweep30_e2e_stderr.txt
set "SWEEP_RC=%ERRORLEVEL%"
popd
if "%SWEEP_RC%"=="0" goto :sweep_ok
echo [check_release] FAIL: perf sweep exited with RC=%SWEEP_RC%.
type "%SRCDIR%\sweep30_e2e_stdout.txt"
goto :fail
:skip_sweep
echo [check_release] 4/5 perf sweep skipped (SKIP_SWEEP=1).
goto :after_sweep
:sweep_ok
echo [check_release] sweep PASS ^(summaries: sweep30_e2e_stdout.txt, raw: sweep30_e2e_stderr.txt^).
if not defined SWEEP_OUT goto :after_sweep
if not exist "%SWEEP_OUT%" mkdir "%SWEEP_OUT%"
copy /y "%SRCDIR%\sweep30_e2e_stdout.txt" "%SWEEP_OUT%\" >nul
copy /y "%SRCDIR%\sweep30_e2e_stderr.txt" "%SWEEP_OUT%\" >nul
echo [check_release] sweep reference log archived to %SWEEP_OUT%.
:after_sweep

rem // ---- 5. harness -------------------------------------------------
echo [check_release] 5/5 running the harness from the extraction...
pushd "%SRCDIR%"
python build_sort_test.py
set "HRC=%ERRORLEVEL%"
popd

if not "%HRC%"=="0" (
    echo [check_release] FAIL: harness exited with RC=%HRC%.
    goto :fail
)

echo.
echo [check_release] PASS: download OK, checksums OK, harness RC=0.
goto :cleanup

:fail
set "FINALRC=1"
goto :cleanup

:cleanup
echo [check_release] cleaning up %WORKDIR%...
if defined WORKDIR if exist "%WORKDIR%" rd /s /q "%WORKDIR%"
if "%FINALRC%"=="1" (
    endlocal & exit /b 1
)
endlocal & exit /b 0
