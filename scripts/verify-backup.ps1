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

Step "Migratron Verification (USMTUtils)"

# Ensure BackupPath is absolute
if (-not [System.IO.Path]::IsPathRooted($BackupPath)) {
    $BackupPath = [System.IO.Path]::GetFullPath((Join-Path (Get-Location).Path $BackupPath))
}

if (-not (Test-Path $BackupPath)) {
    Log "Backup archive not found at: $BackupPath" 'ERROR'
    return
}

$config = Get-UsmtConfig -ConfigPath $ConfigPath
$usmtPath = Find-UsmtPath

if ($null -eq $usmtPath) {
    Log "USMT not found! Cannot run verification. Run Scan first to see install options." 'ERROR'
    return
}

$timestamp = (Get-Date).ToString("yyyyMMdd-HHmmss")
$StagingDir = Join-Path $env:TEMP "migratron-temp-verify-$timestamp"
$logFile    = Join-Path $env:TEMP "verify-$timestamp.log"

Log "USMT Binaries : $usmtPath" 'INFO'
Log "Verify Log    : $logFile" 'INFO'

$isZip = $BackupPath -like "*.zip"
$storeFolder = ""

if ($isZip) {
    $storeFolder = $StagingDir
    Log "Extracting backup ZIP to staging: $StagingDir" 'DEBUG'
    if (-not $DryRun) {
        New-Item -ItemType Directory -Path $StagingDir -Force | Out-Null
        Expand-Archive -Path $BackupPath -DestinationPath $StagingDir -Force

        $canonicalStaging = [System.IO.Path]::GetFullPath($StagingDir).TrimEnd('\') + '\'
        $extractedItems = Get-ChildItem -Path $StagingDir -Recurse -Force
        foreach ($item in $extractedItems) {
            $canonicalItem = [System.IO.Path]::GetFullPath($item.FullName)
            if (-not $canonicalItem.StartsWith($canonicalStaging, [System.StringComparison]::OrdinalIgnoreCase)) {
                Log "Directory traversal detected in ZIP archive! Aborting verify. Offending entry: $($item.FullName)" 'ERROR'
                Remove-Item -Path $StagingDir -Recurse -Force -ErrorAction SilentlyContinue
                return
            }
        }
    }
}
else {
    $storeFolder = $BackupPath
}

# Recursively locate USMT.MIG inside the store folder
$migFile = $null
if (-not $DryRun) {
    $migFiles = Get-ChildItem -Path $storeFolder -Filter "USMT.MIG" -Recurse -File -ErrorAction SilentlyContinue
    if ($migFiles -and $migFiles.Count -gt 0) {
        $migFile = $migFiles[0].FullName
    }
    
    if ($null -eq $migFile -or -not (Test-Path $migFile)) {
        Log "Invalid backup! Could not find USMT.MIG in the backup store: $storeFolder" 'ERROR'
        if ($isZip -and (Test-Path $StagingDir)) {
            Remove-Item -Path $StagingDir -Recurse -Force | Out-Null
        }
        return
    }
}

$usmtUtilsExe = Join-Path $usmtPath "usmtutils.exe"
$baseArgList = @(
    "/verify",
    "`"$migFile`"",
    "/l:`"$logFile`""
)

# Loop to allow password fallback
$maxAttempts = 3
$attempt = 0
$success = $false

while ($attempt -lt $maxAttempts -and -not $success) {
    $argList = @() + $baseArgList
    $tempKeyFile = $null
    
    if ($config.backup.encrypt) {
        $encryptionKey = $config.backup.encryptionKey
        
        if ($attempt -gt 0 -or [string]::IsNullOrWhiteSpace($encryptionKey)) {
            if ($attempt -gt 0) {
                Write-Host ""
                $retry = Read-Host "[!] Decryption failed. Do you want to manually enter a custom password? [y/N]"
                if ($retry -notlike "y*") {
                    Log "Verification aborted by user." 'WARN'
                    break
                }
            } else {
                Log "Encryption is enabled, but no key was found in the configuration." 'WARN'
            }
            $secPwd = Read-Host "Enter the AES-256 decryption password for this backup" -AsSecureString
            $encryptionKey = Convert-SecureStringToPlaintext -SecureString $secPwd
            if ([string]::IsNullOrWhiteSpace($encryptionKey)) {
                Log "Decryption password cannot be empty. Aborting verify." 'ERROR'
                break
            }
        }
        
        $tempKeyFile = Join-Path $env:TEMP "migratron-key-$timestamp-$attempt.txt"
        $utf8NoBom = New-Object System.Text.UTF8Encoding $false
        [System.IO.File]::WriteAllText($tempKeyFile, $encryptionKey, $utf8NoBom)
        
        $argList += "/decrypt:AES_256"
        $argList += "/keyfile:`"$tempKeyFile`""
    }
    
    $argListString = $argList -join ' '
    
    if ($DryRun) {
        Log "[Dry Run] Would execute: $usmtUtilsExe $argListString" 'SUCCESS'
        $success = $true
        break
    }
    
    Log "Running USMTUtils verification. This may take a few minutes..." 'INFO'
    
    $processParams = @{
        FilePath     = $usmtUtilsExe
        ArgumentList = $argListString
        Wait         = $true
        NoNewWindow  = $true
        PassThru     = $true
        ErrorAction  = 'Continue'
    }
    
    try {
        $result = Start-Process @processParams
        $exitCode = $result.ExitCode
        
        if ($exitCode -eq 0) {
            Log "Verification completed successfully! (Return Code: 0)" 'SUCCESS'
            $success = $true
        }
        elseif ($exitCode -eq 37 -and $config.backup.encrypt) {
            # 37 usually indicates a decryption error (wrong key, bad BOM, invalid BSTR)
            Log "Decryption error occurred (Return Code: 37). The provided encryption key is incorrect." 'ERROR'
            $attempt++
        }
        else {
            Log "Verification failed! Return Code: $exitCode. Check the log for details: $logFile" 'ERROR'
            break
        }
    }
    catch {
        Log "Error running usmtutils.exe: $_" 'ERROR'
        break
    }
    finally {
        if ($tempKeyFile -and (Test-Path $tempKeyFile)) {
            Remove-Item -Path $tempKeyFile -Force -ErrorAction SilentlyContinue
        }
    }
}

if ($isZip -and (Test-Path $StagingDir)) {
    Log "Cleaning up staging directory: $StagingDir" 'DEBUG'
    Remove-Item -Path $StagingDir -Recurse -Force -ErrorAction SilentlyContinue
}
