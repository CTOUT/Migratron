[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'

# Load shared utilities for config parsing and paths
. (Join-Path $PSScriptRoot "utils.ps1")

# Load WinForms
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

# ==============================================================================
# P/Invoke for Idle Time Tracking
# ==============================================================================
$signature = @"
using System;
using System.Runtime.InteropServices;

public class Win32 {
    [StructLayout(LayoutKind.Sequential)]
    public struct LASTINPUTINFO {
        public uint cbSize;
        public uint dwTime;
    }

    [DllImport("User32.dll")]
    public static extern bool GetLastInputInfo(ref LASTINPUTINFO plii);

    [DllImport("User32.dll", SetLastError = true)]
    public static extern bool ShutdownBlockReasonCreate(IntPtr hWnd, [MarshalAs(UnmanagedType.LPWStr)] string pwszReason);

    [DllImport("User32.dll", SetLastError = true)]
    public static extern bool ShutdownBlockReasonDestroy(IntPtr hWnd);

    [DllImport("ntdll.dll", PreserveSig = false)]
    public static extern void NtSuspendProcess(IntPtr processHandle);

    [DllImport("ntdll.dll", PreserveSig = false)]
    public static extern void NtResumeProcess(IntPtr processHandle);

    public static uint GetIdleTime() {
        LASTINPUTINFO lastInPut = new LASTINPUTINFO();
        lastInPut.cbSize = (uint)Marshal.SizeOf(lastInPut);
        if (GetLastInputInfo(ref lastInPut)) {
            return (uint)Environment.TickCount - lastInPut.dwTime;
        }
        return 0;
    }
}
"@
Add-Type -TypeDefinition $signature -Language CSharp -IgnoreWarnings

# ==============================================================================
# Agent State & Configuration
# ==============================================================================
$config = Get-UsmtConfig
$idleThresholdMs = $config.agent.idleMinutesThreshold * 60 * 1000
if ($idleThresholdMs -le 0) { $idleThresholdMs = 15 * 60 * 1000 } # default 15m

$Global:BackupProcess = $null
$Global:IsShuttingDown = $false
$Global:IsManualBackup = $false
$Global:LastUpdateCheck = (Get-Date)

# Find an icon (fallback to standard system info icon)
$icon = [System.Drawing.SystemIcons]::Information

# ==============================================================================
# Hidden Form (Message Pump)
# ==============================================================================
$form = New-Object System.Windows.Forms.Form
$form.ShowInTaskbar = $false
$form.WindowState = "Minimized"
$form.Opacity = 0
$form.Visible = $false
$form.FormBorderStyle = "FixedToolWindow"

# ==============================================================================
# System Tray Icon Setup
# ==============================================================================
$notifyIcon = New-Object System.Windows.Forms.NotifyIcon
$notifyIcon.Icon = $icon
$notifyIcon.Text = "Migratron Background Agent"
$notifyIcon.Visible = $config.agent.showTrayIcon

$contextMenu = New-Object System.Windows.Forms.ContextMenuStrip

$mainScriptPath = Join-Path $PSScriptRoot "..\migratron.ps1"
$appVersion = "Unknown"
if (Test-Path $mainScriptPath) {
    $migText = Get-Content $mainScriptPath -Raw
    if ($migText -match '(?m)^\s*Version:\s*(\d+\.\d+\.\d+)$') {
        $appVersion = "v" + $matches[1]
    }
}

$itemVersion = $contextMenu.Items.Add("Migratron $appVersion")
$itemVersion.Enabled = $false

$contextMenu.Items.Add("-") # Separator

$itemStatus = $contextMenu.Items.Add("Status: Idle")
$itemStatus.Enabled = $false

$itemLastBackup = $contextMenu.Items.Add("Last Backup: Checking...")
$itemLastBackup.Enabled = $false

$contextMenu.Items.Add("-") # Separator

$itemBackup = $contextMenu.Items.Add("Backup Now")
$itemBackup.Add_Click({
    Run-Backup -Manual $true
})

$contextMenu.Items.Add("-") # Separator

$itemUpdate = $contextMenu.Items.Add("Check for Updates")
$itemUpdate.Add_Click({
    Run-UpdateCheck -Manual $true
})

$contextMenu.Items.Add("-") # Separator

$itemExit = $contextMenu.Items.Add("Exit")
$itemExit.Add_Click({
    $notifyIcon.Visible = $false
    $form.Close()
})

$contextMenu.Add_Opening({
    # Update Status
    if ($Global:BackupProcess -and -not $Global:BackupProcess.HasExited) {
        if ($Global:IsSuspended) {
            $action = $config.agent.actionOnUserActivity
            if ($action -eq "Throttle") {
                $itemStatus.Text = "Status: Throttled (User Active)"
            } else {
                $itemStatus.Text = "Status: Paused (User Active)"
            }
        } else {
            $itemStatus.Text = "Status: Running Backup..."
        }
    } else {
        $itemStatus.Text = "Status: Idle"
    }

    # Update Last Backup Time
    $last = Get-LastBackupTime
    if ($last -eq [DateTime]::MinValue) {
        $itemLastBackup.Text = "Last Backup: Never"
    } else {
        $itemLastBackup.Text = "Last Backup: $($last.ToString('yyyy-MM-dd HH:mm'))"
    }
})

$notifyIcon.ContextMenuStrip = $contextMenu

# ==============================================================================
# Core Agent Logic
# ==============================================================================

function Get-LastBackupTime {
    $outDir = Resolve-PathVariables $config.backup.outputDir
    if (-not (Test-Path $outDir)) { return [DateTime]::MinValue }
    $latest = Get-ChildItem -Path $outDir -Filter "migratron-store-*" | Sort-Object CreationTime -Descending | Select-Object -First 1
    if ($latest) { return $latest.CreationTime }
    return [DateTime]::MinValue
}

function Run-UpdateCheck {
    param([bool]$Manual = $false)

    if ($Manual) { $notifyIcon.ShowBalloonTip(3000, "Migratron Updater", "Checking GitHub for updates...", [System.Windows.Forms.ToolTipIcon]::Info) }

    $updaterScript = Join-Path $PSScriptRoot "update-migratron.ps1"
    $psExe = if ($PSVersionTable.PSVersion.Major -ge 7) { 'pwsh.exe' } else { 'powershell.exe' }
    
    $proc = Start-Process $psExe -ArgumentList "-WindowStyle Hidden -NoProfile -ExecutionPolicy RemoteSigned -File `"$updaterScript`"" -PassThru -Wait -WindowStyle Hidden
    
    if ($proc.ExitCode -eq 1) {
        $notifyIcon.ShowBalloonTip(5000, "Migratron Updated!", "Successfully pulled the latest updates from GitHub. Restarting agent...", [System.Windows.Forms.ToolTipIcon]::Info)
        Start-Sleep -Seconds 2
        # Restart agent to pick up new code
        Start-Process $psExe -ArgumentList "-WindowStyle Hidden -NoProfile -ExecutionPolicy RemoteSigned -File `"$PSCommandPath`"" -WindowStyle Hidden
        $notifyIcon.Visible = $false
        $form.Close()
    } elseif ($proc.ExitCode -eq 0) {
        if ($Manual) { $notifyIcon.ShowBalloonTip(3000, "Migratron Updater", "Migratron is already up to date.", [System.Windows.Forms.ToolTipIcon]::Info) }
    } else {
        if ($Manual) { $notifyIcon.ShowBalloonTip(3000, "Migratron Updater", "Failed to update. You may have local uncommitted changes.", [System.Windows.Forms.ToolTipIcon]::Error) }
    }
}

