[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [ValidateSet('windows', 'linux')]
    [string]$Kind,

    [Parameter(ValueFromRemainingArguments = $true)]
    [string[]]$BuildArgs = @()
)

$ErrorActionPreference = 'Stop'
$WslExe = 'wsl.exe'
if ($env:VENTOY_WSL_EXE) { $WslExe = $env:VENTOY_WSL_EXE }
$script:FinalExitCode = 1
$Distro = 'Ubuntu'
if ($env:WSL_DISTRO) { $Distro = $env:WSL_DISTRO }
$Retries = 2
if ($env:WSL_BUILD_RETRIES) { $Retries = [int]$env:WSL_BUILD_RETRIES }
$RetryDelaySeconds = 15
if ($env:WSL_RETRY_DELAY_SECONDS) { $RetryDelaySeconds = [int]$env:WSL_RETRY_DELAY_SECONDS }
if ($Retries -lt 0 -or $RetryDelaySeconds -lt 0) {
    Write-Host '[error] WSL_BUILD_RETRIES and WSL_RETRY_DELAY_SECONDS must be >= 0.' -ForegroundColor Red
    $script:FinalExitCode = 2
    exit $script:FinalExitCode
}

$buildScriptWin = Join-Path $PSScriptRoot "build_ventoy_sort_${Kind}.sh"
$attemptScriptWin = Join-Path $PSScriptRoot 'wsl_build_attempt.sh'
if (-not (Test-Path -LiteralPath $buildScriptWin) -or -not (Test-Path -LiteralPath $attemptScriptWin)) {
    Write-Host "[error] Build script or WSL supervisor missing under $PSScriptRoot" -ForegroundColor Red
    $script:FinalExitCode = 2
    exit $script:FinalExitCode
}

function Invoke-Wsl([string[]]$Arguments) {
    if ([System.IO.Path]::GetExtension($WslExe) -ieq '.ps1') {
        & powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File $WslExe @Arguments
    }
    else {
        & $WslExe @Arguments
    }
}

function Convert-ToWslPath([string]$Path) {
    $converted = Invoke-Wsl @('-d', $Distro, '--', 'wslpath', '-u', $Path) 2>$null
    if ($LASTEXITCODE -ne 0 -or -not $converted) {
        throw "Cannot convert path to WSL (distribution '$Distro'): $Path"
    }
    return (($converted | Out-String).Trim())
}

try {
    $buildScriptWsl = Convert-ToWslPath $buildScriptWin
    $attemptScriptWsl = Convert-ToWslPath $attemptScriptWin
    $wslBuildArgs = @(
        foreach ($arg in $BuildArgs) {
            if ($arg -match '^([^=]+)=([A-Za-z]:[\\/].*)$') {
                $name = $Matches[1]
                $windowsPath = $Matches[2]
                "${name}=$(Convert-ToWslPath $windowsPath)"
            }
            else { $arg }
        }
    )
    $statusWin = Join-Path $env:TEMP "ventoy-wsl-build-$([guid]::NewGuid().ToString('N')).status"
    $statusWsl = Convert-ToWslPath $statusWin
}
catch {
    Write-Host "[error] $_" -ForegroundColor Red
    $script:FinalExitCode = 2
    exit $script:FinalExitCode
}

$attempt = 0
$maxAttempts = $Retries + 1
$originalWslEnv = $env:WSLENV
$hadWslEnv = Test-Path Env:WSLENV
try {
    while ($attempt -lt $maxAttempts) {
        $attempt++
        Remove-Item -LiteralPath $statusWin -Force -ErrorAction SilentlyContinue
        Write-Host "[WSL build] $Kind, attempt $attempt/$maxAttempts (distribution $Distro)"

        # Keep this WSL client in the foreground for the entire build. If WSL
        # shuts down, the status remains 'started' and the bounded retry kicks in.
        $wslArgs = @('-d', $Distro)
        $env:WSLENV = $originalWslEnv
        if ($Kind -eq 'windows' -and $env:VENTOY_SORT_MOK_KEY -and $env:VENTOY_SORT_MOK_CRT) {
            $forwardNames = @()
            if ($env:WSLENV) { $forwardNames += ($env:WSLENV).Split(':') }
            foreach ($secretName in @('VENTOY_SORT_MOK_KEY', 'VENTOY_SORT_MOK_CRT')) {
                $alreadyForwarded = @($forwardNames | Where-Object { ($_ -split '/')[0] -eq $secretName }).Count -gt 0
                if (-not $alreadyForwarded) { $forwardNames += "$secretName/u" }
            }
            $env:WSLENV = (($forwardNames | Select-Object -Unique) -join ':')
        }
        $wslArgs += @('--', 'bash', $attemptScriptWsl, $statusWsl, $buildScriptWsl)
        $wslArgs += @($wslBuildArgs)
        Invoke-Wsl $wslArgs
        $wslExit = $LASTEXITCODE

        for ($poll = 0; $poll -lt 20 -and -not (Test-Path -LiteralPath $statusWin); $poll++) {
            Start-Sleep -Milliseconds 250
        }

        if (Test-Path -LiteralPath $statusWin) {
            $status = (Get-Content -LiteralPath $statusWin -Raw).Trim()
            if ($status -match '^done:(\d+)$') {
                $buildExit = [int]$Matches[1]
                if ($buildExit -eq 0) {
                    $script:FinalExitCode = 0
                    break
                }
                if ($buildExit -lt 128) {
                    Write-Host "[error] Build failed with exit code $buildExit; not retrying a normal failure." -ForegroundColor Red
                    $script:FinalExitCode = $buildExit
                    break
                }
                $reason = "WSL build process was interrupted (exit code: $buildExit)"
            }
            elseif ($status -eq 'started') {
                $reason = "WSL stopped before build completion (wsl.exe exit code: $wslExit)"
            }
            else {
                Write-Host "[error] Unexpected WSL status marker '$status' ($statusWin)" -ForegroundColor Red
                $script:FinalExitCode = 2
                break
            }
        }
        else {
            $reason = "WSL stopped before the build started (wsl.exe exit code: $wslExit)"
        }

        if ($attempt -ge $maxAttempts) {
            Write-Host "[error] $reason after $attempt attempt(s); giving up. Run the .cmd again to resume." -ForegroundColor Red
            $script:FinalExitCode = 1
            break
        }
        Write-Warning "$reason; restarting the full build in $RetryDelaySeconds seconds."
        if ($RetryDelaySeconds -gt 0) { Start-Sleep -Seconds $RetryDelaySeconds }
    }
}
finally {
    if ($hadWslEnv) { $env:WSLENV = $originalWslEnv }
    else { Remove-Item Env:WSLENV -ErrorAction SilentlyContinue }
    Remove-Item -LiteralPath $statusWin -Force -ErrorAction SilentlyContinue
}

exit $script:FinalExitCode
