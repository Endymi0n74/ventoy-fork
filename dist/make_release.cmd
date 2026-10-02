@echo off
setlocal EnableExtensions

rem // ============================================================
rem // make_release.cmd - build and publish a ventoy-fork release
rem // in one command. Symmetric with dist/check_release.cmd:
rem //
rem //   0. sanity: clean tree, synced with origin, validate tag/release state, required tools
rem //   1. create and push a new tag (or move an existing tag with MOVE_TAG=1)
rem //   2. export the archives from the tag (zip + tar.gz)
rem //   3. write SHA256SUMS over the archives
rem //   4. create a new draft release or update the existing release/assets,
rem //      then restore its original draft/published state and set RELEASE_NOTES.md
rem //      PRERELEASE=1 creates a prerelease (for RC/testing tags)
rem //
rem // Usage (from the repo root or the workspace root):
rem //   dist\make_release.cmd v1.1.18-ventoy-sort
rem //   set DRY_RUN=1
rem //   dist\make_release.cmd v1.1.19-ventoy-sort-rc1   (no side effects)
rem //   set PRERELEASE=1
rem //   dist\make_release.cmd v1.1.19-ventoy-sort-rc1
rem //   set DRY_RUN=1
rem //   dist\make_release.cmd v1.1.18-ventoy-sort
rem //   set DRY_RUN=
rem //   set MOVE_TAG=1
rem //   set CONFIRM_MOVE_TAG=v1.1.18-ventoy-sort
rem //   dist\make_release.cmd v1.1.18-ventoy-sort
rem //
rem // Optional env: DIST_DIR (default: sibling "dist" of the repo,
rem // i.e. ..\dist), RELEASE_TITLE (default "Ventoy <tag> (ventoy-fork)"),
rem // PRERELEASE=1 for a prerelease. MOVE_TAG=1 updates an EXISTING tag/release;
rem // it requires CONFIRM_MOVE_TAG=<exact tag>; preview with DRY_RUN=1, then unset it.
rem // MOVE_TAG refuses immutable releases; matching assets use --clobber (GitHub
rem // deletes the old asset before upload), so the three assets are backed up
rem // to DIST_DIR\.asset-backup first and restored automatically if an upload
rem // fails midway; a failed backup aborts before anything is modified.
rem // Requires gh auth with repo write access.
rem // Requires: git, gh, python 3. Exits 0 on success.
rem // ============================================================

if "%~1"=="" (
    echo Usage: %~nx0 ^<tag^>   e.g. v1.1.19-ventoy-sort-rc1
    echo Env:   DRY_RUN=1, PRERELEASE=1, MOVE_TAG=1, CONFIRM_MOVE_TAG=^<exact tag^>, GH_REPO=owner/name, DIST_DIR=^<dir^>
    exit /b 1
)
set "TAG=%~1"
set "TAG_MOVED=0"
set "PUBLISHED_HIDDEN=0"
set "ASSET_BACKUP_COUNT=0"
set "ASSETS_RESTORED="
if not defined GH_REPO set "GH_REPO=Endymi0n74/ventoy-fork"
if not defined RELEASE_TITLE set "RELEASE_TITLE=Ventoy %TAG% (ventoy-fork)"
if not defined MOVE_TAG set "MOVE_TAG=0"
if /i not "%MOVE_TAG%"=="0" if /i not "%MOVE_TAG%"=="1" (
    echo [make_release] ERROR: MOVE_TAG must be 0 or 1.
    exit /b 1
)
if "%MOVE_TAG%"=="1" if not defined DRY_RUN if not "%CONFIRM_MOVE_TAG%"=="%TAG%" (
    echo [make_release] ERROR: moving an existing release tag is destructive.
    echo [make_release] Set CONFIRM_MOVE_TAG to the exact tag name: %TAG%
    exit /b 1
)
if "%MOVE_TAG%"=="1" if defined DRY_RUN if defined CONFIRM_MOVE_TAG if not "%CONFIRM_MOVE_TAG%"=="%TAG%" (
    echo [make_release] ERROR: CONFIRM_MOVE_TAG must match %TAG% exactly.
    exit /b 1
)
if defined DRY_RUN if not "%DRY_RUN%"=="1" (
    echo [make_release] ERROR: DRY_RUN must be unset or exactly 1.
    exit /b 1
)
set "PRE_FLAG="
if /i "%PRERELEASE%"=="1" set "PRE_FLAG=--prerelease"

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
set "ASSET_BACKUP_DIR=%DIST_DIR%\.asset-backup"

