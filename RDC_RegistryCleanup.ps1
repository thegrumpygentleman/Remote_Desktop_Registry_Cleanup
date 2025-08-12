# Remote Desktop Registry Scanner and Cleaner for Action1
# Searches and removes Remote Desktop v1.2.5326.0 registry entries
# Designed to run as System user via Action1

# Set execution policy for this session
Set-ExecutionPolicy -ExecutionPolicy Bypass -Scope Process -Force

# Create log file for Action1 to capture output
$logPath = "$env:TEMP\RemoteDesktopScan.log"
Start-Transcript -Path $logPath -Force

Write-Output "=== Remote Desktop Registry Scanner and Cleaner ==="
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

$foundEntries = @()
$removalSuccess = $true

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
                    
                    # Look for Remote Desktop related entries or specific version
                    $matchFound = $false
                    $matchReason = ""
                    
                    if ($displayName -and $displayName -match "Remote Desktop") { 
                        $matchFound = $true 
                        $matchReason += "DisplayName contains 'Remote Desktop'; "
                    }
                    if ($version -and $version -eq "1.2.5326.0") { 
                        $matchFound = $true 
                        $matchReason += "Version matches 1.2.5326.0; "
                    }
                    if ($installLocation -and $installLocation -match "Remote Desktop") { 
                        $matchFound = $true 
                        $matchReason += "InstallLocation contains 'Remote Desktop'; "
                    }
                    if ($publisher -and $publisher -match "Remote Desktop") { 
                        $matchFound = $true 
                        $matchReason += "Publisher contains 'Remote Desktop'; "
                    }
                    
                    if ($matchFound) {
                        $entry = [PSCustomObject]@{
                            RegistryPath = $subKey.PSPath
                            RegistryKey = $subKey.Name
                            SubKeyName = $subKey.PSChildName
                            DisplayName = $displayName
                            Publisher = $publisher
                            Version = $version
                            InstallLocation = $installLocation
                            UninstallString = $uninstallString
                            MatchReason = $matchReason.TrimEnd("; ")
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

# Display and process results
Write-Output ""
if ($foundEntries.Count -gt 0) {
    Write-Output "=== FOUND ENTRIES ==="
    Write-Output "Found $($foundEntries.Count) potentially related registry entries:"
    Write-Output ""
    
    foreach ($entry in $foundEntries) {
        Write-Output "Registry Key: $($entry.SubKeyName)"
        Write-Output "  Full Registry Path: $($entry.RegistryKey)"
        Write-Output "  PowerShell Path: $($entry.RegistryPath)"
        Write-Output "  Display Name: $($entry.DisplayName)"
        Write-Output "  Publisher: $($entry.Publisher)"
        Write-Output "  Version: $($entry.Version)"
        Write-Output "  Install Location: $($entry.InstallLocation)"
        Write-Output "  Match Reason: $($entry.MatchReason)"
        Write-Output ""
    }
    
    # Removal section with better error handling
    Write-Output "=== ATTEMPTING REMOVAL ==="
    Write-Output "Attempting to remove registry entries..."
    Write-Output ""
    
    foreach ($entry in $foundEntries) {
        Write-Output "Processing: $($entry.DisplayName) [$($entry.SubKeyName)]"
        
        # Try multiple removal methods
        $removed = $false
        
        # Method 1: PowerShell Remove-Item
        try {
            Remove-Item -Path $entry.RegistryPath -Recurse -Force -ErrorAction Stop
            Write-Output "SUCCESS (PowerShell): Removed $($entry.DisplayName)"
            $removed = $true
        } catch {
            Write-Output "PowerShell removal failed: $($_.Exception.Message)"
        }
        
        # Method 2: reg.exe command if PowerShell failed
        if (-not $removed) {
            try {
                $regPath = $entry.RegistryKey -replace "HKEY_LOCAL_MACHINE", "HKLM" -replace "HKEY_CURRENT_USER", "HKCU"
                $regResult = & reg delete "$regPath" /f 2>&1
                if ($LASTEXITCODE -eq 0) {
                    Write-Output "SUCCESS (REG.EXE): Removed $($entry.DisplayName)"
                    $removed = $true
                } else {
                    Write-Output "REG.EXE failed with exit code: $LASTEXITCODE"
                    Write-Output "REG.EXE output: $regResult"
                }
            } catch {
                Write-Output "REG.EXE method failed: $($_.Exception.Message)"
            }
        }
        
        if (-not $removed) {
            Write-Output "FAILED: Could not remove $($entry.DisplayName)"
            $removalSuccess = $false
        }
        
        Write-Output ""
    }
    
} else {
    Write-Output "=== NO ENTRIES FOUND ==="
    Write-Output "No Remote Desktop v1.2.5326.0 entries found in registry."
    Write-Output "The Action1 detection may be a false positive or cached data."
}

Write-Output ""
Write-Output "=== ADDITIONAL CLEANUP ==="
Write-Output "Checking for leftover folders..."

# Check common application data locations
$cleanupPaths = @(
    "$env:ProgramData\Remote Desktop",
    "$env:ALLUSERSPROFILE\Remote Desktop",
    "$env:LOCALAPPDATA\Programs\Remote Desktop",
    "$env:APPDATA\Remote Desktop"
)

foreach ($cleanupPath in $cleanupPaths) {
    if (Test-Path $cleanupPath) {
        Write-Output "Found folder: $cleanupPath"
        try {
            Remove-Item -Path $cleanupPath -Recurse -Force -ErrorAction Stop
            Write-Output "SUCCESS: Removed folder $cleanupPath"
        } catch {
            Write-Output "ERROR: Could not remove $cleanupPath - $($_.Exception.Message)"
            $removalSuccess = $false
        }
    }
}

# Check Windows Installer cache for Remote Desktop MSI files
$installerPath = "$env:SystemRoot\Installer"
if (Test-Path $installerPath) {
    Write-Output "Checking Windows Installer cache..."
    try {
        # Look for MSI files that might be related (this is basic - full MSI inspection requires more code)
        $msiFiles = Get-ChildItem -Path $installerPath -Filter "*.msi" -ErrorAction SilentlyContinue | Select-Object -First 5
        Write-Output "Found $($msiFiles.Count) MSI files in installer cache (showing first 5)"
        foreach ($msi in $msiFiles) {
            Write-Output "  MSI: $($msi.Name) - $($msi.LastWriteTime)"
        }
    } catch {
        Write-Output "Could not fully access installer cache: $($_.Exception.Message)"
    }
}

Write-Output ""
Write-Output "=== SCAN COMPLETE ==="
Write-Output "Log file location: $logPath"
Write-Output "Entries found: $($foundEntries.Count)"
Write-Output "Overall removal success: $removalSuccess"
Write-Output "Script completed at: $(Get-Date)"

# Stop logging
Stop-Transcript

# Return appropriate exit code
if ($foundEntries.Count -gt 0) {
    if ($removalSuccess) {
        Write-Output "Exit code 0: Entries found and successfully removed"
        exit 0
    } else {
        Write-Output "Exit code 2: Entries found but removal had issues"
        exit 2
    }
} else {
    Write-Output "Exit code 0: No entries found"
    exit 0
}
