@echo off
rem ============================================================================
rem  Lanceur Windows du build reproductible du paquet ventoy-sort.
rem  Tout le travail se fait dans WSL (Ubuntu) ; ce fichier ne fait que convertir
rem  le chemin et transmettre les arguments NAME=value, par exemple :
rem      build_ventoy_sort_windows.cmd
rem      build_ventoy_sort_windows.cmd KEEP=1
rem      build_ventoy_sort_windows.cmd BASE_ZIP=/mnt/d/Codex/dist/_dl/ventoy-1.1.17-windows.zip
rem ============================================================================
setlocal EnableExtensions

set "SCRIPT_WIN=%~dp0build_ventoy_sort_windows.sh"
set "SCRIPT="
for /f "usebackq delims=" %%i in (`wsl -d Ubuntu -- wslpath -u "%SCRIPT_WIN%" 2^>nul`) do set "SCRIPT=%%i"

if not defined SCRIPT (
    echo [erreur] WSL/Ubuntu introuvable, ou conversion du chemin impossible :
    echo          %SCRIPT_WIN%
    echo          Verifier avec :  wsl -d Ubuntu -- uname -a
    exit /b 1
)

wsl -d Ubuntu -- bash "%SCRIPT%" %*
exit /b %ERRORLEVEL%
