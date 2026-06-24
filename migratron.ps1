<#
.SYNOPSIS
    Migratron - Windows Settings Migration Toolkit (USMT Edition)

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
    while ($true) {
        Clear-Host
        Write-Host "==================================================" -ForegroundColor Magenta
        Write-Host "                 M I G R A T R O N                " -ForegroundColor Magenta
        Write-Host "     Windows Settings Migration Toolkit (USMT)    " -ForegroundColor DarkGray
        Write-Host "==================================================" -ForegroundColor Magenta
        Write-Host ""
        Write-Host "  [1] Migration Operations (Backup & Restore)"
        Write-Host "  [2] Manage Backups (List & Delete)"
        Write-Host "  [3] Configuration & Automation"
        Write-Host "  [4] Exit"
        Write-Host ""
        
        $choice = Read-Host "Select an option [1-4]"
        
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
                    Write-Host ""
                    
                    $opChoice = Read-Host "Select an option [1-3]"
                    if ($opChoice -eq "1") {
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
                    Write-Host ""
                    
                    $cfgChoice = Read-Host "Select an option [1-4]"
                    if ($cfgChoice -eq "1") {
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
                        Write-Host "  [3] Back to Menu"
                        $taskChoice = Read-Host "Select an option [1-3]"
                        if ($taskChoice -eq "1") {
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
                        } elseif ($taskChoice -eq "2") {
                            & (Join-Path $ScriptDir "schedule-task.ps1") -Unregister
                        }
                        Read-Host "`nPress Enter to return to menu..."
                    }
                    elseif ($cfgChoice -eq "3") {
                        while ($true) {
                            $localCfg = Get-LocalConfig
                            $retMode = if ($null -ne $localCfg.backup.retentionMode) { $localCfg.backup.retentionMode } else { "inherited" }
                            $enc = if ($null -ne $localCfg.backup.encrypt) { $localCfg.backup.encrypt } else { "inherited" }
                            $encEncoded = if ($null -ne $localCfg.backup.encryptionKeyEncoded) { $localCfg.backup.encryptionKeyEncoded } else { $false }
                            $hasKey = if (-not [string]::IsNullOrEmpty($localCfg.backup.encryptionKey)) { "Yes" } else { "No" }
                            
                            Clear-Host
                            Write-Host "==================================================" -ForegroundColor Magenta
                            Write-Host "               Backup Settings                    " -ForegroundColor Magenta
                            Write-Host "==================================================" -ForegroundColor Magenta
                            Write-Host ""
                            Write-Host "  [1] Toggle Retention Mode (Current: $retMode)"
                            Write-Host "  [2] Toggle Encryption (Current: $enc)"
                            Write-Host "  [3] Set Encryption Key (Key Set: $hasKey)"
                            Write-Host "  [4] Toggle DPAPI Key Encoding (Current: $encEncoded)"
                            Write-Host "  [5] Back to Menu"
                            Write-Host ""
                            
                            $editChoice = Read-Host "Select an option [1-5]"
                            if ($editChoice -eq "1") {
                                $newMode = Read-Host "Enter retention mode (simple/gfs, or leave empty to clear override)"
                                if ([string]::IsNullOrWhiteSpace($newMode)) {
                                    $localCfg.backup.psobject.Properties.Remove("retentionMode")
                                } else {
                                    $localCfg.backup | Add-Member -MemberType NoteProperty -Name "retentionMode" -Value $newMode -Force
                                }
                                Set-LocalConfig -ConfigObject $localCfg
                            }
                            elseif ($editChoice -eq "2") {
                                $newEnc = Read-Host "Enable encryption? (y/n, or empty to clear override)"
                                if ([string]::IsNullOrWhiteSpace($newEnc)) {
                                    $localCfg.backup.psobject.Properties.Remove("encrypt")
                                } else {
                                    $val = if ($newEnc -match '^y') { $true } else { $false }
                                    $localCfg.backup | Add-Member -MemberType NoteProperty -Name "encrypt" -Value $val -Force
                                }
                                Set-LocalConfig -ConfigObject $localCfg
                            }
                            elseif ($editChoice -eq "3") {
                                $newKey = Read-Host -AsSecureString "Enter new encryption key (leave empty to clear)"
                                $plainKey = [System.Runtime.InteropServices.Marshal]::PtrToStringAuto([System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($newKey))
                                if ([string]::IsNullOrWhiteSpace($plainKey)) {
                                    $localCfg.backup.psobject.Properties.Remove("encryptionKey")
                                    Set-LocalConfig -ConfigObject $localCfg
                                } else {
                                    if ($encEncoded) {
                                        $encodedString = ConvertFrom-SecureString $newKey
                                        $localCfg.backup | Add-Member -MemberType NoteProperty -Name "encryptionKey" -Value $encodedString -Force
                                    } else {
                                        $localCfg.backup | Add-Member -MemberType NoteProperty -Name "encryptionKey" -Value $plainKey -Force
                                    }
                                    Set-LocalConfig -ConfigObject $localCfg
                                    Write-Host "Encryption key updated successfully." -ForegroundColor Green
                                    Start-Sleep -Seconds 1
                                }
                            }
                            elseif ($editChoice -eq "4") {
                                $newEncEncoded = -not $encEncoded
                                
                                Write-Host ""
                                Write-Host "Changing key encoding requires re-entering your encryption key." -ForegroundColor Yellow
                                $newKey = Read-Host -AsSecureString "Enter encryption key (leave empty to cancel)"
                                $plainKey = [System.Runtime.InteropServices.Marshal]::PtrToStringAuto([System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($newKey))
                                
                                if ([string]::IsNullOrWhiteSpace($plainKey)) {
                                    Write-Host "Action cancelled. Encoding unchanged." -ForegroundColor DarkGray
                                    Start-Sleep -Seconds 1
                                } else {
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
                                }
                            }
                            elseif ($editChoice -eq "5") { break }
                        }
                    }
                    elseif ($cfgChoice -eq "4") { break }
                }
            }
            "4" {
                Write-Host "`nGoodbye!" -ForegroundColor Cyan
                return
            }
            default {
                Log "Invalid choice. Please enter a value between 1 and 4." 'WARN'
                Start-Sleep -Seconds 1
            }
        }
    }
}
