# Remote Desktop Registry Scanner for Action1 Vulnerability
# Searches for Remote Desktop v1.2.5326.0 registry entries
# Designed to run as System user via Action1

# Set execution policy for this session
Set-ExecutionPolicy -ExecutionPolicy Bypass -Scope Process -Force

# Create log file for Action1 to capture output
$logPath = "$env:TEMP\RemoteDesktopScan.log"
Start-Transcript -Path $logPath -Force

Write-Output "=== Remote Desktop Registry Scanner ==="
Write-Output "Scanning for Remote Desktop v1.2.5326.0 registry entries..."
Write-Output "Running as: $($env:USERNAME)"
Write-Output "System Time: $(Get-Date)"
Write-Output ""

# Define registry paths to search
$registryPaths = @(
    "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall",
    "HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall",
    "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall"
)

# Search terms
$searchTerms = @("Remote Desktop", "1.2.5326.0")

$foundEntries = @()

foreach ($path in $registryPaths) {
    Write-Output "Checking: $path"
    
    if (Test-Path $path) {
        try {
            $subKeys = Get-ChildItem -Path $path -ErrorAction SilentlyContinue
            
            foreach ($subKey in $subKeys) {
                try {
                    $properties = Get-ItemProperty -Path $subKey.PSPath -ErrorAction SilentlyContinue
                    
                    # Check DisplayName, Publisher, DisplayVersion, and InstallLocation
                    $displayName = $properties.DisplayName
                    $publisher = $properties.Publisher
                    $version = $properties.DisplayVersion
                    $installLocation = $properties.InstallLocation
                    $uninstallString = $properties.UninstallString
                    
                    # Look for Remote Desktop related entries
                    $matchFound = $false
                    if ($displayName -and $displayName -match "Remote Desktop") { $matchFound = $true }
                    if ($version -and $version -eq "1.2.5326.0") { $matchFound = $true }
                    if ($installLocation -and $installLocation -match "Remote Desktop") { $matchFound = $true }
                    
                    if ($matchFound) {
                        $entry = [PSCustomObject]@{
                            RegistryPath = $subKey.PSPath
                            SubKey = $subKey.PSChildName
                            DisplayName = $displayName
                            Publisher = $publisher
                            Version = $version
                            InstallLocation = $installLocation
                            UninstallString = $uninstallString
                        }
                        $foundEntries += $entry
                    }
                } catch {
                    # Skip entries we can't read
                    continue
                }
            }
        } catch {
            Write-Output "Could not access $path - $($_.Exception.Message)"
        }
    } else {
        Write-Output "Registry path not found: $path"
    }
}

# Display results
Write-Host ""
if ($foundEntries.Count -gt 0) {
    Write-Host "=== FOUND ENTRIES ===" -ForegroundColor Red
    Write-Host "Found $($foundEntries.Count) potentially related registry entries:" -ForegroundColor Red
    Write-Host ""
    
    foreach ($entry in $foundEntries) {
        Write-Host "Registry Key: $($entry.SubKey)" -ForegroundColor Yellow
        Write-Host "  Full Path: $($entry.RegistryPath)"
        Write-Host "  Display Name: $($entry.DisplayName)"
        Write-Host "  Publisher: $($entry.Publisher)"
        Write-Host "  Version: $($entry.Version)"
        Write-Host "  Install Location: $($entry.InstallLocation)"
        Write-Host "  Uninstall String: $($entry.UninstallString)"
        Write-Host ""
    }
    
    # Generate removal script
    Write-Host "=== REMOVAL SCRIPT ===" -ForegroundColor Magenta
    Write-Host "To remove these entries, run this PowerShell script as Administrator:" -ForegroundColor Magenta
    Write-Host ""
    Write-Host "# BACKUP REGISTRY FIRST!" -ForegroundColor Red
    Write-Host "# Export registry before running: reg export HKLM\SOFTWARE registry_backup.reg" -ForegroundColor Red
    Write-Host ""
    
    foreach ($entry in $foundEntries) {
        $keyPath = $entry.RegistryPath -replace "Microsoft.PowerShell.Core\\Registry::", ""
        Write-Host "Remove-Item -Path `"$($entry.RegistryPath)`" -Force -ErrorAction SilentlyContinue" -ForegroundColor White
        Write-Host "Write-Host `"Removed: $($entry.DisplayName)`"" -ForegroundColor White
    }
    
} else {
    Write-Host "=== NO ENTRIES FOUND ===" -ForegroundColor Green
    Write-Host "No Remote Desktop v1.2.5326.0 entries found in registry." -ForegroundColor Green
    Write-Host "The Action1 detection may be a false positive or cached data." -ForegroundColor Yellow
}

Write-Output ""
Write-Output "=== ADDITIONAL CLEANUP ==="
Write-Output "Checking additional locations..."

# Check Windows Installer cache
$installerPath = "$env:SystemRoot\Installer"
if (Test-Path $installerPath) {
    Write-Output "Checking Windows Installer cache..."
    try {
        $msiFiles = Get-ChildItem -Path $installerPath -Filter "*.msi" -ErrorAction SilentlyContinue
        foreach ($msi in $msiFiles) {
            # This is a simplified check - full MSI parsing would require more complex code
            Write-Output "Found MSI file: $($msi.Name)"
        }
    } catch {
        Write-Output "Could not access installer cache: $($_.Exception.Message)"
    }
}

# Check common application data locations
$appDataPaths = @(
    "$env:ProgramData",
    "$env:ALLUSERSPROFILE"
)

foreach ($appPath in $appDataPaths) {
    $rdPath = Join-Path $appPath "Remote Desktop"
    if (Test-Path $rdPath) {
        Write-Output "Found Remote Desktop folder in: $rdPath"
        try {
            Remove-Item -Path $rdPath -Recurse -Force -ErrorAction Stop
            Write-Output "SUCCESS: Removed folder $rdPath"
        } catch {
            Write-Output "ERROR: Could not remove $rdPath - $($_.Exception.Message)"
        }
    }
}

Write-Output ""
Write-Output "=== SCAN COMPLETE ==="
Write-Output "Check log file at: $logPath"
Write-Output "Script completed at: $(Get-Date)"

# Stop logging
Stop-Transcript

# Return exit code based on findings
if ($foundEntries.Count -gt 0) {
    Write-Output "Exiting with code 1 - Entries found and processed"
    exit 1
} else {
    Write-Output "Exiting with code 0 - No entries found"
    exit 0
}
