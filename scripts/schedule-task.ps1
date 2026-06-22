[CmdletBinding()]
param(
    [switch]$Register,
    [switch]$Unregister,
    [string]$TaskName = "MigratronSnapshot",
    [ValidateSet('Daily', 'AtLogon', 'OnIdle')]
    [string]$TriggerType = "Daily",
    [string]$Time = "22:00"
)

# Load shared utilities
. (Join-Path $PSScriptRoot "utils.ps1")

# Admin required to manage scheduled tasks
Assert-AdminPrivileges

$config = Get-UsmtConfig
if ([string]::IsNullOrEmpty($TaskName)) {
    $TaskName = $config.schedule.taskName
}

$taskPath = "\"

if ($Unregister) {
    Step "Unregistering Migratron Scheduled Task"
    
    if (Get-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue) {
        Unregister-ScheduledTask -TaskName $TaskName -Confirm:$false
        Log "Successfully removed scheduled task: $TaskName" 'SUCCESS'
    }
    else {
        Log "Scheduled task '$TaskName' does not exist." 'WARN'
    }
    return
}

if ($Register) {
    Step "Registering Migratron Scheduled Task"
    
    # 1. Define the action to run PowerShell script
    $scriptPath = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot "..\migratron.ps1"))
    $arguments  = "-NoProfile -ExecutionPolicy RemoteSigned -File `"$scriptPath`" -Backup -SkipSensitive"

    # Register the task using the same PowerShell host that is currently running
    # (pwsh.exe for PS 7+, powershell.exe for Windows PowerShell 5.1)
    $psExe = if ($PSVersionTable.PSVersion.Major -ge 7) { 'pwsh.exe' } else { 'powershell.exe' }

    $action = New-ScheduledTaskAction -Execute $psExe -Argument $arguments
    
    # 2. Define the trigger
    $trigger = switch ($TriggerType) {
        "Daily" {
            # Check time format (HH:mm)
            if ($Time -notmatch '^\d{2}:\d{2}$') {
                Log "Invalid time format '$Time'. Defaulting to 22:00." 'WARN'
                $Time = "22:00"
            }
            New-ScheduledTaskTrigger -Daily -At $Time
        }
        "AtLogon" {
            New-ScheduledTaskTrigger -AtLogOn
        }
        "OnIdle" {
            # In PowerShell triggers, OnIdle is configured via settings, but we initialize with logon first
            $t = New-ScheduledTaskTrigger -AtLogOn
            $t
        }
    }
    
    # 3. Define the principal (Run as current user, elevated)
    $currentUser = [System.Security.Principal.WindowsIdentity]::GetCurrent().Name
    $principal = New-ScheduledTaskPrincipal -UserId $currentUser -RunLevel Highest
    
    # 4. Define task settings
    $settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -StartWhenAvailable
    
    # If OnIdle is chosen, configure the idle trigger parameters in settings
    if ($TriggerType -eq "OnIdle") {
        # Configure idle duration and wait times
        $settings.IdleSettings.IdleDuration = New-TimeSpan -Minutes 10
        $settings.IdleSettings.WaitTimeout = New-TimeSpan -Hours 1
    }
    
    # Remove existing task first if it exists
    if (Get-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue) {
        Log "Removing existing scheduled task: $TaskName" 'DEBUG'
        Unregister-ScheduledTask -TaskName $TaskName -Confirm:$false
    }
    
    # Register the task
    try {
        Register-ScheduledTask -TaskName $TaskName -Action $action -Trigger $trigger -Principal $principal -Settings $settings | Out-Null
        Log "Successfully registered scheduled task!" 'SUCCESS'
        Log "Task Name: $TaskName" 'INFO'
        Log "Shell    : $psExe" 'INFO'
        $triggerStr = $TriggerType
        if ($TriggerType -eq "Daily") { $triggerStr = "$TriggerType at $Time" }
        Log "Trigger  : $triggerStr" 'INFO'
        Log "Run As   : $currentUser (Elevated)" 'INFO'
        Log "Action   : powershell.exe $arguments" 'INFO'
    }
    catch {
        Log "Failed to register scheduled task: $_" 'ERROR'
    }
}
else {
    Log "Please specify either -Register or -Unregister." 'WARN'
}
