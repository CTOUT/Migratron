[CmdletBinding()]
param(
    [string]$ConfigPath = (Join-Path $PSScriptRoot "usmt-config.json")
)

# Load shared utilities
. (Join-Path $PSScriptRoot "utils.ps1")

Step "Migratron USMT System Scan & Audit"

# 1. Read config
$config = Get-UsmtConfig -ConfigPath $ConfigPath
$outputDirResolved = Resolve-PathVariables -Path $config.backup.outputDir

# 2. Check USMT
$usmtPath = Find-UsmtPath
if ($null -ne $usmtPath) {
    Log "USMT Status: FOUND" 'SUCCESS'
    Log "USMT Path  : $usmtPath" 'INFO'
    
    # Check for requested XML files
    foreach ($xml in $config.usmt.xmlFiles) {
        $localXmlPath = Join-Path $PSScriptRoot $xml
        if (Test-Path $localXmlPath) {
            Log "  [✓] XML Rule: $xml (Found locally in repo)" 'SUCCESS'
        } elseif (Test-Path (Join-Path $usmtPath $xml)) {
            Log "  [✓] XML Rule: $xml (Found in USMT directory)" 'SUCCESS'
        } else {
            Log "  [X] XML Rule: $xml (MISSING! Not found locally or in USMT directory)" 'ERROR'
        }
    }
} else {
    Log "USMT Status: NOT FOUND" 'ERROR'
    Log "USMT is required for Migratron snapshots." 'WARN'
    Write-Host ""
    Write-Host "To resolve this:" -ForegroundColor Cyan
    Write-Host "  1. Download and install the Windows Assessment and Deployment Kit (ADK):" -ForegroundColor Gray
    Write-Host "     https://learn.microsoft.com/en-us/windows-hardware/get-started/adk-install" -ForegroundColor Gray
    Write-Host "  2. Or, copy the USMT folders ('amd64' or 'x86') from an ADK installation directly into a folder named 'usmt' in the repository root." -ForegroundColor Gray
    Write-Host "  3. Or, configure 'customPath' in scripts/usmt-config.json to point to your scanstate.exe folder." -ForegroundColor Gray
    Write-Host ""
}

# 3. Check OneDrive Sync Transport
$oneDrivePath = $env:OneDrive
if ([string]::IsNullOrEmpty($oneDrivePath)) {
    $oneDrivePath = $env:OneDriveConsumer
}
if ([string]::IsNullOrEmpty($oneDrivePath)) {
    $oneDrivePath = $env:OneDriveCommercial
}

if (-not [string]::IsNullOrEmpty($oneDrivePath) -and (Test-Path $oneDrivePath)) {
    Log "OneDrive Status: ACTIVE" 'SUCCESS'
    Log "OneDrive Path  : $oneDrivePath" 'INFO'
} else {
    Log "OneDrive Status: NOT DETECTED (or not signed in)" 'WARN'
    Log "Backups will be saved locally, but will not sync automatically to the cloud." 'WARN'
}

# 4. Check Stored Snapshots
Log "Backup Output Directory: $outputDirResolved" 'INFO'
if (Test-Path $outputDirResolved) {
    $backups = Get-ChildItem -Path $outputDirResolved -Filter "migratron-store-*.zip" -File | Sort-Object LastWriteTime -Descending
    if ($backups.Count -gt 0) {
        Log "Found $($backups.Count) existing snapshot(s):" 'SUCCESS'
        foreach ($b in $backups) {
            $size = Get-FormatSize -Bytes $b.Length
            Log "  - $($b.Name) (Size: $size, Modified: $($b.LastWriteTime))" 'INFO'
        }
    } else {
        Log "No previous snapshots found in the output directory." 'INFO'
    }
} else {
    Log "Output directory does not exist yet (it will be created during the first backup)." 'INFO'
}

Write-Host ""
$adminStatus = "Standard User (Not Elevated)"
$adminLevel = 'WARN'
if (Test-IsAdmin) {
    $adminStatus = "Administrator (Elevated)"
    $adminLevel = 'SUCCESS'
}
Log "Current Session Privilege: $adminStatus" -Level $adminLevel