function Run-Backup {
    param([bool]$Manual = $false)
    
    if ($Global:BackupProcess -and -not $Global:BackupProcess.HasExited) {
        if ($Manual) { $notifyIcon.ShowBalloonTip(3000, "Migratron", "A backup is already running.", [System.Windows.Forms.ToolTipIcon]::Info) }
        return
    }

    $notifyIcon.Text = "Migratron Agent (Running Backup...)"
    if ($Manual) {
        $notifyIcon.ShowBalloonTip(3000, "Migratron", "Starting manual snapshot...", [System.Windows.Forms.ToolTipIcon]::Info)
    }

    # Launch migratron.ps1 silently
    $scriptPath = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot "..\migratron.ps1"))
    $psExe = if ($PSVersionTable.PSVersion.Major -ge 7) { 'pwsh.exe' } else { 'powershell.exe' }
    
    $startInfo = New-Object System.Diagnostics.ProcessStartInfo
    $startInfo.FileName = $psExe
    $startInfo.Arguments = "-WindowStyle Hidden -NoProfile -ExecutionPolicy RemoteSigned -File `"$scriptPath`" -Backup"
    $startInfo.WindowStyle = [System.Diagnostics.ProcessWindowStyle]::Hidden
    $startInfo.CreateNoWindow = $true

    $Global:IsManualBackup = $Manual
    $Global:BackupProcess = [System.Diagnostics.Process]::Start($startInfo)
}

# ==============================================================================
# Background Polling Timer
# ==============================================================================
$Global:IsSuspended = $false

$timer = New-Object System.Windows.Forms.Timer
$timer.Interval = 60000 # Check every 60 seconds
$timer.Add_Tick({
    # Reset icon text if backup finished
    if ($Global:BackupProcess -and $Global:BackupProcess.HasExited) {
        $Global:BackupProcess = $null
        $Global:IsSuspended = $false
        $Global:IsManualBackup = $false
        $notifyIcon.Text = "Migratron Background Agent"
    }

    $idleTime = [Win32]::GetIdleTime()

    # If backup is currently running, check if user returned
    if ($Global:BackupProcess) {
        if ($Global:IsManualBackup) {
            # Manual backup completely bypasses idle suspension
            return
        }

        # Reload config in case it changed
        $config = Get-UsmtConfig -Force
        $action = $config.agent.actionOnUserActivity
        if ($null -eq $action) { $action = "Suspend" }

        if ($idleTime -lt 60000 -and -not $Global:IsSuspended) {
            # User is active
            if ($action -eq "Suspend") {
                try {
                    [Win32]::NtSuspendProcess($Global:BackupProcess.Handle)
                    $Global:IsSuspended = $true
                    $notifyIcon.Text = "Migratron Agent (Paused - User Active)"
                } catch {}
            } elseif ($action -eq "Throttle") {
                try {
                    $Global:BackupProcess.PriorityClass = [System.Diagnostics.ProcessPriorityClass]::Idle
                    $Global:IsSuspended = $true # Repurpose flag as IsThrottled
                    $notifyIcon.Text = "Migratron Agent (Throttled - User Active)"
                } catch {}
            }
        } elseif ($idleTime -ge $idleThresholdMs -and $Global:IsSuspended) {
            # User left again, resume or unthrottle
            if ($action -eq "Suspend") {
                try {
                    [Win32]::NtResumeProcess($Global:BackupProcess.Handle)
                    $Global:IsSuspended = $false
                    $notifyIcon.Text = "Migratron Agent (Running Backup...)"
                } catch {}
            } elseif ($action -eq "Throttle") {
                try {
                    $Global:BackupProcess.PriorityClass = [System.Diagnostics.ProcessPriorityClass]::Normal
                    $Global:IsSuspended = $false
                    $notifyIcon.Text = "Migratron Agent (Running Backup...)"
                } catch {}
            }
        }
        return
    }

    # Not running a backup yet. Check Idle Time to start one.
    if ($idleTime -ge $idleThresholdMs) {
        # We are idle. Have we backed up today?
        $lastBackup = Get-LastBackupTime
        if ($lastBackup.Date -lt (Get-Date).Date) {
            # It's a new day, and user is idle.
            Run-Backup
        }
    }

    # Daily Background Update Check
    if ($config.agent.autoUpdate -and ((Get-Date) -gt $Global:LastUpdateCheck.AddHours(24))) {
        $Global:LastUpdateCheck = (Get-Date)
        Run-UpdateCheck -Manual $false
    }
})

# ==============================================================================
# Shutdown Intercept Logic
# ==============================================================================
if ($config.agent.interceptShutdown) {
    $form.Add_FormClosing({
        param($sender, $e)
        if ($e.CloseReason -eq [System.Windows.Forms.CloseReason]::WindowsShutDown) {
            if (-not $Global:IsShuttingDown) {
                # First time we hear shutdown
                $lastBackup = Get-LastBackupTime
                
                # If we haven't backed up today, block shutdown to do it!
                if ($lastBackup.Date -lt (Get-Date).Date) {
                    $e.Cancel = $true
                    $Global:IsShuttingDown = $true
                    [Win32]::ShutdownBlockReasonCreate($form.Handle, "Migratron is saving a final snapshot before shutting down...")
                    
                    Run-Backup -Manual $true
                    
                    # We must wait synchronously in this UI thread for the backup to finish
                    # so Windows knows we are busy. We'll poll with Application.DoEvents.
                    while (-not $Global:BackupProcess.HasExited) {
                        Start-Sleep -Milliseconds 500
                        [System.Windows.Forms.Application]::DoEvents()
                    }
                    
                    # Done! Release the block and exit
                    [Win32]::ShutdownBlockReasonDestroy($form.Handle)
                    
                    # Tell Windows to shut down again, or just let our form close so the OS shutdown continues naturally
                    # Wait, if we canceled it, we must initiate a fast shutdown now that we are done.
                    Stop-Computer -Force
                }
            }
        }
    })
}

# ==============================================================================
# Start Message Loop
# ==============================================================================
$timer.Start()
[System.Windows.Forms.Application]::Run($form)

# Cleanup
$notifyIcon.Visible = $false
$notifyIcon.Dispose()
$form.Dispose()
