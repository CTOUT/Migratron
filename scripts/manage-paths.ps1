param()

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Definition
. (Join-Path $ScriptDir "utils.ps1")

$localCfg = Get-LocalConfig

while ($true) {
    Clear-Host
    Show-MenuHeader -Title "Manage Included Custom Paths"
    
    $paths = @()
    if ($null -ne $localCfg.psobject.Properties['backup'] -and $null -ne $localCfg.backup.psobject.Properties['includePaths']) {
        $paths = @($localCfg.backup.includePaths)
    }
    
    if ($paths.Count -eq 0) {
        Write-Host "[-] No custom paths currently configured.`n" -ForegroundColor DarkGray
        $choice = Read-Host "Press Enter to return"
        return
    }
    
    Write-Host " ID | Path" -ForegroundColor Cyan
    Write-Host "----|-------------------------------------------------"
    for ($i=0; $i -lt $paths.Count; $i++) {
        $idPad = ($i+1).ToString().PadLeft(2)
        Write-Host " $idPad | $($paths[$i])"
    }
    Write-Host "----|-------------------------------------------------"
    
    Write-Host "`nInstructions:" -ForegroundColor Yellow
    Write-Host " - Enter the IDs of paths you wish to REMOVE, separated by commas (e.g. '1, 4')"
    Write-Host " - You can also use ranges (e.g. '1-5')"
    Write-Host " - Type 'clear' to permanently remove all paths."
    Write-Host " - Leave empty and press Enter to return."
    $selection = Read-Host "`nEnter selection"
    
    if ([string]::IsNullOrWhiteSpace($selection)) {
        return
    }
    
    if ($selection -match '(?i)^clear$') {
        $localCfg.backup.includePaths = @()
        Set-LocalConfig -ConfigObject $localCfg
        Write-Host "`n[√] All custom paths successfully removed!" -ForegroundColor Green
        Start-Sleep -Seconds 1
        continue
    }
    
    # Parse IDs
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
        $localCfg.backup.includePaths = $newPaths
        Set-LocalConfig -ConfigObject $localCfg
        Write-Host "`n[√] Removed $($selectedIndices.Count) paths from configuration!" -ForegroundColor Green
        Start-Sleep -Seconds 1
    } else {
        Write-Host "`n[-] Invalid selection." -ForegroundColor Red
        Start-Sleep -Seconds 1
    }
}
