@echo off
setlocal EnableExtensions

rem // ============================================================
rem // make_release.cmd - build and publish a ventoy-fork release
rem // in one command. Symmetric with dist/check_release.cmd:
rem //
rem //   0. sanity: clean tree, synced with origin, gh/python
rem //      available, target tag does not exist yet
rem //   1. create the annotated tag on HEAD and push it
rem //   2. export the archives from the tag (zip + tar.gz)
rem //   3. write SHA256SUMS over the archives
rem //   4. create/upload the GitHub release and set its notes
rem //      to RELEASE_NOTES.md (edited with the new tag name)
rem //
rem // Usage (from the repo root or the workspace root):
rem //   dist\make_release.cmd v1.1.18-ventoy-sort
rem //   set DRY_RUN=1
rem //   dist\make_release.cmd v1.1.18-ventoy-sort   (no side effects)
rem //
rem // Optional env: DIST_DIR (default: sibling "dist" of the repo,
rem // i.e. ..\dist), RELEASE_TITLE (default "Ventoy <tag> (ventoy-fork)").
rem // Requires: git, gh, python 3. Exits 0 on success.
rem // ============================================================

if "%~1"=="" (
    echo Usage: %~nx0 ^<tag^>   e.g. v1.1.18-ventoy-sort
    echo Env:   DRY_RUN=1, GH_REPO=owner/name, DIST_DIR=^<dir^>, RELEASE_TITLE="..."
    exit /b 1
)
set "TAG=%~1"
if not defined GH_REPO set "GH_REPO=Endymi0n74/ventoy-fork"
if not defined RELEASE_TITLE set "RELEASE_TITLE=Ventoy %TAG% (ventoy-fork)"

where git >nul 2>nul   || (echo [make_release] ERROR: git not found.   & exit /b 1)
where gh  >nul 2>nul   || (echo [make_release] ERROR: gh not found.    & exit /b 1)
where python >nul 2>nul || (echo [make_release] ERROR: python not found. & exit /b 1)

rem // ---- repo root = one level up from this script (dist/ is in repo) -
for %%I in ("%~dp0.") do set "REPO=%%~fI"
set "REPO=%REPO%\.."
for %%I in ("%REPO%") do set "REPO=%%~fI"
if not exist "%REPO%\.git" (
    echo [make_release] ERROR: repo root not found above %~dp0
    exit /b 1
)
if not defined DIST_DIR set "DIST_DIR=%REPO%\..\dist"

echo [make_release] tag=%TAG%
echo [make_release] repo=%REPO%
echo [make_release] dist=%DIST_DIR%
if defined DRY_RUN echo [make_release] DRY_RUN=1 - no side effects
echo.

rem // ---- 0. sanity ----------------------------------------------------
echo [make_release] 0/4 sanity checks...
pushd "%REPO%"
git diff --quiet || (echo [make_release] ERROR: working tree has unstaged changes. & goto :fail_pushd)
git diff --cached --quiet || (echo [make_release] ERROR: working tree has staged changes. & goto :fail_pushd)
git fetch origin --quiet 2>nul
for /f %%A in ('git rev-parse HEAD')  do set "LOCAL_HEAD=%%A"
for /f %%A in ('git rev-parse origin/master') do set "ORIGIN_HEAD=%%A"
if not "%LOCAL_HEAD%"=="%ORIGIN_HEAD%" (
    echo [make_release] ERROR: HEAD is not origin/master ^(push first^).
    goto :fail_pushd
)
git rev-parse -q --verify "refs/tags/%TAG%" >nul 2>nul && (
    echo [make_release] ERROR: tag %TAG% already exists ^(use a new name^).
    goto :fail_pushd
)
if not exist "%REPO%\RELEASE_NOTES.md" (
    echo [make_release] ERROR: RELEASE_NOTES.md not found at repo root.
    goto :fail_pushd
)
echo [make_release] sanity OK ^(HEAD=%LOCAL_HEAD:~0,8%, clean, synced, tag free^).
popd

