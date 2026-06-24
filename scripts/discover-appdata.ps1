[CmdletBinding()]
param()

. (Join-Path $PSScriptRoot "utils.ps1")

$scanPaths = @(
    $env:APPDATA,
    $env:LOCALAPPDATA,
    (Join-Path $env:USERPROFILE "AppData\LocalLow"),
    (Join-Path $env:USERPROFILE "Saved Games")
)

# Aggressive heuristics to drop caches, built-ins, and generic hardware/software bloat
$excludePattern = '(?i)^(Microsoft|Packages|CrashDumps|Temp|Cache|logs?|Temporary Internet Files|Code Cache|GPUCache|Crashpad|NVIDIA.*|AMD|Intel.*|Radeon.*|Dropbox|Zoom|WebEx|Slack|Teams.*|GitHubDesktop|Docker)$'

$candidates = [System.Collections.Generic.List[object]]::new()

Write-Host "Scanning application data and game saves (this may take a moment)..." -ForegroundColor Cyan

foreach ($path in $scanPaths) {
    if (-not (Test-Path $path)) { continue }
    
    $dirs = Get-ChildItem -Path $path -Directory -ErrorAction SilentlyContinue
    foreach ($dir in $dirs) {
        if ($dir.Name -match $excludePattern) { continue }
        
        # Skip junctions/symlinks (like folders manually redirected to OneDrive)
        if ($dir.Attributes -match 'ReparsePoint') { continue }
        
        # Calculate folder size and find config extensions
        $sizeBytes = 0
        $hasConfigExt = $false
        try {
            $files = Get-ChildItem -Path $dir.FullName -Recurse -File -Force -ErrorAction SilentlyContinue
            if ($files) {
                $sizeBytes = ($files | Measure-Object -Property Length -Sum).Sum
                $exts = $files.Extension | Select-Object -Unique
                if ($exts -match '(?i)^\.(json|cfg|ini|xml|yml|yaml)$') {
                    $hasConfigExt = $true
                }
            }
        } catch {}
        
        # Skip empty folders
        if ($sizeBytes -eq 0 -or $null -eq $sizeBytes) { continue }

        # Format the path using environment variables for portability
        $varPath = $dir.FullName
        if ($varPath -imatch [regex]::Escape($env:APPDATA)) {
            $varPath = $varPath -ireplace [regex]::Escape($env:APPDATA), '%APPDATA%'
        } elseif ($varPath -imatch [regex]::Escape($env:LOCALAPPDATA)) {
            $varPath = $varPath -ireplace [regex]::Escape($env:LOCALAPPDATA), '%LOCALAPPDATA%'
        } else {
            $varPath = $varPath -ireplace [regex]::Escape($env:USERPROFILE), '%USERPROFILE%'
        }
        
        $baseType = "Saved Games"
        if ($path -eq $env:APPDATA) { $baseType = "Roaming" }
        elseif ($path -eq $env:LOCALAPPDATA) { $baseType = "Local" }
        elseif ($path -match "LocalLow") { $baseType = "LocalLow" }

        $nameMatch = ($dir.Name -match '(?i)^(save|conf|setting)')

        $rec = ""
        if ($nameMatch -or $hasConfigExt -or $baseType -eq "Saved Games") {
            if ($sizeBytes -gt 1GB) { $rec = "[HEAVY]" }
            else { $rec = "[OK]" }
        } else {
            if ($sizeBytes -lt 250MB) { $rec = "[OK]" }
            elseif ($sizeBytes -gt 1GB) { $rec = "[HEAVY]" }
            else { $rec = "[-]" }
        }

        $candidates.Add([pscustomobject]@{
            Id = 0
            Name = $dir.Name
            FullPath = $dir.FullName
            VarPath = $varPath
            SizeBytes = $sizeBytes
            FormatSize = Get-FormatSize -Bytes $sizeBytes
            BaseType = $baseType
            Rec = $rec
        })
    }
}

if ($candidates.Count -eq 0) {
    Write-Host "No 3rd-party configuration folders found." -ForegroundColor Yellow
    return
}

