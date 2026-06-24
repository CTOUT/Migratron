<#
.SYNOPSIS
    Migratron - Windows Settings Migration Toolkit (USMT Edition)
    Version: 1.1.0

.DESCRIPTION
    A lightweight utility that wraps Windows User State Migration Tool (USMT)
    to scan, backup, and restore local application settings, configs, and registry.

.PARAMETER Scan
    Performs a system scan to check USMT installation, OneDrive status, and existing backups.

.PARAMETER Backup
    Executes a ScanState snapshot, saving a ZIP package to your backup output folder.

.PARAMETER Restore
    Executes a LoadState restoration, copying settings back from a backup archive.

.PARAMETER BackupPath
    The path to the backup ZIP file (required for -Restore).

.PARAMETER RegisterTask
    Registers a Windows Scheduled Task to run snapshots automatically.

.PARAMETER UnregisterTask
    Removes the registered Windows Scheduled Task.

.PARAMETER TriggerType
    The scheduled task trigger type: 'Daily', 'AtLogon', or 'OnIdle'. Default: 'Daily'.

.PARAMETER Time
    The daily scheduled time (HH:mm format). Default: '22:00'.

.PARAMETER DryRun
    Simulates the ScanState or LoadState operation without writing changes.

.PARAMETER Interactive
    If set during restore, prompts for confirmation before starting the LoadState process.

.EXAMPLE
    # Show interactive menu
    .\migratron.ps1

.EXAMPLE
    # Run scan
    .\migratron.ps1 -Scan

.EXAMPLE
    # Run elevated backup
    .\migratron.ps1 -Backup

.EXAMPLE
    # Register daily snapshot task at 18:30
    .\migratron.ps1 -RegisterTask -TriggerType Daily -Time "18:30"
#>
[CmdletBinding()]
param(
    [switch]$Scan,
    [switch]$List,
    [switch]$Backup,
    [switch]$Restore,
    [string]$BackupPath,
    [switch]$RegisterTask,
    [switch]$UnregisterTask,
    [ValidateSet('Daily', 'AtLogon', 'OnIdle')]
    [string]$TriggerType = "Daily",
    [string]$Time = "22:00",
    [switch]$DryRun,
    [switch]$Interactive
)

$ErrorActionPreference = 'Stop'
$ScriptDir = Join-Path $PSScriptRoot "scripts"

# Load shared utilities
. (Join-Path $ScriptDir "utils.ps1")

# Route commands if switches are passed
$hasSwitch = $Scan -or $List -or $Backup -or $Restore -or $RegisterTask -or $UnregisterTask