echo [make_release] tag=%TAG%
echo [make_release] repo=%REPO%
echo [make_release] dist=%DIST_DIR%
if "%MOVE_TAG%"=="1" echo [make_release] MOVE_TAG=1 - update existing tag/release
if defined DRY_RUN echo [make_release] DRY_RUN=1 - no side effects
echo.

rem // ---- 0. sanity ----------------------------------------------------
echo [make_release] 0/4 sanity checks...
pushd "%REPO%"
set "DIRTY="
set "STATUS_RC=0"
for /f "delims=" %%A in ('git status --porcelain') do set "DIRTY=1"
if errorlevel 1 set "STATUS_RC=1"
if "%STATUS_RC%"=="1" (
    echo [make_release] ERROR: could not inspect the working tree state.
    goto :fail_pushd
)
if not defined DIRTY goto :clean_tree
echo [make_release] ERROR: working tree is not clean ^(tracked or untracked changes^).
goto :fail_pushd
:clean_tree
git fetch origin --quiet 2>nul
if errorlevel 1 (
    echo [make_release] ERROR: could not fetch origin; refusing to publish or move a tag.
    goto :fail_pushd
)
set "LOCAL_HEAD="
set "ORIGIN_HEAD="
for /f %%A in ('git rev-parse HEAD')  do set "LOCAL_HEAD=%%A"
for /f %%A in ('git rev-parse origin/master') do set "ORIGIN_HEAD=%%A"
if not defined LOCAL_HEAD goto :head_lookup_failed
if not defined ORIGIN_HEAD goto :head_lookup_failed
if not "%LOCAL_HEAD%"=="%ORIGIN_HEAD%" (
    echo [make_release] ERROR: HEAD is not origin/master ^(push first^).
    goto :fail_pushd
)
if "%MOVE_TAG%"=="1" goto :move_tag_checks
git rev-parse -q --verify "refs/tags/%TAG%" >nul 2>nul
if not errorlevel 1 goto :tag_exists
goto :tag_available
:head_lookup_failed
echo [make_release] ERROR: could not resolve HEAD or origin/master.
goto :fail_pushd
:tag_exists
echo [make_release] ERROR: tag %TAG% already exists ^(use MOVE_TAG=1 to update its existing release^).
goto :fail_pushd
:tag_available
goto :notes_check

