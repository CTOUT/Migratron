[CmdletBinding()]
param(
    [string]$ConfigPath = (Join-Path $PSScriptRoot "usmt-config.json"),
    [switch]$DryRun
)

# Load shared utilities
. (Join-Path $PSScriptRoot "utils.ps1")

# USMT requires admin elevation
Assert-AdminPrivileges

Step "Migratron Backup (ScanState Snapshot)"

# 1. Load config and find USMT
$config = Get-UsmtConfig -ConfigPath $ConfigPath
$usmtPath = Find-UsmtPath

if ($null -eq $usmtPath) {
    Log "USMT not found! Cannot run ScanState. Run Scan first to see install options." 'ERROR'
    return
}

# --- FIX #6: Warn when encryption is disabled ---
if (-not $config.backup.encrypt) {
    Log "WARNING: Backup encryption is disabled ('encrypt: false' in config). USMT stores contain sensitive user data." 'WARN'
    Log "         Consider enabling encryption or storing backups on encrypted drives (e.g. BitLocker)." 'WARN'
}

$outputDirResolved = Resolve-PathVariables -Path $config.backup.outputDir
$timestamp = (Get-Date).ToString("yyyyMMdd-HHmmss")

# Ensure OutputDir exists
if (-not $DryRun -and -not (Test-Path $outputDirResolved)) {
    New-Item -ItemType Directory -Path $outputDirResolved -Force | Out-Null
    Log "Created backup output directory: $outputDirResolved"
}

# --- FIX #8: Use $env:TEMP for staging so orphaned data does not remain in the repo ---
$StagingStore = Join-Path $env:TEMP "migratron-temp-store-$timestamp"
$logFile      = Join-Path $env:TEMP "scanstate-$timestamp.log"

Log "USMT Binaries : $usmtPath" 'INFO'
Log "Staging Folder: $StagingStore" 'DEBUG'
Log "ScanState Log : $logFile" 'INFO'

# Build Arguments for ScanState
$scanStateExe = Join-Path $usmtPath "scanstate.exe"

# Generate custom exclusion XML dynamically if excludePaths is specified
$customXmlPath = Join-Path $PSScriptRoot "ExcludeCustom.xml"
$customXmlCreated = $false

