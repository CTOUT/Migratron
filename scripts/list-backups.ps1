[CmdletBinding()]
param(
    [string]$ConfigPath = (Join-Path $PSScriptRoot "usmt-config.json")
)

# Load shared utilities
. (Join-Path $PSScriptRoot "utils.ps1")

$config = Get-UsmtConfig -ConfigPath $ConfigPath
$outputDirResolved = Resolve-PathVariables -Path $config.backup.outputDir

Log "Backup Output Directory: $outputDirResolved" 'INFO'
if (Test-Path $outputDirResolved) {
    $backups = Get-ChildItem -Path $outputDirResolved -Filter "migratron-store-*" | 
               Where-Object { $_.Name -match '^migratron-store-\d{8}-\d{6}(\.zip)?$' } | 
               Sort-Object LastWriteTime -Descending
    if ($backups.Count -gt 0) {
        Log "Found $($backups.Count) existing snapshot(s):" 'SUCCESS'
        foreach ($b in $backups) {
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
            Log "  - $($b.Name) (Size: $sizeStr, Modified: $($b.LastWriteTime))" 'INFO'
        }
    }
    else {
        Log "No previous snapshots found in the output directory." 'INFO'
    }
}
else {
    Log "Output directory does not exist yet (it will be created during the first backup)." 'INFO'
}