:move_tag_checks
rem // Refuse to move a tag unless the local and remote annotated/lightweight
rem // tag objects agree, and a GitHub release is already attached to this tag.
git rev-parse -q --verify "refs/tags/%TAG%" >nul 2>nul
if errorlevel 1 goto :move_tag_missing
for /f %%A in ('git rev-parse "refs/tags/%TAG%"') do set "LOCAL_TAG_SHA=%%A"
set "REMOTE_TAG_SHA="
git ls-remote --exit-code --tags origin "refs/tags/%TAG%" >nul 2>nul
if errorlevel 1 goto :move_tag_missing_remote
for /f "tokens=1,2" %%A in ('git ls-remote --tags origin "refs/tags/%TAG%"') do if "%%B"=="refs/tags/%TAG%" set "REMOTE_TAG_SHA=%%A"
if not defined REMOTE_TAG_SHA goto :move_tag_lookup_failed
if not "%LOCAL_TAG_SHA%"=="%REMOTE_TAG_SHA%" goto :move_tag_mismatch
set "EXISTING_RELEASE_TAG="
set "EXISTING_RELEASE_ID="
set "EXISTING_RELEASE_PRERELEASE="
set "EXISTING_RELEASE_DRAFT="
set "EXISTING_RELEASE_IMMUTABLE="
rem // Find the release ID via API: get-by-tag omits drafts, so paginate releases.
gh api --paginate "repos/%GH_REPO%/releases?per_page=100" --jq "length" >nul 2>nul
if errorlevel 1 goto :move_release_lookup_failed
set "RELEASE_LOOKUP_OUTPUT="
for /f "tokens=1,2" %%A in ('gh api --paginate "repos/%GH_REPO%/releases?per_page=100" --jq ".[] | [.id, .tag_name] | @tsv" 2^>nul') do (
    set "RELEASE_LOOKUP_OUTPUT=1"
    if "%%B"=="%TAG%" set "EXISTING_RELEASE_ID=%%A"
)
if not defined RELEASE_LOOKUP_OUTPUT goto :move_release_lookup_failed
if not defined EXISTING_RELEASE_ID goto :move_release_missing
set "RELEASE_DETAIL_OUTPUT="
for /f "tokens=1-4" %%A in ('gh api "repos/%GH_REPO%/releases/%EXISTING_RELEASE_ID%" --jq "[.tag_name, (.draft|tostring), (.prerelease|tostring), (.immutable|tostring)] | @tsv" 2^>nul') do (
    set "RELEASE_DETAIL_OUTPUT=1"
    set "EXISTING_RELEASE_TAG=%%A"
    set "EXISTING_RELEASE_DRAFT=%%B"
    set "EXISTING_RELEASE_PRERELEASE=%%C"
    set "EXISTING_RELEASE_IMMUTABLE=%%D"
)
if not defined RELEASE_DETAIL_OUTPUT goto :move_release_lookup_failed
if not defined EXISTING_RELEASE_TAG goto :move_release_lookup_failed
if not "%EXISTING_RELEASE_TAG%"=="%TAG%" goto :move_release_missing
if /i not "%EXISTING_RELEASE_PRERELEASE%"=="true" if /i not "%EXISTING_RELEASE_PRERELEASE%"=="false" goto :move_release_state_unknown
if /i not "%EXISTING_RELEASE_DRAFT%"=="true" if /i not "%EXISTING_RELEASE_DRAFT%"=="false" goto :move_release_state_unknown
if /i "%EXISTING_RELEASE_DRAFT%"=="false" (
    if not defined EXISTING_RELEASE_IMMUTABLE goto :move_immutable_unknown
    if /i "%EXISTING_RELEASE_IMMUTABLE%"=="true" goto :move_immutable
    if /i not "%EXISTING_RELEASE_IMMUTABLE%"=="false" goto :move_immutable_unknown
)
rem // Preserve the existing release channel and draft/published state; MOVE_TAG
rem // is only a content/tag update, not an implicit stable/prerelease conversion.
set "PRE_FLAG="
if /i "%EXISTING_RELEASE_PRERELEASE%"=="true" set "PRE_FLAG=--prerelease"
echo [make_release] existing release found; prerelease=%EXISTING_RELEASE_PRERELEASE%, draft=%EXISTING_RELEASE_DRAFT%, immutable=%EXISTING_RELEASE_IMMUTABLE%; tag object %LOCAL_TAG_SHA:~0,8% will move to %LOCAL_HEAD:~0,8%.
goto :notes_check
:move_tag_missing
echo [make_release] ERROR: local tag %TAG% does not exist.
goto :fail_pushd
:move_tag_missing_remote
echo [make_release] ERROR: remote tag %TAG% does not exist on origin.
goto :fail_pushd
:move_tag_lookup_failed
echo [make_release] ERROR: could not read remote tag %TAG%; check origin connectivity and permissions.
goto :fail_pushd
:move_tag_mismatch
echo [make_release] ERROR: local tag %TAG% differs from origin; fetch/reconcile it before moving.
goto :fail_pushd
:move_release_missing
echo [make_release] ERROR: no GitHub release exists for tag %TAG% in %GH_REPO%.
goto :fail_pushd
:move_release_lookup_failed
echo [make_release] ERROR: no accessible GitHub release was found for %TAG%; verify gh authentication and repository access.
goto :fail_pushd
:move_release_state_unknown
echo [make_release] ERROR: could not read the existing release draft/prerelease state; refusing to update it.
goto :fail_pushd
:move_immutable
echo [make_release] ERROR: GitHub marks this release immutable; it cannot be retagged or have assets replaced.
goto :fail_pushd
:move_immutable_unknown
echo [make_release] ERROR: could not confirm that the existing GitHub release is mutable; refusing to move it.
goto :fail_pushd

