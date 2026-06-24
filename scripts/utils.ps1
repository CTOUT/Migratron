# Migratron Utilities Module
# Contains shared functions for logging, path resolution, USMT discovery, and admin checks.

$ErrorActionPreference = 'Stop'

#region Logging
function Log {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Message,
        [ValidateSet('INFO', 'WARN', 'ERROR', 'SUCCESS', 'DEBUG')]
        [string]$Level = 'INFO'
    )
    $ts = (Get-Date).ToString('yyyy-MM-dd HH:mm:ss')
    $icon = switch ($Level) {
        'ERROR' { '[X]' }
        'WARN' { '[!]' }
        'SUCCESS' { '[√]' }
        'DEBUG' { '[-]' }
        default { '[i]' }
    }
    $color = switch ($Level) {
        'ERROR' { 'Red' }
        'WARN' { 'Yellow' }
        'SUCCESS' { 'Green' }
        'DEBUG' { 'DarkGray' }
        default { 'Cyan' }
    }
    Write-Host "[$ts] $icon $Message" -ForegroundColor $color
}

function Step {
    param([string]$Label)
    Write-Host ""
    Write-Host "  ── $Label ──" -ForegroundColor Magenta
    Write-Host ""
}
#endregion

#region UX Helpers
function Show-MenuHeader {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Title,
        [string]$Subtitle = ""
    )
    Clear-Host
    Write-Host "==================================================" -ForegroundColor Magenta
    
    $padLeft = [math]::Max(0, [math]::Floor((50 - $Title.Length) / 2))
    $padRight = [math]::Max(0, 50 - $Title.Length - $padLeft)
    $centeredTitle = (" " * $padLeft) + $Title + (" " * $padRight)
    Write-Host $centeredTitle -ForegroundColor Magenta
    
    if (-not [string]::IsNullOrEmpty($Subtitle)) {
        $padLeftSub = [math]::Max(0, [math]::Floor((50 - $Subtitle.Length) / 2))
        $padRightSub = [math]::Max(0, 50 - $Subtitle.Length - $padLeftSub)
        $centeredSubtitle = (" " * $padLeftSub) + $Subtitle + (" " * $padRightSub)
        Write-Host $centeredSubtitle -ForegroundColor DarkGray
    }
    
    Write-Host "==================================================" -ForegroundColor Magenta
    Write-Host ""
}
#endregion

#region Security Helpers
function Convert-SecureStringToPlaintext {
    param(
        [Parameter(Mandatory = $true)]
        [System.Security.SecureString]$SecureString
    )
    $bstr = [System.IntPtr]::Zero
    try {
        $bstr = [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($SecureString)
        return [System.Runtime.InteropServices.Marshal]::PtrToStringAuto($bstr)
    } finally {
        if ($bstr -ne [System.IntPtr]::Zero) {
            [System.Runtime.InteropServices.Marshal]::ZeroFreeBSTR($bstr)
        }
    }
}

function Read-ConfirmedSecureString {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Prompt,
        [string]$ConfirmPrompt = "Confirm encryption key"
    )
    while ($true) {
        $newKey = Read-Host -AsSecureString "$Prompt"
        $plainKey = Convert-SecureStringToPlaintext -SecureString $newKey
        
        if ([string]::IsNullOrWhiteSpace($plainKey)) {
            return $null
        } else {
            $confirmKey = Read-Host -AsSecureString "$ConfirmPrompt"
            $plainConfirm = Convert-SecureStringToPlaintext -SecureString $confirmKey
            if ($plainKey -cne $plainConfirm) {
                Write-Host "[X] Error: Keys do not match. Please try again." -ForegroundColor Red
                Write-Host ""
                continue
            }
            return $newKey
        }
    }
}
#endregion

#region Path Resolution
function Resolve-PathVariables {
    param([string]$Path)
    if ([string]::IsNullOrEmpty($Path)) { return $Path }
    
    $resolved = $Path
    
    # Resolve active OneDrive path
    $oneDrive = $env:OneDrive
    if ([string]::IsNullOrEmpty($oneDrive)) { $oneDrive = $env:OneDriveConsumer }
    if ([string]::IsNullOrEmpty($oneDrive)) { $oneDrive = $env:OneDriveCommercial }
    if ([string]::IsNullOrEmpty($oneDrive)) { $oneDrive = Join-Path $env:USERPROFILE "OneDrive" }
    
    $resolved = $resolved -replace '\$ONEDRIVE', $oneDrive
    $resolved = $resolved -replace '\$HOME', $env:USERPROFILE
    $resolved = $resolved -replace '\$APPDATA', $env:APPDATA
    $resolved = $resolved -replace '\$LOCALAPPDATA', $env:LOCALAPPDATA
    $resolved = $resolved -replace '\$USERPROFILE', $env:USERPROFILE
    
    # Expand any standard Windows environment variables in the form %VAR%
    $resolved = [System.Environment]::ExpandEnvironmentVariables($resolved)
    return $resolved
}

