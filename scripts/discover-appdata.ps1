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
$excludePattern = '(?i)^(Microsoft|Packages|Programs|CrashDumps|Temp|.*cache.*|logs?|Temporary Internet Files|Crashpad|NVIDIA.*|AMD|Intel.*|Radeon.*|Dropbox|Zoom|WebEx|Slack|Teams.*|GitHubDesktop|Docker|HammerAI|Vortex.*)$'

$candidates = [System.Collections.Generic.List[object]]::new()

Write-Host "Scanning application data and game saves (this may take a moment)..." -ForegroundColor Cyan

foreach ($path in $scanPaths) {
    if (-not (Test-Path $path)) { continue }
    
    $dirs = Get-ChildItem -Path $path -Directory -ErrorAction SilentlyContinue
    foreach ($dir in $dirs) {
        if ($dir.Name -match $excludePattern) { continue }
        
        # Skip junctions/symlinks (like folders manually redirected to OneDrive)
        if ($dir.Attributes -match 'ReparsePoint') { continue }
        
        # Calculate folder size, config extensions, and interesting subdirectories
        $sizeBytes = 0
        $hasConfigExt = $false
        $hasInterestingDir = $false
        try {
            $items = Get-ChildItem -Path $dir.FullName -Recurse -Force -ErrorAction SilentlyContinue
            if ($items) {
                $files = $items | Where-Object { -not $_.PSIsContainer }
                $subDirs = $items | Where-Object { $_.PSIsContainer }
                
                if ($files) {
                    $sizeBytes = ($files | Measure-Object -Property Length -Sum).Sum
                    
                    # Calculate filtered size based on ExcludeCommon rules
                    $filteredFiles = $files | Where-Object {
                        $_.FullName -notmatch '(?i)\\(workspaceStorage|globalStorage|CachedData|Cache|Code Cache|GPUCache|Crashpad|Temp|TMP|Temporary)\\'
                    }
                    if ($filteredFiles) {
                        $filteredSizeBytes = ($filteredFiles | Measure-Object -Property Length -Sum).Sum
                    } else {
                        $filteredSizeBytes = 0
                    }

                    $exts = $files.Extension | Select-Object -Unique
                    if ($exts -match '(?i)^\.(json|cfg|ini|xml|yml|yaml)$') {
                        $hasConfigExt = $true
                    }
                }
                
                if ($subDirs) {
                    $interesting = $subDirs | Where-Object { $_.Name -match '(?i)^(save|conf|setting)' } | Select-Object -First 1
                    if ($interesting) {
                        $hasInterestingDir = $true
                    }
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
        if ($nameMatch -or $hasInterestingDir -or $hasConfigExt -or $baseType -eq "Saved Games") {
            if ($filteredSizeBytes -gt 1GB) { $rec = "[HEAVY]" }
            else { $rec = "[OK]" }
        } else {
            if ($filteredSizeBytes -lt 250MB) { $rec = "[OK]" }
            elseif ($filteredSizeBytes -gt 1GB) { $rec = "[HEAVY]" }
            else { $rec = "[-]" }
        }

        $candidates.Add([pscustomobject]@{
            Id = 0
            Name = $dir.Name
            FullPath = $dir.FullName
            VarPath = $varPath
            SizeBytes = $sizeBytes
            FilteredSizeBytes = $filteredSizeBytes
            FormatSize = Get-FormatSize -Bytes $sizeBytes
            FormatFilteredSize = Get-FormatSize -Bytes $filteredSizeBytes
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

$lastActionMessage = ""
$currentPage = 0

while ($true) {
    Clear-Host

    # Load existing config dynamically for each redraw
    $localCfg = Get-LocalConfig
    if ($null -eq $localCfg.psobject.Properties['backup']) {
        $localCfg | Add-Member -MemberType NoteProperty -Name "backup" -Value (New-Object PSObject)
    }
    if ($null -eq $localCfg.backup.psobject.Properties['includePaths']) {
        $localCfg.backup | Add-Member -MemberType NoteProperty -Name "includePaths" -Value @()
    }
    if ($null -eq $localCfg.backup.psobject.Properties['excludePaths']) {
        $localCfg.backup | Add-Member -MemberType NoteProperty -Name "excludePaths" -Value @()
    }

    $currentIncludes = @($localCfg.backup.includePaths)
    $currentExcludes = @($localCfg.backup.excludePaths)

    # Calculate page size based on terminal height (reserving 19 lines for headers/footers/prompts)
    $terminalHeight = 40
    try { $terminalHeight = $Host.UI.RawUI.WindowSize.Height } catch {}
    $pageSize = $terminalHeight - 19
    if ($pageSize -lt 5) { $pageSize = 10 } # fallback

    $totalPages = [math]::Ceiling($sortedCandidates.Count / $pageSize)
    if ($currentPage -ge $totalPages) { $currentPage = [math]::Max(0, $totalPages - 1) }
    if ($currentPage -lt 0) { $currentPage = 0 }

    $startIndex = $currentPage * $pageSize
    $pageItems = $sortedCandidates | Select-Object -Skip $startIndex -First $pageSize

    Show-MenuHeader -Title "Discovered Configuration Folders" -Subtitle "Page $($currentPage + 1) of $totalPages"
    Write-Host " ID | Rec     | Status | Type       | Size (Raw) | Size (Net) | Name / Path" -ForegroundColor Cyan
    Write-Host "----|---------|--------|------------|------------|------------|-------------------------------------------"
    
    foreach ($item in $pageItems) {
        $idPad = $item.Id.ToString().PadLeft(2)
        $recPad = $item.Rec.PadRight(7)
        $typePad = $item.BaseType.PadRight(10)
        $sizePad = $item.FormatSize.PadRight(10)
        $filtPad = $item.FormatFilteredSize.PadRight(10)
        
        $statusStr = "[ - ]"
        $statusColor = "DarkGray"
        if ($currentIncludes -contains $item.VarPath) {
            $statusStr = "[INC]"
            $statusColor = "Green"
        } elseif ($currentExcludes -contains $item.VarPath) {
            $statusStr = "[EXC]"
            $statusColor = "Red"
        }
        $statPad = $statusStr.PadRight(6)

        Write-Host -NoNewline " $idPad | "
        if ($item.Rec -eq "[HEAVY]") { Write-Host -NoNewline "$recPad" -ForegroundColor Red }
        elseif ($item.Rec -eq "[OK]") { Write-Host -NoNewline "$recPad" -ForegroundColor Green }
        else { Write-Host -NoNewline "$recPad" }
        
        Write-Host -NoNewline " | "
        Write-Host -NoNewline "$statPad" -ForegroundColor $statusColor
        Write-Host " | $typePad | $sizePad | $filtPad | $($item.VarPath)"
    }
    Write-Host "----|---------|--------|------------|------------|------------|-------------------------------------------"

    if ($lastActionMessage) {
        Write-Host "`n$lastActionMessage" -ForegroundColor Green
        $lastActionMessage = ""
    }

    Write-Host "`nInstructions:" -ForegroundColor Yellow
    Write-Host " - Type 'n' for Next Page, 'p' for Previous Page (or just press Enter for Next)"
    Write-Host " - To INCLUDE folders, type 'i' followed by IDs (e.g. 'i 1, 4, 7-10')"
    Write-Host " - To EXCLUDE folders, type 'e' followed by IDs (e.g. 'e 2, 5')"
    Write-Host " - To REMOVE folders, type 'r' followed by IDs (e.g. 'r 3')"
    Write-Host " - Type 'q' or 'exit' when you are finished."

    $selection = Read-Host "`nEnter selection [n, p, i, e, r, or q]"
    $selection = $selection.Trim()

    if ([string]::IsNullOrWhiteSpace($selection) -or $selection -eq 'n') {
        if ($currentPage -lt ($totalPages - 1)) { $currentPage++ }
        else { $lastActionMessage = "[-] You are on the last page." }
        continue
    }

    if ($selection -match '(?i)^(q|quit|exit)$') {
        Write-Host "[-] Finished discovery." -ForegroundColor DarkGray
        return
    }

    if ($selection -match '(?i)^p$') {
        if ($currentPage -gt 0) { $currentPage-- }
        else { $lastActionMessage = "[-] You are on the first page." }
        continue
    }

    $action = "include"
    $idString = $selection

    if ($selection -match '(?i)^([ier])\s+(.*)$') {
        $prefix = $matches[1].ToLower()
        $idString = $matches[2]
        if ($prefix -eq 'e') { $action = "exclude" }
        elseif ($prefix -eq 'r') { $action = "remove" }
    } elseif ($selection -match '^\d') {
        # Defaults to include if just numbers are typed
        $action = "include"
    } else {
        $lastActionMessage = "[-] Unknown command. Please try again."
        continue
    }

    $selectedIds = @()
    if ($idString -match '(?i)^all$') {
        $selectedIds = $sortedCandidates.Id
    } else {
        $parts = $idString -split ','
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
        $lastActionMessage = "[-] No valid folders selected. Try again."
        continue
    }

    $addedCount = 0

    if ($action -eq "include") {
        foreach ($path in $pathsToAdd) {
            if ($currentIncludes -notcontains $path) {
                $currentIncludes += $path
                $addedCount++
            }
            $currentExcludes = $currentExcludes | Where-Object { $_ -ne $path }
        }
        $localCfg.backup.includePaths = $currentIncludes | Sort-Object -Unique
        $localCfg.backup.excludePaths = $currentExcludes | Sort-Object -Unique
        Set-LocalConfig -ConfigObject $localCfg
        $lastActionMessage = "[√] Added $addedCount folder(s) to INCLUSIONS!"
    } elseif ($action -eq "exclude") {
        foreach ($path in $pathsToAdd) {
            if ($currentExcludes -notcontains $path) {
                $currentExcludes += $path
                $addedCount++
            }
            $currentIncludes = $currentIncludes | Where-Object { $_ -ne $path }
        }
        $localCfg.backup.includePaths = $currentIncludes | Sort-Object -Unique
        $localCfg.backup.excludePaths = $currentExcludes | Sort-Object -Unique
        Set-LocalConfig -ConfigObject $localCfg
        $lastActionMessage = "[√] Added $addedCount folder(s) to EXCLUSIONS!"
    } elseif ($action -eq "remove") {
        $removedCount = 0
        foreach ($path in $pathsToAdd) {
            if ($currentIncludes -contains $path -or $currentExcludes -contains $path) {
                $removedCount++
            }
            $currentIncludes = $currentIncludes | Where-Object { $_ -ne $path }
            $currentExcludes = $currentExcludes | Where-Object { $_ -ne $path }
        }
        $localCfg.backup.includePaths = $currentIncludes | Sort-Object -Unique
        $localCfg.backup.excludePaths = $currentExcludes | Sort-Object -Unique
        Set-LocalConfig -ConfigObject $localCfg
        $lastActionMessage = "[√] Removed $removedCount folder(s) from both lists!"
    }
}