:notes_check
if exist "%REPO%\RELEASE_NOTES.md" goto :notes_exist
echo [make_release] ERROR: RELEASE_NOTES.md not found at repo root.
goto :fail_pushd
:notes_exist
echo [make_release] sanity OK ^(HEAD=%LOCAL_HEAD:~0,8%, clean, synced^).
if "%MOVE_TAG%"=="1" echo [make_release] release state: prerelease=%EXISTING_RELEASE_PRERELEASE%, draft=%EXISTING_RELEASE_DRAFT%, immutable=%EXISTING_RELEASE_IMMUTABLE%.
popd
goto :sanity_done
:sanity_done

if defined DRY_RUN goto :dry_run

goto :release_execute

:dry_run
echo.
echo [make_release] DRY-RUN summary of what would run:
if "%MOVE_TAG%"=="1" (
    echo   gh api repos/%GH_REPO%/releases/%EXISTING_RELEASE_ID%/assets  ^(backup 3 assets to %ASSET_BACKUP_DIR%^)
    if /i "%EXISTING_RELEASE_DRAFT%"=="true" (
        echo   release is already a draft; keep it unpublished throughout the update
    ) else (
        echo   gh release edit %TAG% --repo %GH_REPO% --draft=true %PRE_FLAG% ^(hide release during replacement^)
    )
    echo   git tag -fa %TAG% -m "Release ventoy-fork %TAG%"
    echo   git push --force-with-lease=refs/tags/%TAG%:%REMOTE_TAG_SHA% origin refs/tags/%TAG%
) else (
    echo   git tag -a %TAG% -m "Release ventoy-fork %TAG%" ^&^& git push origin %TAG%
)
echo   git archive --format=zip    --prefix=Ventoy-%TAG%/ -o %DIST_DIR%\Ventoy-%TAG%.zip %TAG%
echo   git archive --format=tar.gz --prefix=Ventoy-%TAG%/ -o %DIST_DIR%\Ventoy-%TAG%.tar.gz %TAG%
echo   regenerate %DIST_DIR%\SHA256SUMS from both source archives
if "%MOVE_TAG%"=="1" (
    echo   gh release upload %TAG% --repo %GH_REPO% --clobber ^<2 source archives^> SHA256SUMS
    if /i "%EXISTING_RELEASE_DRAFT%"=="true" (
        echo   gh release edit %TAG% --repo %GH_REPO% %PRE_FLAG% --notes-file RELEASE_NOTES.md ^(keep draft^)
    ) else (
        echo   gh release edit %TAG% --repo %GH_REPO% --draft=false %PRE_FLAG% --notes-file RELEASE_NOTES.md
    )
) else (
    echo   gh release create %TAG% --repo %GH_REPO% --draft --title "%RELEASE_TITLE%" %PRE_FLAG% --notes-file RELEASE_NOTES.md
    echo   gh release upload %TAG% --repo %GH_REPO% --clobber ^<2 source archives^> SHA256SUMS
    echo   gh release edit %TAG% --repo %GH_REPO% --draft=false %PRE_FLAG% --notes-file RELEASE_NOTES.md
)
echo [make_release] DRY-RUN OK - nothing was done.
exit /b 0

:download_asset
rem // %~1 = asset id, %~2 = file name. Binary body straight to stdout; this
rem // path also works for draft releases (no get-by-tag involved).
gh api "repos/%GH_REPO%/releases/assets/%~1" -H "Accept: application/octet-stream" >"%ASSET_BACKUP_DIR%\%~2"
exit /b %ERRORLEVEL%

:release_execute
if "%MOVE_TAG%"=="1" goto :move_existing_tag

rem // ---- 1. create a new tag -------------------------------------------
echo [make_release] 1/4 creating annotated tag %TAG% on HEAD...
git -C "%REPO%" tag -a "%TAG%" -m "Release ventoy-fork %TAG%"
if errorlevel 1 goto :fail_nolocal
git -C "%REPO%" push origin "%TAG%"
if errorlevel 1 (
    echo [make_release] push failed - removing the local tag.
    git -C "%REPO%" tag -d "%TAG%" >nul
    goto :fail_nolocal
)
goto :tag_ready

