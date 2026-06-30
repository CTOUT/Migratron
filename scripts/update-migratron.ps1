[CmdletBinding()]
param()

$repoRoot = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot ".."))
Push-Location $repoRoot

try {
    # Fetch latest branches and tags
    git fetch origin 2>&1 | Out-Null
    
    # Check if we are behind origin/main
    $behind = git rev-list HEAD..origin/main --count
    if ([int]$behind -eq 0) {
        Pop-Location
        exit 0 # Up to date
    }

    # Attempt to pull cleanly
    $pullOutput = git pull origin main --no-edit 2>&1
    if ($LASTEXITCODE -eq 0) {
        Pop-Location
        exit 1 # Updated successfully
    } else {
        # Failed to pull (likely local changes)
        Pop-Location
        exit 2 # Error
    }
} catch {
    Pop-Location
    exit 2
}
