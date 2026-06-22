[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$BackupPath,
    [string]$ConfigPath = (Join-Path $PSScriptRoot "usmt-config.json"),
    [switch]$Interactive,
    [switch]$DryRun
)

# Load shared utilities
. (Join-Path $PSScriptRoot "utils.ps1")

# USMT requires admin elevation
Assert-AdminPrivileges

Step "Migratron Restore (LoadState Snapshot)"

# Ensure BackupPath is absolute
if (-not [System.IO.Path]::IsPathRooted($BackupPath)) {
    $BackupPath = [System.IO.Path]::GetFullPath((Join-Path (Get-Location).Path $BackupPath))
}

if (-not (Test-Path $BackupPath)) {
    Log "Backup archive not found at: $BackupPath" 'ERROR'
    return
}

# 1. Load config and find USMT
$config = Get-UsmtConfig -ConfigPath $ConfigPath
$usmtPath = Find-UsmtPath

if ($null -eq $usmtPath) {
    Log "USMT not found! Cannot run LoadState. Run Scan first to see install options." 'ERROR'
    return
}

$timestamp = (Get-Date).ToString("yyyyMMdd-HHmmss")
# --- FIX #8: Use $env:TEMP for staging so orphaned data does not remain in the repo ---
$StagingDir = Join-Path $env:TEMP "migratron-temp-restore-$timestamp"
$logFile    = Join-Path $env:TEMP "loadstate-$timestamp.log"

Log "USMT Binaries : $usmtPath" 'INFO'
Log "LoadState Log : $logFile" 'INFO'

# If interactive, verify user wants to proceed
if ($Interactive) {
    $choice = Read-Host "Restore snapshot from '$BackupPath'? [Y/n]"
    if ($choice -like "n*") {
        Log "Restore aborted by user." 'WARN'
        return
    }
}

# Determine if the BackupPath is a file (zip) or directory
$isZip = $BackupPath -like "*.zip"
$storeFolder = ""

if ($isZip) {
    $storeFolder = $StagingDir
    Log "Extracting backup ZIP to staging: $StagingDir" 'DEBUG'
    if (-not $DryRun) {
        New-Item -ItemType Directory -Path $StagingDir -Force | Out-Null
        Expand-Archive -Path $BackupPath -DestinationPath $StagingDir -Force

        # --- FIX #5: Zip Slip protection ---
        # Verify every extracted path is contained within $StagingDir to prevent
        # directory traversal attacks via crafted ZIP archives.
        $canonicalStaging = [System.IO.Path]::GetFullPath($StagingDir).TrimEnd('\') + '\'
        $extractedItems = Get-ChildItem -Path $StagingDir -Recurse -Force
        foreach ($item in $extractedItems) {
            $canonicalItem = [System.IO.Path]::GetFullPath($item.FullName)
            if (-not $canonicalItem.StartsWith($canonicalStaging, [System.StringComparison]::OrdinalIgnoreCase)) {
                Log "Directory traversal detected in ZIP archive! Aborting restore. Offending entry: $($item.FullName)" 'ERROR'
                Remove-Item -Path $StagingDir -Recurse -Force -ErrorAction SilentlyContinue
                return
            }
        }
        Log "ZIP archive passed directory traversal check." 'DEBUG'
    }
}
else {
    $storeFolder = $BackupPath
    Log "Restoring directly from directory: $storeFolder" 'DEBUG'
}

# Verify USMT.MIG exists
$migFile = Join-Path $storeFolder "USMT.MIG"
if (-not $DryRun -and -not (Test-Path $migFile)) {
    Log "Invalid backup! Could not find USMT.MIG in the backup store: $storeFolder" 'ERROR'
    if ($isZip -and (Test-Path $StagingDir)) {
        Remove-Item -Path $StagingDir -Recurse -Force | Out-Null
    }
    return
}

# Build Arguments for LoadState
$loadStateExe = Join-Path $usmtPath "loadstate.exe"
$xmlArgs = @()
foreach ($xml in $config.usmt.xmlFiles) {
    $localXmlPath = Join-Path $PSScriptRoot $xml
    if (Test-Path $localXmlPath) {
        $xmlArgs += "/i:`"$localXmlPath`""
    }
    else {
        $xmlArgs += "/i:`"$usmtPath\$xml`""
    }
}

# Add standard parameters:
#  /c   - Continue on non-fatal errors
#  /v:13 - Verbose logging
#  /l   - Log file path
$argList = @(
    "`"$storeFolder`"",
    ($xmlArgs -join ' '),
    "/l:`"$logFile`""
)

# Append any custom arguments from config
# --- FIX #3: restrict additionalArgs to a strict allowlist of safe USMT flags ---
$allowedArgPatterns = @(
    '^/c$',
    '^/nocompress$',
    '^/v:\d+$',
    '^/efs:(skip|copyraw|abort|hardlink)$',
    '^/listfiles:.+$',
    '^/offlineWinDir:.+$',
    '^/offlineWinOld:.+$'
)
if ($config.usmt.additionalArgs -and $config.usmt.additionalArgs.Count -gt 0) {
    foreach ($arg in $config.usmt.additionalArgs) {
        $resolvedArg = Resolve-PathVariables -Path $arg
        $matched = $false
        foreach ($pattern in $allowedArgPatterns) {
            if ($resolvedArg -match $pattern) { $matched = $true; break }
        }
        if ($matched) {
            $argList += $resolvedArg
        }
        else {
            Log "Skipping disallowed additionalArg: '$resolvedArg'" 'WARN'
        }
    }
}

$argListString = $argList -join ' '

if ($DryRun) {
    Log "[Dry Run] Would execute: $loadStateExe $argListString" 'SUCCESS'
    if ($isZip -and (Test-Path $StagingDir)) {
        Remove-Item -Path $StagingDir -Recurse -Force | Out-Null
    }
    return
}

Log "Running USMT LoadState restore. This may take a few minutes..." 'INFO'

$processParams = @{
    FilePath     = $loadStateExe
    ArgumentList = $argListString
    Wait         = $true
    NoNewWindow  = $true
    PassThru     = $true
    ErrorAction  = 'Continue'
}

try {
    # Run loadstate
    $result = Start-Process @processParams
    $exitCode = $result.ExitCode
    
    # USMT exit codes:
    # 0 = Success
    # 1 = Success with warnings
    if ($exitCode -eq 0 -or $exitCode -eq 1) {
        Log "LoadState restore completed successfully (Exit Code: $exitCode)." 'SUCCESS'
        Log "Your local application settings and user states have been restored." 'SUCCESS'
    }
    else {
        Log "LoadState failed with exit code: $exitCode." 'ERROR'
        Log "Please check the log file at: $logFile" 'ERROR'
    }
}
catch {
    Log "An error occurred during LoadState execution: $_" 'ERROR'
}
finally {
    # Clean up staging directory
    if ($isZip -and (Test-Path $StagingDir)) {
        Log "Cleaning up staging directory: $StagingDir" 'DEBUG'
        Remove-Item -Path $StagingDir -Recurse -Force -ErrorAction SilentlyContinue | Out-Null
    }
    # Clean up loose log if process failed
    if (Test-Path $logFile) {
        Log "Log file is available at: $logFile" 'INFO'
    }
}