:move_existing_tag
rem // Back up the three assets BEFORE any mutation: --clobber deletes each
rem // old asset right before uploading its replacement, so a rollback needs
rem // yesterday's files. Download by asset ID (gh release download would
rem // resolve the release via get-by-tag, which 404s on drafts). A failure
rem // here stops with the release and the tag exactly as they were.
echo [make_release] backing up the existing release assets to %ASSET_BACKUP_DIR%...
if exist "%ASSET_BACKUP_DIR%" rmdir /s /q "%ASSET_BACKUP_DIR%"
mkdir "%ASSET_BACKUP_DIR%" 2>nul
if errorlevel 1 goto :fail_backup
gh api "repos/%GH_REPO%/releases/%EXISTING_RELEASE_ID%/assets" --jq "length" >nul 2>nul
if errorlevel 1 goto :fail_backup
set "ASSET_LIST_OUTPUT="
set "ASSET_ID_ZIP="
set "ASSET_ID_TAR="
set "ASSET_ID_SUM="
for /f "tokens=1,2" %%A in ('gh api "repos/%GH_REPO%/releases/%EXISTING_RELEASE_ID%/assets" --jq ".[] | [.id, .name] | @tsv" 2^>nul') do (
    set "ASSET_LIST_OUTPUT=1"
    if /i "%%B"=="Ventoy-%TAG%.zip" set "ASSET_ID_ZIP=%%A"
    if /i "%%B"=="Ventoy-%TAG%.tar.gz" set "ASSET_ID_TAR=%%A"
    if /i "%%B"=="SHA256SUMS" set "ASSET_ID_SUM=%%A"
)
if not defined ASSET_LIST_OUTPUT goto :fail_backup
if defined ASSET_ID_ZIP (
    call :download_asset "%ASSET_ID_ZIP%" "Ventoy-%TAG%.zip"
    if errorlevel 1 goto :fail_backup
)
if defined ASSET_ID_TAR (
    call :download_asset "%ASSET_ID_TAR%" "Ventoy-%TAG%.tar.gz"
    if errorlevel 1 goto :fail_backup
)
if defined ASSET_ID_SUM (
    call :download_asset "%ASSET_ID_SUM%" "SHA256SUMS"
    if errorlevel 1 goto :fail_backup
)
set "ASSET_BACKUP_COUNT=0"
if defined ASSET_ID_ZIP set /a ASSET_BACKUP_COUNT+=1
if defined ASSET_ID_TAR set /a ASSET_BACKUP_COUNT+=1
if defined ASSET_ID_SUM set /a ASSET_BACKUP_COUNT+=1
rem // Draft first: this suppresses the release-published workflow until the
rem // new tag, git archives, checksums and assets are all ready.
if /i "%EXISTING_RELEASE_DRAFT%"=="true" goto :move_tag_now
echo [make_release] 1/4 putting the existing release in draft mode...
set "PUBLISHED_HIDDEN=1"
gh release edit "%TAG%" --repo "%GH_REPO%" --draft=true %PRE_FLAG%
if errorlevel 1 goto :restore_published_release

:move_tag_now
echo [make_release] 2/4 moving the existing annotated tag to HEAD...
git -C "%REPO%" tag -fa "%TAG%" -m "Release ventoy-fork %TAG%"
if errorlevel 1 goto :restore_published_release
set "NEW_TAG_SHA="
set "NEW_TAG_RC=0"
for /f %%A in ('git -C "%REPO%" rev-parse "refs/tags/%TAG%"') do set "NEW_TAG_SHA=%%A"
if errorlevel 1 set "NEW_TAG_RC=1"
if "%NEW_TAG_RC%"=="1" goto :restore_published_release
if not defined NEW_TAG_SHA goto :restore_published_release
git -C "%REPO%" push --force-with-lease="refs/tags/%TAG%:%REMOTE_TAG_SHA%" origin "refs/tags/%TAG%"
if errorlevel 1 goto :move_push_failed
set "TAG_MOVED=1"
goto :verify_moved_tag

