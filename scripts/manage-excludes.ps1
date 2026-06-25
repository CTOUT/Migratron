param()

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Definition
. (Join-Path $ScriptDir "utils.ps1")

$localCfg = Get-LocalConfig

# Ensure backup and excludePaths exist
if ($null -eq $localCfg.psobject.Properties['backup']) {
    $localCfg | Add-Member -NotePropertyName "backup" -NotePropertyValue ([PSCustomObject]@{ excludePaths = @() })
}
if ($null -eq $localCfg.backup.psobject.Properties['excludePaths']) {
    $localCfg.backup | Add-Member -NotePropertyName "excludePaths" -NotePropertyValue @()
}

while ($true) {
    Clear-Host
    Show-MenuHeader -Title "Manage Excluded Custom Paths"
    
    $paths = @($localCfg.backup.excludePaths)
    
    if ($paths.Count -eq 0) {
        Write-Host "[-] No custom exclusions currently configured.`n" -ForegroundColor Gray
    } else {
        Write-Host " ID | Path" -ForegroundColor Cyan
        Write-Host "----|-------------------------------------------------"
        for ($i=0; $i -lt $paths.Count; $i++) {
            $idPad = ($i+1).ToString().PadLeft(2)
            Write-Host " $idPad | $($paths[$i])"
        }
        Write-Host "----|-------------------------------------------------"
    }
    
    Write-Host "`nInstructions:" -ForegroundColor Yellow
    Write-Host " - Type 'add <path>' to add a new exclusion (e.g., 'add D:\Games')"
    if ($paths.Count -gt 0) {
        Write-Host " - Enter the IDs of paths you wish to REMOVE, separated by commas (e.g. '1, 4')"
        Write-Host " - You can also use ranges (e.g. '1-5')"
        Write-Host " - Type 'clear' to permanently remove all exclusions."
    }
    Write-Host " - Leave empty and press Enter to return."
    $selection = Read-Host "`nEnter selection"
    
    if ([string]::IsNullOrWhiteSpace($selection)) {
        return
    }
    
    if ($selection -match '(?i)^add\s+(.+)$') {
        $newPath = $matches[1].Trim()
        if ($paths -contains $newPath) {
            Write-Host "`n[-] Path already exists in exclusions." -ForegroundColor Yellow
        } else {
            $paths += $newPath
            $localCfg.backup.excludePaths = $paths | Sort-Object
            Set-LocalConfig -ConfigObject $localCfg
            Write-Host "`n[√] Added '$newPath' to exclusions!" -ForegroundColor Green
        }
        Start-Sleep -Seconds 1
        continue
    }
    
    if ($paths.Count -eq 0) {
        Write-Host "`n[-] Invalid selection." -ForegroundColor Red
        Start-Sleep -Seconds 1
        continue
    }
    
    if ($selection -match '(?i)^clear$') {
        $localCfg.backup.excludePaths = @()
        Set-LocalConfig -ConfigObject $localCfg
        Write-Host "`n[√] All custom exclusions successfully removed!" -ForegroundColor Green
        Start-Sleep -Seconds 1
        continue
    }
    
    # Parse IDs for removal
    $selectedIndices = @()
    $parts = $selection -split ','
    foreach ($part in $parts) {
        $part = $part.Trim()
        if ($part -match '^(\d+)-(\d+)$') {
            $start = [int]$matches[1]
            $end = [int]$matches[2]
            if ($start -le $end) {
                $selectedIndices += $start..$end
            } else {
                $selectedIndices += $end..$start
            }
        } elseif ($part -match '^\d+$') {
            $selectedIndices += [int]$part
        }
    }
    
    $selectedIndices = $selectedIndices | Sort-Object -Unique | Where-Object { $_ -ge 1 -and $_ -le $paths.Count }
    
    if ($selectedIndices.Count -gt 0) {
        $newPaths = @()
        for ($i=0; $i -lt $paths.Count; $i++) {
            if ($selectedIndices -notcontains ($i+1)) {
                $newPaths += $paths[$i]
            }
        }
        $localCfg.backup.excludePaths = $newPaths | Sort-Object
        Set-LocalConfig -ConfigObject $localCfg
        Write-Host "`n[√] Removed $($selectedIndices.Count) paths from configuration!" -ForegroundColor Green
        Start-Sleep -Seconds 1
    } else {
        Write-Host "`n[-] Invalid selection." -ForegroundColor Red
        Start-Sleep -Seconds 1
    }
}
