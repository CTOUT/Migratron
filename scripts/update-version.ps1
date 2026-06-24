[CmdletBinding()]
param(
    [Parameter(Mandatory=$true, HelpMessage="Semantic version string (e.g. v1.1.0)")]
    [ValidatePattern('^v\d+\.\d+\.\d+$')]
    [string]$Version
)

$ErrorActionPreference = 'Stop'
$repoRoot = (Resolve-Path "$PSScriptRoot\..").Path

$changelogPath = Join-Path $repoRoot "CHANGELOG.md"
$migratronPath = Join-Path $repoRoot "migratron.ps1"

$dateStr = (Get-Date).ToString("yyyy-MM-dd")

# 1. Update CHANGELOG.md
if (Test-Path $changelogPath) {
    $cl = Get-Content $changelogPath -Raw
    
    $pattern = '(?m)^## \[Unreleased\]$'
    $replacement = "## [Unreleased]`r`n`r`n---`r`n`r`n## [$Version] — $dateStr"
    
    if ($cl -match $pattern) {
        $cl = $cl -replace $pattern, $replacement
        $utf8NoBom = New-Object System.Text.UTF8Encoding $false
        [System.IO.File]::WriteAllText($changelogPath, $cl, $utf8NoBom)
        Write-Host "Updated CHANGELOG.md with $Version" -ForegroundColor Green
    } else {
        Write-Host "Could not find '## [Unreleased]' section in CHANGELOG.md." -ForegroundColor Yellow
    }
}

# 2. Update migratron.ps1 version string
if (Test-Path $migratronPath) {
    $mig = Get-Content $migratronPath -Raw
    $vClean = $Version.Substring(1) # remove 'v' for the script header
    
    if ($mig -match '(?m)^\s*Version:\s*\d+\.\d+\.\d+$') {
        $mig = $mig -replace '(?m)^(\s*Version:\s*)\d+\.\d+\.\d+$', "`${1}$vClean"
        $utf8NoBom = New-Object System.Text.UTF8Encoding $false
        [System.IO.File]::WriteAllText($migratronPath, $mig, $utf8NoBom)
        Write-Host "Updated version in migratron.ps1 to $vClean" -ForegroundColor Green
    } else {
        # Inject Version line below .SYNOPSIS
        $pattern = '(?m)^(\.SYNOPSIS\r?\n[^\r\n]+)$'
        $replacement = "`${1}`r`n    Version: $vClean"
        if ($mig -match $pattern) {
            $mig = $mig -replace $pattern, $replacement
            $utf8NoBom = New-Object System.Text.UTF8Encoding $false
            [System.IO.File]::WriteAllText($migratronPath, $mig, $utf8NoBom)
            Write-Host "Injected version $vClean into migratron.ps1" -ForegroundColor Green
        }
    }
}

Write-Host "Version bump complete! Don't forget to commit the changes and create a git tag." -ForegroundColor Cyan
