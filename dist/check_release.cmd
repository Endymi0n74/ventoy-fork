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
rem //   6. if ventoy-sort package assets are present in the release
rem //      (ventoy-*-ventoy-sort-windows.zip / -linux.tar.gz), or PKG_DIR=
rem //      points at local ones, run the 3 package checks of README.fr.md
rem //      (fingerprint, fork marker, baseline diff) via check_release_pkg.py
rem //      - skipped with a notice when there is no package to check
rem //
rem // Usage (from the repo root or the workspace root):
rem //   dist\check_release.cmd
rem //   set SKIP_SWEEP=1
rem //   set SWEEP_OUT=D:\somewhere   (keep the sweep reference log)
rem //   set GH_REPO=owner/name
rem //   set TAG=v1.2.0
rem //   set PKG_DIR=D:\somewhere  (ventoy-sort packages to check in step 6
rem //                             when they are not release assets)
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
echo [check_release] 1/6 downloading release assets...
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
echo [check_release] 2/6 verifying SHA256 checksums...
python -c "import hashlib,sys; sd,base=open(sys.argv[1]),sys.argv[2]; rows=[l.split(None,1) for l in sd if l.strip()]; bad=[n.strip().lstrip('*') for h,n in rows if hashlib.sha256(open(base+'\\\\'+n.strip().lstrip('*'),'rb').read()).hexdigest()!=h.lower()]; print('\n'.join('MISMATCH: '+n for n in bad) if bad else 'all %%d checksum(s) OK' %% len(rows)); sys.exit(1 if bad or not rows else 0)" "%WORKDIR%\SHA256SUMS" "%WORKDIR%"
if errorlevel 1 (
    echo [check_release] FAIL: checksum verification failed.
    goto :fail
)

rem // ---- 3. extract -------------------------------------------------
echo [check_release] 3/6 extracting %ZIPNAME%...
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
echo [check_release] 4/6 building the perf variant and running --sweep 30...
pushd "%SRCDIR%"
python build_sort_test.py --perf --sweep 30 1>sweep30_e2e_stdout.txt 2> sweep30_e2e_stderr.txt
set "SWEEP_RC=%ERRORLEVEL%"
popd
if "%SWEEP_RC%"=="0" goto :sweep_ok
echo [check_release] FAIL: perf sweep exited with RC=%SWEEP_RC%.
type "%SRCDIR%\sweep30_e2e_stdout.txt"
goto :fail
:skip_sweep
echo [check_release] 4/6 perf sweep skipped (SKIP_SWEEP=1).
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
echo [check_release] 5/6 running the harness from the extraction...
pushd "%SRCDIR%"
python build_sort_test.py
set "HRC=%ERRORLEVEL%"
popd

if not "%HRC%"=="0" (
    echo [check_release] FAIL: harness exited with RC=%HRC%.
    goto :fail
)

rem // ---- 6. ventoy-sort package checks (README.fr.md guide) -----------
rem // Applies the 3 package checks (fingerprint / fork marker / baseline
rem // diff) to the ventoy-sort packages when they are part of the release
rem // assets or provided locally via PKG_DIR=. Otherwise: skipped notice.
set "PKGRC=0"
set "PKGLIST="
set "PKGFOUND=0"
if defined PKG_DIR if exist "%PKG_DIR%\*.zip" set "PKGFOUND=1"
if defined PKG_DIR if exist "%PKG_DIR%\*.tar.gz" set "PKGFOUND=1"
for %%A in ("%WORKDIR%\ventoy-*-ventoy-sort-windows.zip") do if exist "%%~A" set "PKGFOUND=1"
for %%A in ("%WORKDIR%\ventoy-*-ventoy-sort-linux.tar.gz") do if exist "%%~A" set "PKGFOUND=1"
if "%PKGFOUND%"=="0" (
    echo [check_release] 6/6 no ventoy-sort package in the release assets ^(and no PKG_DIR=^) - package checks skipped.
    goto :after_pkg
)
echo [check_release] 6/6 running the 3 package checks (fingerprint / marker / baseline)...
if defined PKG_DIR (
    for %%A in ("%PKG_DIR%\ventoy-*-ventoy-sort-windows.zip") do if exist "%%~A" call :addpkg "%%~A"
    for %%A in ("%PKG_DIR%\ventoy-*-ventoy-sort-linux.tar.gz") do if exist "%%~A" call :addpkg "%%~A"
)
for %%A in ("%WORKDIR%\ventoy-*-ventoy-sort-windows.zip") do if exist "%%~A" call :addpkg "%%~A"
for %%A in ("%WORKDIR%\ventoy-*-ventoy-sort-linux.tar.gz") do if exist "%%~A" call :addpkg "%%~A"
python "%~dp0check_release_pkg.py" %PKGLIST%
set "PKGRC=%ERRORLEVEL%"
if not "%PKGRC%"=="0" (
    echo [check_release] FAIL: package checks exited with RC=%PKGRC%.
    goto :fail
)
:after_pkg

echo.
echo [check_release] PASS: download OK, checksums OK, harness RC=0, package checks OK.
goto :cleanup

:addpkg
set "PKGLIST=%PKGLIST% %~1"
goto :eof

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