if ($config.backup.excludePaths -and $config.backup.excludePaths.Count -gt 0) {
    Log "Generating custom exclusion rules (ExcludeCustom.xml)..." 'INFO'
    $xmlLines = @(
        '<?xml version="1.0" encoding="UTF-8"?>',
        '<migration urlid="http://www.microsoft.com/migration/1.0/migxmlext/ExcludeCustom">',
        '  <component type="Documents" context="UserAndSystem">',
        '    <displayName>Custom User Exclusions</displayName>',
        '    <role role="Data">',
        '      <rules>',
        '        <unconditionalExclude>',
        '          <objectSet>'
    )
    foreach ($path in $config.backup.excludePaths) {
        $resolvedPath = Resolve-PathVariables -Path $path
        $cleanPath = $resolvedPath.TrimEnd('\')
        if ($cleanPath -match '^[a-zA-Z]:$') {
            $cleanPath = "$cleanPath\"
        }
        if ($cleanPath.EndsWith('\')) {
            $patternPath = "${cleanPath}* [*]"
        }
        else {
            $patternPath = "${cleanPath}\* [*]"
        }
        # --- FIX #4: XML-encode the path before embedding to prevent XML injection ---
        $safePatternPath = [System.Security.SecurityElement]::Escape($patternPath)
        $xmlLines += "            <pattern type=`"File`">$safePatternPath</pattern>"
    }
    $xmlLines += @(
        '          </objectSet>',
        '        </unconditionalExclude>',
        '      </rules>',
        '    </role>',
        '  </component>',
        '</migration>'
    )
    $xmlLines | Out-File -FilePath $customXmlPath -Encoding utf8 -Force
    $customXmlCreated = $true
}

$xmlArgs = @()
foreach ($xml in $config.usmt.xmlFiles) {
    $localXmlPath = Join-Path $PSScriptRoot $xml
    if (Test-Path $localXmlPath) {
        $xmlArgs += "/i:`"$localXmlPath`""
    }
    else {
        $xmlArgs += "/i:`"$usmtPath\$xml`""
    }
}

if ($customXmlCreated -and (Test-Path $customXmlPath)) {
    $xmlArgs += "/i:`"$customXmlPath`""
}

# Add standard parameters:
#  /o   - Overwrite existing store
#  /c   - Continue on non-fatal errors
#  /v:13 - Verbose logging
#  /l   - Log file path
#  /ue:*\* - Exclude all users (optional, but by default USMT captures all users. Let's capture the current user only for speed)
#  /ui:username - Include current user. Let's use standard default options first.
$argList = @(
    "`"$StagingStore`"",
    ($xmlArgs -join ' '),
    "/o",
    "/l:`"$logFile`""
)

# ── User scope resolution ────────────────────────────────────────────────────
# Priority: users[] (named list) > userScope > default "current"
#
# users[]      non-empty → capture exactly those accounts (/ue:*\* + /ui: per entry)
# userScope    "all"     → no user-filtering flags (USMT default: all profiles)
# userScope    "current" → running user only (/ue:*\* + /ui:DOMAIN\USERNAME)
$userScope   = if (-not [string]::IsNullOrEmpty($config.usmt.userScope)) { $config.usmt.userScope } else { 'current' }
$namedUsers  = @($config.usmt.users | Where-Object { -not [string]::IsNullOrEmpty($_) })

if ($namedUsers.Count -gt 0) {
    # Named users mode — exclude all, then re-include each specified account
    $argList += '/ue:*\*'
    $userList = @()
    foreach ($u in $namedUsers) {
        # Auto-prefix with current domain if no domain separator present
        $qualified = if ($u -match '\\') { $u } else { "$env:USERDOMAIN\$u" }
        $argList  += "/ui:$qualified"
        $userList += $qualified
    }
    Log "User Scope  : Named users — $($userList -join ', ')" 'INFO'
}
elseif ($userScope -eq 'all') {
    Log "User Scope  : All users on this machine" 'WARN'
    Log "             (Set usmt.userScope to 'current' or populate usmt.users[] to narrow the scope.)" 'WARN'
}
else {
    # current: exclude everyone, then re-include only the running account
    $domain   = $env:USERDOMAIN
    $username = $env:USERNAME
    $argList += "/ue:*\*"
    $argList += "/ui:$domain\$username"
    Log "User Scope  : Current user only ($domain\$username)" 'INFO'
}

# Append any custom arguments from config
# --- FIX #3: restrict additionalArgs to a strict allowlist of safe USMT flags ---
$allowedArgPatterns = @(
    '^/c$',
    '^/nocompress$',
    '^/hardlink$',
    '^/v:\d+$',
    '^/efs:(skip|copyraw|abort|hardlink)$',
    '^/listfiles:.+$',
    '^/offlineWinDir:.+$',
    '^/offlineWinOld:.+$'
)
if ($config.usmt.additionalArgs -and $config.usmt.additionalArgs.Count -gt 0) {
    foreach ($arg in $config.usmt.additionalArgs) {
        $resolvedArg = Resolve-PathVariables -Path $arg
        $matched = $false
        foreach ($pattern in $allowedArgPatterns) {
            if ($resolvedArg -match $pattern) { $matched = $true; break }
        }
        if ($matched) {
            $argList += $resolvedArg
        }
        else {
            Log "Skipping disallowed additionalArg: '$resolvedArg'" 'WARN'
        }
    }
}

$argListString = $argList -join ' '

if ($DryRun) {
    Log "[Dry Run] Would execute: $scanStateExe $argListString" 'SUCCESS'
    Log "[Dry Run] Backup would be zipped to: $outputDirResolved\migratron-store-$timestamp.zip" 'SUCCESS'
    return
}

# Create staging folder
if (-not (Test-Path $StagingStore)) {
    New-Item -ItemType Directory -Path $StagingStore -Force | Out-Null
}

Log "Running USMT ScanState snapshot. This may take a few minutes..." 'INFO'

$processParams = @{
    FilePath     = $scanStateExe
    ArgumentList = $argListString
    Wait         = $true
    NoNewWindow  = $true
    PassThru     = $true
    ErrorAction  = 'Continue'
}

try {
    # Run scanstate
    $result = Start-Process @processParams
    $exitCode = $result.ExitCode
    
    # USMT exit codes:
    # 0 = Success
    # 1 = Success with warnings (e.g. some locked files skipped)
    # Any other code is a failure.
    if ($exitCode -eq 0 -or $exitCode -eq 1) {
        Log "ScanState snapshot completed successfully (Exit Code: $exitCode)." 'SUCCESS'
        
        # Copy log into staging folder so it's packaged in the ZIP
        if (Test-Path $logFile) {
            Copy-Item -Path $logFile -Destination (Join-Path $StagingStore "scanstate.log") -Force
            Remove-Item -Path $logFile -Force
        }
        
        # Copy XML files to staging store for self-documenting backups
        $xmlStagingDir = Join-Path $StagingStore "USMT-XML"
        New-Item -ItemType Directory -Path $xmlStagingDir -Force | Out-Null
        foreach ($xml in $config.usmt.xmlFiles) {
            $localXmlPath = Join-Path $PSScriptRoot $xml
            if (Test-Path $localXmlPath) {
                Copy-Item -Path $localXmlPath -Destination $xmlStagingDir -Force | Out-Null
            }
        }
        if ($customXmlCreated -and (Test-Path $customXmlPath)) {
            Copy-Item -Path $customXmlPath -Destination $xmlStagingDir -Force | Out-Null
        }

        # Backup the Migratron JSON configs
        if (Test-Path $ConfigPath) {
            Copy-Item -Path $ConfigPath -Destination $StagingStore -Force | Out-Null
        }
        $localConfigPath = Join-Path (Split-Path $ConfigPath) "usmt-config.local.json"
        if (Test-Path $localConfigPath) {
            Copy-Item -Path $localConfigPath -Destination $StagingStore -Force | Out-Null
        }
        
        $zipFileName = "migratron-store-$timestamp.zip"
        $zipFilePath = Join-Path $outputDirResolved $zipFileName
        
        if ($config.backup.compress) {
            Log "Compressing snapshot into ZIP archive: $zipFileName"
            Compress-Archive -Path "$StagingStore\*" -DestinationPath $zipFilePath -Force
            
            if (Test-Path $zipFilePath) {
                $bytes = (Get-Item $zipFilePath).Length
                Log "Archive created successfully!" 'SUCCESS'
                Log "Final path: $zipFilePath" 'SUCCESS'
                Log "Archive size: $(Get-FormatSize -Bytes $bytes)" 'INFO'
            }
            else {
                Log "Failed to create compressed ZIP archive." 'ERROR'
            }
        }
        else {
            # Move uncompressed staging folder directly to output dir
            $destFolder = Join-Path $outputDirResolved "migratron-store-$timestamp"
            Log "Moving uncompressed store to: $destFolder"
            Move-Item -Path $StagingStore -Destination $destFolder -Force
        }
        
        # Sync USMT binaries to the backup output directory
        $binariesDest = Join-Path $outputDirResolved "USMT-Binaries"
        $scanStateDest = Join-Path $binariesDest "scanstate.exe"
        $scanStateSource = Join-Path $usmtPath "scanstate.exe"
        
        $shouldCopy = $false
        if (-not (Test-Path $scanStateDest)) {
            $shouldCopy = $true
            Log "Syncing USMT binaries to output directory..." 'INFO'
        }
        else {
            $sourceFile = Get-Item $scanStateSource
            $destFile = Get-Item $scanStateDest
            if ($sourceFile.LastWriteTime -gt $destFile.LastWriteTime) {
                $shouldCopy = $true
                Log "Newer USMT binaries detected in ADK. Updating output directory..." 'INFO'
            }
        }

        if ($shouldCopy) {
            New-Item -ItemType Directory -Path $binariesDest -Force -ErrorAction SilentlyContinue | Out-Null
            Copy-Item -Path "$usmtPath\*" -Destination $binariesDest -Recurse -Force | Out-Null
            Log "USMT Binaries copied to: $binariesDest" 'SUCCESS'
        }
        else {
            Log "USMT Binaries are up-to-date in output directory. Skipping copy." 'DEBUG'
        }
        
        # Retention management
        Log "Checking backup retention policy..."
        $retentionLimit = $config.backup.retentionCount
        if ($retentionLimit -gt 0) {
            $backups = Get-ChildItem -Path $outputDirResolved -Filter "migratron-store-*" | 
                       Where-Object { $_.Name -match '^migratron-store-\d{8}-\d{6}(\.zip)?$' } | 
                       Sort-Object LastWriteTime
            
            if ($backups.Count -gt $retentionLimit) {
                $deleteCount = $backups.Count - $retentionLimit
                Log "Found $($backups.Count) backups. Retention policy is $retentionLimit. Deleting oldest $deleteCount backup(s)." 'WARN'
                for ($i = 0; $i -lt $deleteCount; $i++) {
                    $oldBackup = $backups[$i]
                    Log "  Deleting: $($oldBackup.Name)" 'WARN'
                    Remove-Item -Path $oldBackup.FullName -Recurse -Force
                }
            }
        }
    }
    else {
        Log "ScanState failed with exit code: $exitCode." 'ERROR'
        Log "Please check the log file at: $logFile" 'ERROR'
    }
}
catch {
    Log "An error occurred during ScanState execution: $_" 'ERROR'
}
finally {
    # Clean up custom XML file
    if ($customXmlCreated -and (Test-Path $customXmlPath)) {
        Log "Cleaning up custom XML file: $customXmlPath" 'DEBUG'
        Remove-Item -Path $customXmlPath -Force -ErrorAction SilentlyContinue | Out-Null
    }
    
    # Clean up staging directory
    if (Test-Path $StagingStore) {
        Log "Cleaning up staging directory: $StagingStore" 'DEBUG'
        Remove-Item -Path $StagingStore -Recurse -Force -ErrorAction SilentlyContinue | Out-Null
    }
    # Clean up loose log if process failed
    if (Test-Path $logFile) {
        Log "Log file is available at: $logFile" 'INFO'
    }
}