if ($hasSwitch) {
    if ($Scan) {
        & (Join-Path $ScriptDir "scan-system.ps1")
    }
    
    if ($List) {
        & (Join-Path $ScriptDir "list-backups.ps1")
    }
    
    if ($Backup) {
        # Check and elevate to admin
        Assert-AdminPrivileges -CallerBoundParameters $PSBoundParameters
        
        $params = @{}
        if ($DryRun) { $params["DryRun"] = $true }
        & (Join-Path $ScriptDir "backup-profile.ps1") @params
    }
    
    if ($Restore) {
        if ([string]::IsNullOrEmpty($BackupPath)) {
            Log "Parameter -BackupPath is required when using -Restore." 'ERROR'
            return
        }
        # Check and elevate to admin
        Assert-AdminPrivileges -CallerBoundParameters $PSBoundParameters
        
        $params = @{ BackupPath = $BackupPath }
        if ($Interactive) { $params["Interactive"] = $true }
        if ($DryRun) { $params["DryRun"] = $true }
        
        & (Join-Path $ScriptDir "restore-profile.ps1") @params
    }
    
    if ($RegisterTask) {
        Assert-AdminPrivileges -CallerBoundParameters $PSBoundParameters
        & (Join-Path $ScriptDir "schedule-task.ps1") -Register -TriggerType $TriggerType -Time $Time
    }
    
    if ($UnregisterTask) {
        Assert-AdminPrivileges -CallerBoundParameters $PSBoundParameters
        & (Join-Path $ScriptDir "schedule-task.ps1") -Unregister
    }
}
else {
    # No switches: run interactive menu
    :MainMenu while ($true) {
        Clear-Host
        Write-Host "==================================================" -ForegroundColor Magenta
        Write-Host "                 M I G R A T R O N                " -ForegroundColor Magenta
        Write-Host "     Windows Settings Migration Toolkit (USMT)    " -ForegroundColor DarkGray
        Write-Host "==================================================" -ForegroundColor Magenta
        Write-Host ""
        Write-Host "  [1] Migration Operations (Backup & Restore)"
        Write-Host "  [2] Manage Backups (List & Delete)"
        Write-Host "  [3] Configuration & Automation"
        Write-Host "  ---" -ForegroundColor DarkGray
        Write-Host "  [Q] Quit"
        Write-Host ""
        
        $choice = Read-Host "Select an option [1-3, Q]"
        
        switch ($choice) {
            "1" {
                while ($true) {
                    Clear-Host
                    Write-Host "==================================================" -ForegroundColor Magenta
                    Write-Host "              Migration Operations                " -ForegroundColor Magenta
                    Write-Host "==================================================" -ForegroundColor Magenta
                    Write-Host ""
                    Write-Host "  [1] Backup Settings to ZIP Archive"
                    Write-Host "  [2] Restore Settings from ZIP Archive"
                    Write-Host "  [3] Back to Main Menu"
                    Write-Host "  ---" -ForegroundColor DarkGray
                    Write-Host "  [Q] Quit"
                    Write-Host ""
                    
                    $opChoice = Read-Host "Select an option [1-3, Q]"
                    if ($opChoice -match '^[qQ]$') { return }
                    elseif ($opChoice -eq "1") {
                        Write-Host ""
                        Assert-AdminPrivileges -CallerBoundParameters $PSBoundParameters
                        $dry = Read-Host "Dry run (simulate backup)? [y/N]"
                        $drySwitch = if ($dry -like "y*") { $true } else { $false }
                        $params = @{}
                        if ($drySwitch) { $params["DryRun"] = $true }
                        & (Join-Path $ScriptDir "backup-profile.ps1") @params
                        Read-Host "`nPress Enter to return to menu..."
                    }
                    elseif ($opChoice -eq "2") {
                        Write-Host ""
                        Assert-AdminPrivileges -CallerBoundParameters $PSBoundParameters
                        $path = Read-Host "Enter path to the backup ZIP file"
                        $path = $path.Trim("'", '"')
                        if ([string]::IsNullOrEmpty($path) -or -not (Test-Path $path)) {
                            Log "Backup file not found at: '$path'" 'ERROR'
                            Read-Host "`nPress Enter to return to menu..."
                            continue
                        }
                        $int = Read-Host "Interactive mode (confirm restore)? [y/N]"
                        $intSwitch = if ($int -like "y*") { $true } else { $false }
                        $dry = Read-Host "Dry run (simulate restore)? [y/N]"
                        $drySwitch = if ($dry -like "y*") { $true } else { $false }
                        $params = @{ BackupPath = $path }
                        if ($intSwitch) { $params["Interactive"] = $true }
                        if ($drySwitch) { $params["DryRun"] = $true }
                        & (Join-Path $ScriptDir "restore-profile.ps1") @params
                        Read-Host "`nPress Enter to return to menu..."
                    }
                    elseif ($opChoice -eq "3") { break }
                }
            }
            "2" {
                Write-Host ""
                & (Join-Path $ScriptDir "list-backups.ps1") -InteractiveDelete
            }
            "3" {
                while ($true) {
                    Clear-Host
                    Write-Host "==================================================" -ForegroundColor Magenta
                    Write-Host "           Configuration & Automation             " -ForegroundColor Magenta
                    Write-Host "==================================================" -ForegroundColor Magenta
                    Write-Host ""
                    Write-Host "  [1] Scan and Audit Local Settings"
                    Write-Host "  [2] Manage Scheduled Task"
                    Write-Host "  [3] Edit Backup Settings (Retention & Encryption)"
                    Write-Host "  [4] Back to Main Menu"
                    Write-Host "  ---" -ForegroundColor DarkGray
                    Write-Host "  [Q] Quit"
                    Write-Host ""
                    
                    $cfgChoice = Read-Host "Select an option [1-4, Q]"
                    if ($cfgChoice -match '^[qQ]$') { return }
                    elseif ($cfgChoice -eq "1") {
                        Write-Host ""
                        & (Join-Path $ScriptDir "scan-system.ps1")
                        Read-Host "`nPress Enter to return to menu..."
                    }
                    elseif ($cfgChoice -eq "2") {
                        Write-Host ""
                        Assert-AdminPrivileges -CallerBoundParameters $PSBoundParameters
                        Write-Host "Manage Scheduled Task:" -ForegroundColor Magenta
                        Write-Host "  [1] Register Daily Backup Task"
                        Write-Host "  [2] Remove Scheduled Task"
                        Write-Host "  [3] Back to Configuration Menu"
                        Write-Host "  [4] Back to Main Menu"
                        Write-Host "  ---" -ForegroundColor DarkGray
                        Write-Host "  [Q] Quit"
                        $taskChoice = Read-Host "Select an option [1-4, Q]"
                        if ($taskChoice -match '^[qQ]$') { return }
                        elseif ($taskChoice -eq "1") {
                            $timeVal = Read-Host "Enter daily backup time (e.g. 22:00)"
                            if ([string]::IsNullOrEmpty($timeVal) -or $timeVal -notmatch '^\d{2}:\d{2}$') {
                                Log "Invalid time format. Using default 22:00." 'WARN'
                                $timeVal = '22:00'
                            }
                            $trigger = Read-Host "Select trigger type (Daily / AtLogon / OnIdle)"
                            $allowedTriggers = @('Daily', 'AtLogon', 'OnIdle')
                            if ($allowedTriggers -notcontains $trigger) {
                                Log "Invalid trigger type '$trigger'. Using default 'Daily'." 'WARN'
                                $trigger = 'Daily'
                            }
                            $params = @{ Register = $true; Time = $timeVal; TriggerType = $trigger }
                            & (Join-Path $ScriptDir "schedule-task.ps1") @params
                            Read-Host "`nPress Enter to return to menu..."
                        } elseif ($taskChoice -eq "2") {
                            & (Join-Path $ScriptDir "schedule-task.ps1") -Unregister
                            Read-Host "`nPress Enter to return to menu..."
                        } elseif ($taskChoice -eq "4") {
                            continue MainMenu
                        }
                    }
                    elseif ($cfgChoice -eq "3") {
                        while ($true) {
                            $mergedCfg = Get-UsmtConfig
                            $localCfg = Get-LocalConfig
                            
                            $retMode = $mergedCfg.backup.retentionMode
                            $enc = $mergedCfg.backup.encrypt
                            $encEncoded = if ($null -ne $localCfg.backup.encryptionKeyEncoded) { $localCfg.backup.encryptionKeyEncoded } else { $false }
                            $hasKey = if (-not [string]::IsNullOrEmpty($localCfg.backup.encryptionKey)) { "Yes" } else { "No" }
                            
                            $simpleCount = $mergedCfg.backup.retentionCount
                            $gfsD = $mergedCfg.backup.gfsRetention.dailies
                            $gfsW = $mergedCfg.backup.gfsRetention.weeklies
                            $gfsM = $mergedCfg.backup.gfsRetention.monthlies
                            
                            Clear-Host
                            Write-Host "==================================================" -ForegroundColor Magenta
                            Write-Host "               Backup Settings                    " -ForegroundColor Magenta
                            Write-Host "==================================================" -ForegroundColor Magenta
                            Write-Host ""
                            Write-Host "  [1] Toggle Retention Mode (Current: $retMode)"
                            if ($retMode -eq 'simple') {
                                Write-Host "  [2] Set Simple Retention Count (Current: $simpleCount)"
                            } else {
                                Write-Host "  [2] Set GFS Retention Count (D: $gfsD, W: $gfsW, M: $gfsM)"
                            }
                            Write-Host "  [3] Toggle Encryption (Current: $enc)"
                            
                            $keyOpt = -1
                            $encOpt = -1
                            $testOpt = -1
                            $backOpt = 4
                            
                            if ($enc -eq $true) {
                                $keyOpt = 4
                                $encOpt = 5
                                $backOpt = 6
                                Write-Host "  [$keyOpt] Set Encryption Key (Key Set: $hasKey)"
                                Write-Host "  [$encOpt] Toggle DPAPI Key Encoding (Current: $encEncoded)"
                                
                                if ($hasKey -eq "Yes") {
                                    $testOpt = 6
                                    $backOpt = 7
                                    Write-Host "  [$testOpt] Verify Current Encryption Key"
                                }
                            }
                            
                            $mainOpt = $backOpt + 1
                            Write-Host "  [$backOpt] Back to Configuration Menu"
                            Write-Host "  [$mainOpt] Back to Main Menu"
                            Write-Host "  ---" -ForegroundColor DarkGray
                            Write-Host "  [Q] Quit"
                            Write-Host ""
                            
                            $editChoice = Read-Host "Select an option [1-$mainOpt, Q]"
                            if ($editChoice -match '^[qQ]$') { return }
                            elseif ($editChoice -eq "1") {
                                $newMode = Read-Host "Enter retention mode (simple/gfs, or leave empty to clear override)"
                                if ([string]::IsNullOrWhiteSpace($newMode)) {
                                    $localCfg.backup.psobject.Properties.Remove("retentionMode")
                                } else {
                                    $localCfg.backup | Add-Member -MemberType NoteProperty -Name "retentionMode" -Value $newMode -Force
                                }
                                Set-LocalConfig -ConfigObject $localCfg
                                
                                $tempCfg = Get-UsmtConfig
                                if ($tempCfg.backup.retentionMode -eq 'simple') {
                                    $retLimit = $tempCfg.backup.retentionCount
                                    $outDir = Resolve-PathVariables -Path $tempCfg.backup.outputDir
                                    if (Test-Path $outDir) {
                                        $backupsCount = @(Get-ChildItem -Path $outDir -Filter "migratron-store-*" | 
                                            Where-Object { $_.Name -match '^migratron-store-\d{8}-\d{6}(\.zip)?$' }).Count
                                        if ($retLimit -gt 0 -and $backupsCount -gt $retLimit) {
                                            $diff = $backupsCount - $retLimit + 1
                                            Write-Host ""
                                            Write-Host "WARNING: You currently have $backupsCount backups." -ForegroundColor Yellow
                                            Write-Host "With a simple limit of $retLimit, the next backup will PERMANENTLY DELETE your $diff oldest snapshot(s)!" -ForegroundColor Red
                                            Read-Host "`nPress Enter to acknowledge..."
                                        }
                                    }
                                }
                            }
                            elseif ($editChoice -eq "2") {
                                if ($retMode -eq 'simple') {
                                    $val = Read-Host "Enter simple retention count (number, or empty to clear)"
                                    if ([string]::IsNullOrWhiteSpace($val)) {
                                        $localCfg.backup.psobject.Properties.Remove("retentionCount")
                                    } elseif ($val -match '^\d+$') {
                                        $localCfg.backup | Add-Member -MemberType NoteProperty -Name "retentionCount" -Value [int]$val -Force
                                    }
                                    Set-LocalConfig -ConfigObject $localCfg
                                    
                                    $tempCfg = Get-UsmtConfig
                                    $retLimit = $tempCfg.backup.retentionCount
                                    $outDir = Resolve-PathVariables -Path $tempCfg.backup.outputDir
                                    if (Test-Path $outDir) {
                                        $backupsCount = @(Get-ChildItem -Path $outDir -Filter "migratron-store-*" | 
                                            Where-Object { $_.Name -match '^migratron-store-\d{8}-\d{6}(\.zip)?$' }).Count
                                        if ($retLimit -gt 0 -and $backupsCount -gt $retLimit) {
                                            $diff = $backupsCount - $retLimit + 1
                                            Write-Host ""
                                            Write-Host "WARNING: You currently have $backupsCount backups." -ForegroundColor Yellow
                                            Write-Host "With a simple limit of $retLimit, the next backup will PERMANENTLY DELETE your $diff oldest snapshot(s)!" -ForegroundColor Red
                                            Read-Host "`nPress Enter to acknowledge..."
                                        }
                                    }
                                } else {
                                    Write-Host "Leave any value empty to skip/clear:" -ForegroundColor DarkGray
                                    $dVal = Read-Host "Enter Dailies count"
                                    $wVal = Read-Host "Enter Weeklies count"
                                    $mVal = Read-Host "Enter Monthlies count"
                                    
                                    if (-not $localCfg.backup.psobject.Properties.Match('gfsRetention')) {
                                        $localCfg.backup | Add-Member -MemberType NoteProperty -Name "gfsRetention" -Value (New-Object PSObject) -Force
                                    }
                                    
                                    if ([string]::IsNullOrWhiteSpace($dVal)) { $localCfg.backup.gfsRetention.psobject.Properties.Remove("dailies") }
                                    elseif ($dVal -match '^\d+$') { $localCfg.backup.gfsRetention | Add-Member -MemberType NoteProperty -Name "dailies" -Value [int]$dVal -Force }
                                    
                                    if ([string]::IsNullOrWhiteSpace($wVal)) { $localCfg.backup.gfsRetention.psobject.Properties.Remove("weeklies") }
                                    elseif ($wVal -match '^\d+$') { $localCfg.backup.gfsRetention | Add-Member -MemberType NoteProperty -Name "weeklies" -Value [int]$wVal -Force }
                                    
                                    if ([string]::IsNullOrWhiteSpace($mVal)) { $localCfg.backup.gfsRetention.psobject.Properties.Remove("monthlies") }
                                    elseif ($mVal -match '^\d+$') { $localCfg.backup.gfsRetention | Add-Member -MemberType NoteProperty -Name "monthlies" -Value [int]$mVal -Force }
                                    
                                    Set-LocalConfig -ConfigObject $localCfg
                                    
                                    $tempCfg = Get-UsmtConfig
                                    $outDir = Resolve-PathVariables -Path $tempCfg.backup.outputDir
                                    if (Test-Path $outDir) {
                                        $backupsCount = @(Get-ChildItem -Path $outDir -Filter "migratron-store-*" | 
                                            Where-Object { $_.Name -match '^migratron-store-\d{8}-\d{6}(\.zip)?$' }).Count
                                        if ($backupsCount -gt 0) {
                                            Write-Host ""
                                            Write-Host "WARNING: You currently have $backupsCount backups." -ForegroundColor Yellow
                                            Write-Host "Lowering GFS limits may permanently delete older tiered snapshots on the next run!" -ForegroundColor Red
                                            Read-Host "`nPress Enter to acknowledge..."
                                        }
                                    }
                                }
                            }
                            elseif ($editChoice -eq "3") {
                                $val = -not $enc
                                if ($val -and $hasKey -ne "Yes") {
                                        Write-Host ""
                                        Write-Host "Select key encoding format:" -ForegroundColor Cyan
                                        Write-Host "  [1] Plaintext"
                                        Write-Host "  [2] DPAPI Encoded (Recommended)"
                                        $encChoiceStr = Read-Host "Select an option [1-2, default 2]"
                                        $newEncEncoded = if ($encChoiceStr -eq "1") { $false } else { $true }
                                        $localCfg.backup | Add-Member -MemberType NoteProperty -Name "encryptionKeyEncoded" -Value $newEncEncoded -Force
                                        
                                        while ($true) {
                                            $newKey = Read-Host -AsSecureString "Enter encryption key to enable (leave empty to cancel)"
                                            $plainKey = [System.Runtime.InteropServices.Marshal]::PtrToStringAuto([System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($newKey))
                                            
                                            if ([string]::IsNullOrWhiteSpace($plainKey)) {
                                                Write-Host "No key provided. Encryption will remain disabled." -ForegroundColor Yellow
                                                $val = $false
                                                $localCfg.backup.psobject.Properties.Remove("encryptionKeyEncoded")
                                                Start-Sleep -Seconds 2
                                                break
                                            } else {
                                                $confirmKey = Read-Host -AsSecureString "Confirm encryption key"
                                                $plainConfirm = [System.Runtime.InteropServices.Marshal]::PtrToStringAuto([System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($confirmKey))
                                                if ($plainKey -cne $plainConfirm) {
                                                    Write-Host "Keys do not match. Please try again." -ForegroundColor Red
                                                    Write-Host ""
                                                    continue
                                                }
                                                
                                                if ($newEncEncoded) {
                                                    $encodedString = ConvertFrom-SecureString $newKey
                                                    $localCfg.backup | Add-Member -MemberType NoteProperty -Name "encryptionKey" -Value $encodedString -Force
                                                } else {
                                                    $localCfg.backup | Add-Member -MemberType NoteProperty -Name "encryptionKey" -Value $plainKey -Force
                                                }
                                                Write-Host "Encryption key set successfully." -ForegroundColor Green
                                                Start-Sleep -Seconds 1
                                                break
                                            }
                                        }
                                    }
                                    $localCfg.backup | Add-Member -MemberType NoteProperty -Name "encrypt" -Value $val -Force
                                Set-LocalConfig -ConfigObject $localCfg
                            }
                            elseif ($keyOpt -ne -1 -and $editChoice -eq "$keyOpt") {
                                while ($true) {
                                    $newKey = Read-Host -AsSecureString "Enter new encryption key (leave empty to clear/cancel)"
                                    $plainKey = [System.Runtime.InteropServices.Marshal]::PtrToStringAuto([System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($newKey))
                                    if ([string]::IsNullOrWhiteSpace($plainKey)) {
                                        $localCfg.backup.psobject.Properties.Remove("encryptionKey")
                                        $localCfg.backup.psobject.Properties.Remove("encryptionKeyEncoded")
                                        $localCfg.backup | Add-Member -MemberType NoteProperty -Name "encrypt" -Value $false -Force
                                        Set-LocalConfig -ConfigObject $localCfg
                                        Write-Host "Encryption key cleared and encryption disabled." -ForegroundColor Yellow
                                        Start-Sleep -Seconds 1
                                        break
                                    } else {
                                        $confirmKey = Read-Host -AsSecureString "Confirm new encryption key"
                                        $plainConfirm = [System.Runtime.InteropServices.Marshal]::PtrToStringAuto([System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($confirmKey))
                                        if ($plainKey -cne $plainConfirm) {
                                            Write-Host "Keys do not match. Please try again." -ForegroundColor Red
                                            Write-Host ""
                                            continue
                                        }
                                        
                                        if ($encEncoded) {
                                            $encodedString = ConvertFrom-SecureString $newKey
                                            $localCfg.backup | Add-Member -MemberType NoteProperty -Name "encryptionKey" -Value $encodedString -Force
                                        } else {
                                            $localCfg.backup | Add-Member -MemberType NoteProperty -Name "encryptionKey" -Value $plainKey -Force
                                        }
                                        Set-LocalConfig -ConfigObject $localCfg
                                        Write-Host "Encryption key updated successfully." -ForegroundColor Green
                                        Start-Sleep -Seconds 1
                                        break
                                    }
                                }
                            }
                            elseif ($encOpt -ne -1 -and $editChoice -eq "$encOpt") {
                                $newEncEncoded = -not $encEncoded
                                
                                Write-Host ""
                                Write-Host "Changing key encoding requires re-entering your encryption key." -ForegroundColor Yellow
                                
                                while ($true) {
                                    $newKey = Read-Host -AsSecureString "Enter encryption key (leave empty to cancel)"
                                    $plainKey = [System.Runtime.InteropServices.Marshal]::PtrToStringAuto([System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($newKey))
                                    
                                    if ([string]::IsNullOrWhiteSpace($plainKey)) {
                                        Write-Host "Action cancelled. Encoding unchanged." -ForegroundColor DarkGray
                                        Start-Sleep -Seconds 1
                                        break
                                    } else {
                                        $confirmKey = Read-Host -AsSecureString "Confirm encryption key"
                                        $plainConfirm = [System.Runtime.InteropServices.Marshal]::PtrToStringAuto([System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($confirmKey))
                                        if ($plainKey -cne $plainConfirm) {
                                            Write-Host "Keys do not match. Please try again." -ForegroundColor Red
                                            Write-Host ""
                                            continue
                                        }
                                        
                                        $localCfg.backup | Add-Member -MemberType NoteProperty -Name "encryptionKeyEncoded" -Value $newEncEncoded -Force
                                        if ($newEncEncoded) {
                                            $encodedString = ConvertFrom-SecureString $newKey
                                            $localCfg.backup | Add-Member -MemberType NoteProperty -Name "encryptionKey" -Value $encodedString -Force
                                        } else {
                                            $localCfg.backup | Add-Member -MemberType NoteProperty -Name "encryptionKey" -Value $plainKey -Force
                                        }
                                        Set-LocalConfig -ConfigObject $localCfg
                                        Write-Host "Encoding toggled and key updated successfully." -ForegroundColor Green
                                        Start-Sleep -Seconds 1
                                        break
                                    }
                                }
                            }
                            elseif ($testOpt -ne -1 -and $editChoice -eq "$testOpt") {
                                Write-Host ""
                                $testKey = Read-Host -AsSecureString "Enter current encryption key to verify"
                                $plainTest = [System.Runtime.InteropServices.Marshal]::PtrToStringAuto([System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($testKey))
                                
                                $storedKey = $localCfg.backup.encryptionKey
                                if ($encEncoded) {
                                    try {
                                        $secureStored = ConvertTo-SecureString $storedKey
                                        $plainStored = [System.Runtime.InteropServices.Marshal]::PtrToStringAuto([System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($secureStored))
                                    } catch {
                                        $plainStored = $null
                                    }
                                } else {
                                    $plainStored = $storedKey
                                }
                                
                                Write-Host ""
                                if (-not [string]::IsNullOrEmpty($plainTest) -and $plainTest -ceq $plainStored) {
                                    Write-Host "Success: The encryption key matches the stored value." -ForegroundColor Green
                                } else {
                                    Write-Host "Error: The encryption key DOES NOT match the stored value." -ForegroundColor Red
                                }
                                Read-Host "`nPress Enter to continue..."
                            }
                            elseif ($editChoice -eq "$backOpt") { break }
                            elseif ($editChoice -eq "$mainOpt") { continue MainMenu }
                        }
                    }
                    elseif ($cfgChoice -eq "4") { break }
                }
            }
            { $_ -match '^[qQ]$' } {
                Write-Host "`nGoodbye!" -ForegroundColor Cyan
                return
            }
            default {
                Log "Invalid choice. Please enter a valid option." 'WARN'
                Start-Sleep -Seconds 1
            }
        }
    }
}