function Convert-ToUsmtPath {
    param([string]$ResolvedPath)
    if ([string]::IsNullOrEmpty($ResolvedPath)) { return $ResolvedPath }
    
    # Translate absolute paths into USMT CSIDL variables.
    # USMT ignores absolute paths pointing inside a user profile, so they must be translated.
    $usmtPath = $ResolvedPath -ireplace [regex]::Escape($env:LOCALAPPDATA), '%CSIDL_LOCAL_APPDATA%'
    $usmtPath = $usmtPath -ireplace [regex]::Escape($env:APPDATA), '%CSIDL_APPDATA%'
    $usmtPath = $usmtPath -ireplace [regex]::Escape($env:USERPROFILE), '%CSIDL_PROFILE%'
    $usmtPath = $usmtPath -ireplace [regex]::Escape($env:windir), '%CSIDL_WINDOWS%'
    if ($null -ne ${env:ProgramFiles(x86)}) {
        $usmtPath = $usmtPath -ireplace [regex]::Escape(${env:ProgramFiles(x86)}), '%CSIDL_PROGRAM_FILESX86%'
    }
    $usmtPath = $usmtPath -ireplace [regex]::Escape($env:ProgramFiles), '%CSIDL_PROGRAM_FILES%'
    if ($null -ne $env:ProgramData) {
        $usmtPath = $usmtPath -ireplace [regex]::Escape($env:ProgramData), '%CSIDL_COMMON_APPDATA%'
    }
    
    return $usmtPath
}
#endregion

#region Manifest/Config Management
function Get-UsmtConfig {
    param(
        [string]$ConfigPath = (Join-Path $PSScriptRoot "usmt-config.json")
    )
    if (-not (Test-Path $ConfigPath)) {
        throw "Configuration file not found at: $ConfigPath"
    }
    try {
        $json = Get-Content $ConfigPath -Raw | ConvertFrom-Json
        
        # Check for local overrides file (usmt-config.local.json)
        $localPath = Join-Path (Split-Path $ConfigPath) "usmt-config.local.json"
        if (Test-Path $localPath) {
            $localJson = Get-Content $localPath -Raw | ConvertFrom-Json
            if ($null -ne $localJson) {
                # Merge local properties into the main config object
                foreach ($section in $localJson.psobject.Properties.Name) {
                    if ($null -eq $json.$section) {
                        $json | Add-Member -MemberType NoteProperty -Name $section -Value $localJson.$section
                    }
                    else {
                        foreach ($prop in $localJson.$section.psobject.Properties.Name) {
                            if ($null -eq $json.$section.$prop) {
                                $json.$section | Add-Member -MemberType NoteProperty -Name $prop -Value $localJson.$section.$prop
                            }
                            else {
                                if ($json.$section.$prop -is [array] -and $localJson.$section.$prop -is [array]) {
                                    # Merge array properties instead of overwriting
                                    $json.$section.$prop = @($json.$section.$prop) + @($localJson.$section.$prop)
                                }
                                else {
                                    $json.$section.$prop = $localJson.$section.$prop
                                }
                            }
                        }
                    }
                }
            }
        }
        
        # DPAPI Decryption for Encoded Keys
        if ($null -ne $json.backup.encryptionKeyEncoded -and $json.backup.encryptionKeyEncoded -eq $true -and -not [string]::IsNullOrEmpty($json.backup.encryptionKey)) {
            try {
                $secureStr = ConvertTo-SecureString $json.backup.encryptionKey
                $plainText = Convert-SecureStringToPlaintext -SecureString $secureStr
                $json.backup.encryptionKey = $plainText
            }
            catch {
                Log "Failed to decrypt DPAPI encryptionKey. Ensure the key was encoded on this machine by this user." 'ERROR'
                $json.backup.encryptionKey = ""
            }
        }
        
        return $json
    }
    catch {
        Log "Failed to parse JSON config: $_" 'ERROR'
        return $null
    }
}

