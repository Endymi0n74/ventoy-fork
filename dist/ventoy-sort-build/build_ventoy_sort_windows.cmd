@echo off
rem ============================================================================
rem  Lanceur Windows du build reproductible du paquet ventoy-sort.
rem  Le superviseur PowerShell maintient un client WSL actif pendant le build
rem  et le relance si la VM s'arrête sans code de sortie normal. Arguments :
rem      build_ventoy_sort_windows.cmd
rem      build_ventoy_sort_windows.cmd KEEP=1
rem      set WSL_BUILD_RETRIES=3 (optionnel, defaut : 2 relances)
rem      set WSL_DISTRO=Ubuntu-24.04 (optionnel, defaut : Ubuntu)
rem ============================================================================
setlocal EnableExtensions

powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%~dp0run_wsl_build.ps1" -Kind windows %*
exit /b %ERRORLEVEL%