:move_push_failed
rem // A network error can be reported after the server accepted the update;
rem // inspect origin before deciding whether to roll back or leave the release draft.
set "CURRENT_REMOTE_TAG_SHA="
for /f "tokens=1,2" %%A in ('git -C "%REPO%" ls-remote --tags origin "refs/tags/%TAG%"') do if "%%B"=="refs/tags/%TAG%" set "CURRENT_REMOTE_TAG_SHA=%%A"
if defined CURRENT_REMOTE_TAG_SHA if "%CURRENT_REMOTE_TAG_SHA%"=="%NEW_TAG_SHA%" (
    set "TAG_MOVED=1"
    goto :verify_moved_tag
)
if not defined CURRENT_REMOTE_TAG_SHA goto :fail_tag_state_unknown
if not "%CURRENT_REMOTE_TAG_SHA%"=="%REMOTE_TAG_SHA%" goto :fail_tag_state_unknown
git -C "%REPO%" update-ref "refs/tags/%TAG%" "%LOCAL_TAG_SHA%"
if errorlevel 1 goto :fail_tag_state_unknown
if "%PUBLISHED_HIDDEN%"=="1" goto :restore_published_release
echo [make_release] Existing release was already a draft; the remote tag is unchanged.
goto :fail_nolocal

:verify_moved_tag
set "CURRENT_REMOTE_TAG_SHA="
for /f "tokens=1,2" %%A in ('git -C "%REPO%" ls-remote --tags origin "refs/tags/%TAG%"') do if "%%B"=="refs/tags/%TAG%" set "CURRENT_REMOTE_TAG_SHA=%%A"
if defined CURRENT_REMOTE_TAG_SHA if "%NEW_TAG_SHA%"=="%CURRENT_REMOTE_TAG_SHA%" goto :tag_move_verified
if defined CURRENT_REMOTE_TAG_SHA if "%REMOTE_TAG_SHA%"=="%CURRENT_REMOTE_TAG_SHA%" goto :restore_published_release
set "REMOTE_TAG_SHA=%CURRENT_REMOTE_TAG_SHA%"
goto :fail_tag_state_unknown
:tag_move_verified
set "REMOTE_TAG_SHA=%NEW_TAG_SHA%"
set "LOCAL_TAG_SHA=%NEW_TAG_SHA%"
echo [make_release] annotated tag moved and force-pushed. The release remains draft until its assets are replaced.
echo [make_release] WARNING: gh release upload --clobber deletes each matching old asset before uploading its replacement.
echo [make_release] If a later step fails, the release stays draft for repair.
if /i "%EXISTING_RELEASE_DRAFT%"=="false" set "PUBLISHED_HIDDEN=1"

:tag_ready
rem // ---- 2. archives ----------------------------------------------------
echo [make_release] exporting source archives from tag %TAG%...
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
if "%MOVE_TAG%"=="1" goto :update_existing_release
echo [make_release] 4/4 creating the GitHub release...
rem // Create as a draft so the release-published workflow cannot race
rem // the asset upload. RELEASE_NOTES.md is used verbatim as the body.
gh release create "%TAG%" --repo "%GH_REPO%" --draft --title "%RELEASE_TITLE%" %PRE_FLAG% --notes-file "%REPO%\RELEASE_NOTES.md"
if errorlevel 1 goto :fail_tagged
gh release upload "%TAG%" --repo "%GH_REPO%" --clobber "%DIST_DIR%\Ventoy-%TAG%.zip" "%DIST_DIR%\Ventoy-%TAG%.tar.gz" "%DIST_DIR%\SHA256SUMS"
if errorlevel 1 goto :fail_tagged
gh release edit "%TAG%" --repo "%GH_REPO%" --draft=false %PRE_FLAG% --notes-file "%REPO%\RELEASE_NOTES.md"
if errorlevel 1 goto :fail_tagged
goto :release_success

:update_existing_release
echo [make_release] 4/4 replacing assets on the existing GitHub release...
gh release upload "%TAG%" --repo "%GH_REPO%" --clobber "%DIST_DIR%\Ventoy-%TAG%.zip" "%DIST_DIR%\Ventoy-%TAG%.tar.gz" "%DIST_DIR%\SHA256SUMS"
if errorlevel 1 goto :upload_failed
if /i "%EXISTING_RELEASE_DRAFT%"=="true" goto :keep_existing_draft
gh release edit "%TAG%" --repo "%GH_REPO%" --draft=false %PRE_FLAG% --notes-file "%REPO%\RELEASE_NOTES.md"
if errorlevel 1 goto :fail_tagged
goto :existing_release_updated
:keep_existing_draft
gh release edit "%TAG%" --repo "%GH_REPO%" %PRE_FLAG% --notes-file "%REPO%\RELEASE_NOTES.md"
if errorlevel 1 goto :fail_tagged
:existing_release_updated

goto :release_success