if defined DRY_RUN (
    echo.
    echo [make_release] DRY-RUN summary of what would run:
    echo   git tag -a %TAG% -m "Release ventoy-fork %TAG%" ^&^& git push origin %TAG%
    echo   git archive --format=zip    --prefix=Ventoy-%TAG%/ -o %DIST_DIR%\Ventoy-%TAG%.zip %TAG%
    echo   git archive --format=tar.gz --prefix=Ventoy-%TAG%/ -o %DIST_DIR%\Ventoy-%TAG%.tar.gz %TAG%
    echo   sha256sum over the 2 archives -^> %DIST_DIR%\SHA256SUMS
    echo   gh release create %TAG% --title "%RELEASE_TITLE%" --notes-file ^& upload --clobber
    echo [make_release] DRY-RUN OK - nothing was done.
    exit /b 0
)

rem // ---- 1. tag --------------------------------------------------------
echo [make_release] 1/4 creating annotated tag %TAG% on HEAD...
git -C "%REPO%" tag -a "%TAG%" -m "Release ventoy-fork %TAG%"
if errorlevel 1 goto :fail_nolocal
git -C "%REPO%" push origin "%TAG%"
if errorlevel 1 (
    echo [make_release] push failed - removing the local tag.
    git -C "%REPO%" tag -d "%TAG%" >nul
    goto :fail_nolocal
)

rem // ---- 2. archives ----------------------------------------------------
echo [make_release] 2/4 exporting archives from the tag...
if not exist "%DIST_DIR%" mkdir "%DIST_DIR%"
git -C "%REPO%" archive --format=zip    --prefix=Ventoy-%TAG%/ -o "%DIST_DIR%\Ventoy-%TAG%.zip"    "%TAG%"
if errorlevel 1 goto :fail_tagged
git -C "%REPO%" archive --format=tar.gz --prefix=Ventoy-%TAG%/ -o "%DIST_DIR%\Ventoy-%TAG%.tar.gz" "%TAG%"
if errorlevel 1 goto :fail_tagged

rem // ---- 3. checksums ---------------------------------------------------
echo [make_release] 3/4 writing SHA256SUMS...
pushd "%DIST_DIR%"
python -c "import hashlib;names=['Ventoy-%TAG%.zip','Ventoy-%TAG%.tar.gz'];rows=[hashlib.sha256(open(n,'rb').read()).hexdigest()+'  '+n for n in names];open('SHA256SUMS','w',newline='\n').write('\n'.join(rows)+'\n');print('\n'.join(rows))"
set "SHA_RC=%ERRORLEVEL%"
popd
if not "%SHA_RC%"=="0" goto :fail_tagged

rem // ---- 4. release ------------------------------------------------------
echo [make_release] 4/4 creating the GitHub release...
rem // RELEASE_NOTES.md is written generically (it covers its own tag),
rem // so it is used verbatim as the body.
gh release create "%TAG%" --repo "%GH_REPO%" --title "%RELEASE_TITLE%" --notes-file "%REPO%\RELEASE_NOTES.md"
if errorlevel 1 goto :fail_tagged
gh release upload "%TAG%" --repo "%GH_REPO%" --clobber "%DIST_DIR%\Ventoy-%TAG%.zip" "%DIST_DIR%\Ventoy-%TAG%.tar.gz" "%DIST_DIR%\SHA256SUMS"
if errorlevel 1 goto :fail_tagged

echo.
echo [make_release] PASS: %TAG% tagged, archives + SHA256SUMS built, release published.
echo [make_release] Next: run dist\check_release.cmd ^(set TAG=%TAG%^) to e2e-validate it.
endlocal & exit /b 0

:fail_pushd
popd
:fail_nolocal
endlocal & exit /b 1

:fail_tagged
echo [make_release] FAILED after tagging/archives - the tag %TAG% exists
echo [make_release] locally and possibly on origin; archives may be partial.
echo [make_release] Fix the cause, then re-run the failed step manually or
echo [make_release] delete the tag: git tag -d %TAG% ^&^& git push origin :refs/tags/%TAG%
endlocal & exit /b 1