# Sort candidates by size (descending)
$sortedCandidates = $candidates | Sort-Object SizeBytes -Descending

# Assign IDs
for ($i = 0; $i -lt $sortedCandidates.Count; $i++) {
    $sortedCandidates[$i].Id = $i + 1
}

Show-MenuHeader -Title "Discovered Configuration Folders"
Write-Host " ID | Rec     | Type       | Size       | Name / Path" -ForegroundColor Cyan
Write-Host "----|---------|------------|------------|-------------------------------------------"
foreach ($item in $sortedCandidates) {
    $idPad = $item.Id.ToString().PadLeft(2)
    $recPad = $item.Rec.PadRight(7)
    $typePad = $item.BaseType.PadRight(10)
    $sizePad = $item.FormatSize.PadRight(10)
    
    if ($item.Rec -eq "[HEAVY]") {
        Write-Host " $idPad | $recPad | $typePad | $sizePad | $($item.VarPath)" -ForegroundColor Red
    } elseif ($item.Rec -eq "[OK]") {
        Write-Host " $idPad | $recPad | $typePad | $sizePad | $($item.VarPath)" -ForegroundColor Green
    } else {
        Write-Host " $idPad | $recPad | $typePad | $sizePad | $($item.VarPath)"
    }
}
Write-Host "----|---------|------------|------------|-------------------------------------------"

Write-Host "`nInstructions:" -ForegroundColor Yellow
Write-Host " - Enter the IDs of folders you wish to backup, separated by commas (e.g. '1, 4, 7')"
Write-Host " - You can also use ranges (e.g. '1-5')"
Write-Host " - Type 'all' to select everything, or leave empty to cancel."
$selection = Read-Host "`nEnter selection"

if ([string]::IsNullOrWhiteSpace($selection)) {
    Write-Host "[-] Operation cancelled." -ForegroundColor DarkGray
    return
}

$selectedIds = @()
if ($selection -match '(?i)^all$') {
    $selectedIds = $sortedCandidates.Id
} else {
    $parts = $selection -split ','
    foreach ($part in $parts) {
        $part = $part.Trim()
        if ($part -match '^(\d+)-(\d+)$') {
            $start = [int]$matches[1]
            $end = [int]$matches[2]
            if ($start -le $end) {
                $selectedIds += $start..$end
            } else {
                $selectedIds += $end..$start
            }
        } elseif ($part -match '^\d+$') {
            $selectedIds += [int]$part
        }
    }
}

$selectedIds = $selectedIds | Sort-Object -Unique

$pathsToAdd = @()
foreach ($id in $selectedIds) {
    $item = $sortedCandidates | Where-Object { $_.Id -eq $id }
    if ($item) {
        $pathsToAdd += $item.VarPath
    }
}

if ($pathsToAdd.Count -eq 0) {
    Write-Host "[-] No valid folders selected." -ForegroundColor Yellow
    return
}

# Load existing config
$localCfg = Get-LocalConfig
if (-not $localCfg.psobject.Properties.Match('backup')) {
    $localCfg | Add-Member -MemberType NoteProperty -Name "backup" -Value (New-Object PSObject)
}
if (-not $localCfg.backup.psobject.Properties.Match('includePaths')) {
    $localCfg.backup | Add-Member -MemberType NoteProperty -Name "includePaths" -Value @()
}

$currentIncludes = @($localCfg.backup.includePaths)
$addedCount = 0

foreach ($path in $pathsToAdd) {
    if ($currentIncludes -notcontains $path) {
        $currentIncludes += $path
        $addedCount++
    }
}

if ($addedCount -gt 0) {
    $localCfg.backup.includePaths = $currentIncludes
    Set-LocalConfig -ConfigObject $localCfg
    Write-Host "`n[√] Success: Added $addedCount folder(s) to your includePaths!" -ForegroundColor Green
} else {
    Write-Host "`n[i] No new folders added (they were already in your includePaths)." -ForegroundColor Cyan
}

Start-Sleep -Seconds 2