:upload_failed
rem // --clobber deleted some assets before failing: put the backed-up
rem // copies back so the release is left whole, not half-updated.
if "%ASSET_BACKUP_COUNT%"=="0" goto :fail_tagged
echo [make_release] upload failed - restoring the previous assets from %ASSET_BACKUP_DIR%...
set "ASSETS_RESTORED=1"
for %%F in ("Ventoy-%TAG%.zip" "Ventoy-%TAG%.tar.gz" "SHA256SUMS") do (
    if exist "%ASSET_BACKUP_DIR%\%%~F" (
        gh release upload "%TAG%" --repo "%GH_REPO%" --clobber "%ASSET_BACKUP_DIR%\%%~F"
        if errorlevel 1 set "ASSETS_RESTORED=0"
    )
)
if "%ASSETS_RESTORED%"=="1" (
    echo [make_release] previous assets restored - the release now differs from its published state only by the moved tag.
) else (
    echo [make_release] WARNING: some previous assets could NOT be restored - reload them manually from %ASSET_BACKUP_DIR%.
)
goto :fail_tagged

:release_success
echo.
if "%MOVE_TAG%"=="1" (
    if /i "%EXISTING_RELEASE_DRAFT%"=="true" (
        echo [make_release] PASS: %TAG% moved to HEAD; existing draft assets and notes updated; release remains draft.
    ) else (
        echo [make_release] PASS: %TAG% moved to HEAD; existing release assets and notes updated and published.
    )
) else (
    echo [make_release] PASS: %TAG% tagged, archives + SHA256SUMS built, release published.
)
echo [make_release] Next: run dist\check_release.cmd ^(set TAG=%TAG%^) to e2e-validate it.
if "%MOVE_TAG%"=="1" if exist "%ASSET_BACKUP_DIR%" rmdir /s /q "%ASSET_BACKUP_DIR%"
endlocal & exit /b 0

:fail_backup
echo [make_release] ERROR: could not back up the existing release assets; the release and the tag are unchanged.
echo [make_release] Check gh authentication, network and repository permissions, then rerun.
if exist "%ASSET_BACKUP_DIR%" rmdir /s /q "%ASSET_BACKUP_DIR%"
set "ASSET_BACKUP_COUNT=0"
goto :fail_nolocal

:fail_pushd
popd
:fail_nolocal
endlocal & exit /b 1

:restore_published_release
echo [make_release] ERROR: tag move failed; restoring the previous local tag and published release.
if defined NEW_TAG_SHA (
    git -C "%REPO%" update-ref "refs/tags/%TAG%" "%LOCAL_TAG_SHA%"
    if errorlevel 1 echo [make_release] WARNING: could not restore the previous local tag object.
)
if /i "%EXISTING_RELEASE_DRAFT%"=="true" goto :leave_draft_after_local_failure
gh release edit "%TAG%" --repo "%GH_REPO%" --draft=false %PRE_FLAG%
if errorlevel 1 echo [make_release] WARNING: could not restore the previously published release; it may remain a draft.
:leave_draft_after_local_failure
endlocal & exit /b 1

:fail_tag_state_unknown
echo [make_release] ERROR: could not confirm whether the remote tag moved; the release is left as a draft for safety.
echo [make_release] Inspect origin and the local tag before retrying; no assets were updated.
echo [make_release] Local tag object: %NEW_TAG_SHA%; observed remote tag object: %REMOTE_TAG_SHA%.
endlocal & exit /b 1

:fail_tagged
echo [make_release] FAILED after tag/archive update.
if "%TAG_MOVED%"=="1" (
    echo [make_release] The remote tag points to the moved object; the existing release remains draft for safety.
    echo [make_release] Fix the cause and rerun with MOVE_TAG=1 and CONFIRM_MOVE_TAG=%TAG% to replace the assets.
    if "%PUBLISHED_HIDDEN%"=="1" echo [make_release] This release was published before the operation; publish the repaired draft manually after verification.
    if "%ASSETS_RESTORED%"=="1" echo [make_release] The previous assets are back in place; rerunning MOVE_TAG will replace them with the rebuilt ones.
) else (
    echo [make_release] Tag %TAG% exists locally and remotely; archives may be partial.
    echo [make_release] Fix the cause, then resume the failed step manually.
)
endlocal & exit /b 1