function Get-LocalConfig {
    param([string]$ConfigPath = (Join-Path $PSScriptRoot "usmt-config.local.json"))
    if (Test-Path $ConfigPath) {
        return (Get-Content $ConfigPath -Raw | ConvertFrom-Json)
    }
    
    # Return empty structured PSCustomObject if file doesn't exist
    $obj = New-Object PSObject
    $obj | Add-Member -MemberType NoteProperty -Name "backup" -Value (New-Object PSObject)
    $obj | Add-Member -MemberType NoteProperty -Name "usmt" -Value (New-Object PSObject)
    return $obj
}

function Set-LocalConfig {
    param(
        [Parameter(Mandatory=$true)]$ConfigObject, 
        [string]$ConfigPath = (Join-Path $PSScriptRoot "usmt-config.local.json")
    )
    # ConvertTo-Json truncates without Depth. 10 is safe for usmt-config.
    $jsonString = $ConfigObject | ConvertTo-Json -Depth 10
    
    # Use UTF8NoBOM
    $utf8NoBom = New-Object System.Text.UTF8Encoding $false
    [System.IO.File]::WriteAllText($ConfigPath, $jsonString, $utf8NoBom)
}
#endregion

#region Admin and USMT Helpers
function Test-IsAdmin {
    $identity = [System.Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object System.Security.Principal.WindowsPrincipal($identity)
    return $principal.IsInRole([System.Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Assert-AdminPrivileges {
    # Accept the caller's bound parameters so they can be safely forwarded on elevation.
    # Using a parameter avoids relying on $MyInvocation inside a dot-sourced module,
    # which would reflect the module's own (empty) parameter set instead of the caller's.
    param(
        [hashtable]$CallerBoundParameters = @{}
    )

    if (-not (Test-IsAdmin)) {
        Log "Migratron requires Administrator privileges to run USMT." 'WARN'
        Log "Please restart your PowerShell session as Administrator, or allow UAC elevation." 'INFO'

        # Resolve the script to re-launch (always the top-level migratron.ps1)
        $myPath = $MyInvocation.ScriptName
        if ([string]::IsNullOrEmpty($myPath)) {
            $myPath = Join-Path $PSScriptRoot "..\migratron.ps1"
        }
        $myPath = [System.IO.Path]::GetFullPath($myPath)

        # Build an argument array from the caller's bound parameters.
        # Each value is safely escaped to prevent metacharacter injection.
        $argsList = [System.Collections.Generic.List[string]]::new()
        foreach ($key in $CallerBoundParameters.Keys) {
            $val = $CallerBoundParameters[$key]
            if ($val -is [switch]) {
                if ($val.IsPresent) { $argsList.Add("-$key") }
            }
            else {
                # Escape single-quotes inside the value, then wrap in single quotes
                $escaped = ($val -as [string]) -replace "'", "''"
                $argsList.Add("-$key")
                $argsList.Add("'$escaped'")
            }
        }

        # Build the full ArgumentList array for Start-Process:
        # Each element is a separate token — no string-interpolation injection risk.
        $elevateArgs = [System.Collections.Generic.List[string]]::new()
        $elevateArgs.Add('-NoProfile')
        $elevateArgs.Add('-ExecutionPolicy')
        $elevateArgs.Add('RemoteSigned')
        $elevateArgs.Add('-File')
        $elevateArgs.Add($myPath)
        foreach ($a in $argsList) { $elevateArgs.Add($a) }

        # Re-elevate using the same PowerShell host that is currently running
        # (pwsh.exe for PS 7+, powershell.exe for Windows PowerShell 5.1)
        $psExe = if ($PSVersionTable.PSVersion.Major -ge 7) { 'pwsh.exe' } else { 'powershell.exe' }
        Log "Elevating process via $psExe..." 'INFO'
        Start-Process $psExe -ArgumentList $elevateArgs -Verb RunAs
        exit
    }
}

function Find-UsmtPath {
    # 1. Check usmt-config.json custom path
    try {
        $config = Get-UsmtConfig
        if ($config.usmt -and -not [string]::IsNullOrEmpty($config.usmt.customPath)) {
            $customPath = Resolve-PathVariables -Path $config.usmt.customPath
            if (Test-Path $customPath) {
                return $customPath
            }
        }
    }
    catch {}
    
    $arch = switch ($env:PROCESSOR_ARCHITECTURE.ToLower()) {
        'arm64' { 'arm64' }
        'x86'   { 'x86' }
        default { 'amd64' }
    }
    
    # 2. Check local repo folders (helps users run self-contained USMT)
    $localPaths = @(
        (Join-Path $PSScriptRoot "..\usmt\$arch"),
        (Join-Path $PSScriptRoot "..\usmt"),
        (Join-Path $PSScriptRoot "usmt\$arch"),
        (Join-Path $PSScriptRoot "usmt")
    )
    foreach ($path in $localPaths) {
        if (Test-Path $path) {
            $fullPath = [System.IO.Path]::GetFullPath($path)
            if (Test-Path (Join-Path $fullPath "scanstate.exe")) {
                return $fullPath
            }
        }
    }
    
    # 3. Check Windows ADK standard directories
    $adkBasePaths = @(
        "C:\Program Files (x86)\Windows Kits\10\Assessment and Deployment Kit\User State Migration Tool",
        "C:\Program Files\Windows Kits\10\Assessment and Deployment Kit\User State Migration Tool"
    )
    
    $adkPaths = @()
    foreach ($base in $adkBasePaths) {
        $adkPaths += Join-Path $base $arch
        if ($arch -ne 'amd64') { $adkPaths += Join-Path $base "amd64" } # Fallback to amd64 if native ARM64 is missing
        if ($arch -ne 'x86') { $adkPaths += Join-Path $base "x86" }
    }
    
    foreach ($path in $adkPaths) {
        if (Test-Path $path) {
            if (Test-Path (Join-Path $path "scanstate.exe")) {
                return $path
            }
        }
    }
    
    return $null
}

function Get-FormatSize {
    param([long]$Bytes)
    if ($Bytes -ge 1GB) {
        return "$([Math]::Round($Bytes / 1GB, 2)) GB"
    }
    elseif ($Bytes -ge 1MB) {
        return "$([Math]::Round($Bytes / 1MB, 2)) MB"
    }
    elseif ($Bytes -ge 1KB) {
        return "$([Math]::Round($Bytes / 1KB, 2)) KB"
    }
    else {
        return "$Bytes Bytes"
    }
}
#endregion

#region OneDrive Integration
function Wait-OneDriveSync {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [string]$Path,
        [int]$TimeoutMinutes = 30
    )

    if (-not (Test-Path $Path)) { return }

    $Shell = New-Object -ComObject Shell.Application
    $Folder = $Shell.NameSpace((Split-Path $Path))
    if ($null -eq $Folder) { return }
    $File = $Folder.ParseName((Split-Path $Path -Leaf))
    if ($null -eq $File) { return }

    # Dynamically find the index for "Availability status"
    $statusIndex = -1
    for ($i = 0; $i -lt 400; $i++) {
        $propName = $Folder.GetDetailsOf($null, $i)
        if ($propName -match "(?i)Availability status") {
            $testVal = $Folder.GetDetailsOf($File, $i)
            if (-not [string]::IsNullOrEmpty($testVal)) {
                $statusIndex = $i
                break
            }
        }
    }

    # Fallback to "Status" if Availability status fails
    if ($statusIndex -eq -1) {
        for ($i = 0; $i -lt 400; $i++) {
            $propName = $Folder.GetDetailsOf($null, $i)
            if ($propName -match "^Status$") {
                $testVal = $Folder.GetDetailsOf($File, $i)
                if (-not [string]::IsNullOrEmpty($testVal)) {
                    $statusIndex = $i
                    break
                }
            }
        }
    }

    if ($statusIndex -eq -1) {
        Log "Could not find OneDrive 'Availability status' property. Skipping sync verification." 'WARN'
        return
    }

    $timeout = [TimeSpan]::FromMinutes($TimeoutMinutes)
    $sw = [Diagnostics.Stopwatch]::StartNew()
    $synced = $false

    Log "Waiting for OneDrive to synchronize: $(Split-Path $Path -Leaf)..." 'INFO'

    while ($sw.Elapsed -lt $timeout) {
        $status = $Folder.GetDetailsOf($File, $statusIndex)
        
        if ([string]::IsNullOrEmpty($status)) {
            Log "File does not appear to be tracked by OneDrive (No status). Skipping wait." 'WARN'
            return
        }
        
        if ($status -notmatch "(?i)sync") {
            $synced = $true
            break
        }
        
        $percentComplete = [math]::Min(100, [math]::Floor(($sw.Elapsed.TotalSeconds / $timeout.TotalSeconds) * 100))
        Write-Progress -Activity "OneDrive Synchronization" -Status "Syncing: $(Split-Path $Path -Leaf) ($status)" -PercentComplete $percentComplete
        
        Start-Sleep -Seconds 10
    }

    $sw.Stop()
    Write-Progress -Activity "OneDrive Synchronization" -Completed
    
    if ($synced) {
        Log "OneDrive synchronization completed in $([math]::Round($sw.Elapsed.TotalSeconds, 1))s. (Status: $status)" 'SUCCESS'
    } else {
        Log "OneDrive synchronization timed out after $TimeoutMinutes minutes. (Status: $status)" 'WARN'
    }
}
#endregion

#region Interactive UX Helpers
function Get-BackupSelection {
    param([string]$ConfigPath)
    
    $config = Get-UsmtConfig -ConfigPath $ConfigPath
    if ($null -eq $config) { return $null }
    
    $outputDir = if (-not [string]::IsNullOrEmpty($config.backup.outputDir)) { $config.backup.outputDir } else { "MigratronBackups" }
    $outputDirResolved = Resolve-PathVariables -Path $outputDir
    
    if (-not [System.IO.Path]::IsPathRooted($outputDirResolved)) {
        $outputDirResolved = [System.IO.Path]::GetFullPath((Join-Path (Get-Location).Path $outputDirResolved))
    }
    
    if (-not (Test-Path $outputDirResolved)) {
        Log "Backup directory does not exist: $outputDirResolved" 'WARN'
        $choice = Read-Host "Enter manual path to backup archive (or press Enter to cancel)"
        if ([string]::IsNullOrWhiteSpace($choice)) { return $null }
        return $choice.Trim("'", '"')
    }
    
    $backups = @(Get-ChildItem -Path $outputDirResolved -Filter "migratron-store-*" | 
               Where-Object { $_.Name -match '^migratron-store-\d{8}-\d{6}(\.zip)?$' } | 
               Sort-Object LastWriteTime -Descending)
               
    if ($backups.Count -eq 0) {
        Log "No previous snapshots found in $outputDirResolved" 'INFO'
        $choice = Read-Host "Enter manual path to backup archive (or press Enter to cancel)"
        if ([string]::IsNullOrWhiteSpace($choice)) { return $null }
        return $choice.Trim("'", '"')
    }
    
    Log "Available Backups:" 'INFO'
    for ($i = 0; $i -lt $backups.Count; $i++) {
        $b = $backups[$i]
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
        Log "  [$($i + 1)] $($b.Name) (Size: $sizeStr, Modified: $($b.LastWriteTime))" 'INFO'
    }
    
    Write-Host ""
    $choice = Read-Host "Enter backup number [1-$($backups.Count)], or paste a manual path (Enter to cancel)"
    if ([string]::IsNullOrWhiteSpace($choice)) { return $null }
    
    if ($choice -match '^\d+$' -and [int]$choice -ge 1 -and [int]$choice -le $backups.Count) {
        return $backups[[int]$choice - 1].FullName
    }
    else {
        return $choice.Trim("'", '"')
    }
}
#endregion

function Write-UsmtKeyFile {
    param (
        [string]$Timestamp,
        [string]$EncryptionKey,
        [string]$AttemptSuffix = ""
    )
    $tempKeyFile = Join-Path $env:TEMP "migratron-key-$Timestamp$AttemptSuffix.txt"
    $utf8NoBom = New-Object System.Text.UTF8Encoding($false)
    [System.IO.File]::WriteAllText($tempKeyFile, $EncryptionKey, $utf8NoBom)
    return $tempKeyFile
}

function Remove-UsmtKeyFile {
    param (
        [string]$TempKeyFile
    )
    if ($null -ne $TempKeyFile -and (Test-Path $TempKeyFile)) {
        Log "Shredding temporary decryption key file..." 'DEBUG'
        Remove-Item -Path $TempKeyFile -Force -ErrorAction SilentlyContinue | Out-Null
    }
}

function Expand-SecureArchive {
    param (
        [string]$ArchivePath,
        [string]$StagingDir
    )
    Log "Extracting backup ZIP to staging: $StagingDir" 'DEBUG'
    New-Item -ItemType Directory -Path $StagingDir -Force | Out-Null
    Expand-Archive -Path $ArchivePath -DestinationPath $StagingDir -Force
    
    $canonicalStaging = [System.IO.Path]::GetFullPath($StagingDir).TrimEnd('\') + '\'
    $extractedItems = Get-ChildItem -Path $StagingDir -Recurse -Force
    foreach ($item in $extractedItems) {
        $canonicalItem = [System.IO.Path]::GetFullPath($item.FullName)
        if (-not $canonicalItem.StartsWith($canonicalStaging, [System.StringComparison]::OrdinalIgnoreCase)) {
            Log "Directory traversal detected in ZIP archive! Aborting. Offending entry: $($item.FullName)" 'ERROR'
            Remove-Item -Path $StagingDir -Recurse -Force -ErrorAction SilentlyContinue
            return $false
        }
    }
    return $true
}
