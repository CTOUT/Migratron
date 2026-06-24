[CmdletBinding()]
param(
    [string]$ConfigPath = (Join-Path $PSScriptRoot "usmt-config.json"),
    [switch]$InteractiveDelete
)

# Load shared utilities
. (Join-Path $PSScriptRoot "utils.ps1")

$config = Get-UsmtConfig -ConfigPath $ConfigPath
$outputDirResolved = Resolve-PathVariables -Path $config.backup.outputDir

while ($true) {
    if ($InteractiveDelete) {
        Show-MenuHeader -Title "Manage Backups"
    }
    
    Log "Backup Output Directory: $outputDirResolved" 'INFO'
    
    if (Test-Path $outputDirResolved) {
        $backups = @(Get-ChildItem -Path $outputDirResolved -Filter "migratron-store-*" | 
                   Where-Object { $_.Name -match '^migratron-store-\d{8}-\d{6}(\.zip)?$' } | 
                   Sort-Object LastWriteTime -Descending)
                   
        if ($backups.Count -gt 0) {
            Log "Found $($backups.Count) existing snapshot(s):" 'SUCCESS'
            for ($i = 0; $i -lt $backups.Count; $i++) {
                $b = $backups[$i]
                # Handle uncompressed directories by getting size of contents
                $sizeStr = ""
                if ($b -is [System.IO.DirectoryInfo]) {
                    $dirSize = (Get-ChildItem -Path $b.FullName -Recurse -File -ErrorAction SilentlyContinue | Measure-Object -Property Length -Sum).Sum
                    $sizeStr = Get-FormatSize -Bytes $dirSize
                    $sizeStr += " (Folder)"
                }
                else {
                    $sizeStr = Get-FormatSize -Bytes $b.Length
                    $sizeStr += " (ZIP)"
                }
                
                $prefix = if ($InteractiveDelete) { "[$($i + 1)]" } else { "-" }
                Log "  $prefix $($b.Name) (Size: $sizeStr, Modified: $($b.LastWriteTime))" 'INFO'
            }
        }
        else {
            Log "No previous snapshots found in the output directory." 'INFO'
        }
    }
    else {
        Log "Output directory does not exist yet (it will be created during the first backup)." 'INFO'
    }
    
    if (-not $InteractiveDelete) {
        break
    }
    
    Write-Host ""
    $choice = Read-Host "Enter the number of the backup to delete (or press Enter to return)"
    if ([string]::IsNullOrWhiteSpace($choice)) {
        break
    }
    
    if ($choice -match '^\d+$' -and [int]$choice -ge 1 -and [int]$choice -le $backups.Count) {
        $target = $backups[[int]$choice - 1]
        $confirm = Read-Host "Are you sure you want to permanently delete $($target.Name)? [y/N]"
        if ($confirm -like "y*") {
            Log "Deleting $($target.FullName)..." 'WARN'
            Remove-Item -Path $target.FullName -Recurse -Force
            Log "Deleted successfully." 'SUCCESS'
            Start-Sleep -Seconds 1
        }
    }
    else {
        Log "Invalid selection." 'ERROR'
        Start-Sleep -Seconds 1
    }
}
