#Requires -Version 5.1
#Requires -Modules Microsoft.Graph.Authentication
<#
.SYNOPSIS
    iOS Device Removal Tool for Microsoft Intune and Apple DEP/ADE

.DESCRIPTION
    This PowerShell script automates the complete removal of iOS devices from both 
    Microsoft Intune managed devices and Apple Device Enrollment Program (DEP/ADE) 
    tokens. It provides a streamlined workflow with validation, confirmation prompts,
    and built-in cooldown tracking for DEP token synchronization.
    
    The script performs the following operations:
    1. Validates the device exists in Intune and/or DEP token
    2. Removes the device from Intune managed devices (with verification)
    3. Removes the device from the Apple enrollment program token
    4. Optionally syncs the DEP token with Apple Business Manager
    5. Tracks 15-minute cooldown period with optional countdown timer
    
    Features include pagination support for large DEP token device lists,
    cooldown status checking on startup, and the option to process multiple
    devices in sequence.

.PARAMETER SerialNumber
    The serial number of the iOS device to remove. If not provided, 
    the script will prompt for input.

.EXAMPLE
    .\Remove-iOSDeviceFromToken.ps1 -SerialNumber "DNQJC123ABCD"
    Removes the specified device from Intune and DEP token.

.EXAMPLE
    .\Remove-iOSDeviceFromToken.ps1
    Runs interactively, prompting for the device serial number.

.NOTES
    File Name      : Remove-iOSDeviceFromToken.ps1
    Author         : Mark Orr
    Prerequisite   : Microsoft Graph PowerShell SDK
    Created        : 2026-02-11
    Version        : 1.0
    
    RECOMMENDED: Run this script using PowerShell 7+ for best compatibility
                 and performance. Download from https://aka.ms/powershell
    
    Required Permissions:
    - DeviceManagementServiceConfig.ReadWrite.All (Delegated)
    - DeviceManagementManagedDevices.ReadWrite.All (Delegated)
    
    Dependencies:
    - Microsoft.Graph.Authentication module
    - Active Apple Business Manager token in Intune
    - Appropriate Azure AD permissions

.LINK
    https://docs.microsoft.com/en-us/graph/api/resources/intune-enrollment-deponboardingsetting

.COMPONENT
    Microsoft Graph PowerShell SDK
    Microsoft Intune
    Apple Business Manager Integration
#>

[CmdletBinding(SupportsShouldProcess)]
param(
    [string]$SerialNumber
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if (-not $SerialNumber) {
    $SerialNumber = Read-Host "Enter the device serial number"
    if (-not $SerialNumber) {
        Write-Host "No serial number provided. Exiting." -ForegroundColor Red
        return
    }
}

$GraphBaseUrl = 'https://graph.microsoft.com/beta'

# --- Authenticate ---

Write-Host "Signing in to Microsoft Graph (browser window will open)..." -ForegroundColor Cyan
Connect-MgGraph -Scopes 'DeviceManagementServiceConfig.ReadWrite.All','DeviceManagementManagedDevices.ReadWrite.All' -NoWelcome

# Build auth header using the SDK's token
function Invoke-GraphRequest {
    param(
        [string]$Method,
        [string]$Uri
    )

    $params = @{
        Method  = $Method
        Uri     = $Uri
        Headers = @{ 'ConsistencyLevel' = 'eventual' }
    }

    return Invoke-MgGraphRequest @params
}

Write-Host "Authenticated successfully." -ForegroundColor Green

# =====================
# COOLDOWN CHECK
# =====================

# Check if any DEP tokens are in cooldown before proceeding
Write-Host "`nChecking DEP token cooldown status..." -ForegroundColor Cyan
$tokensForCooldown = Invoke-GraphRequest -Method GET -Uri "$GraphBaseUrl/deviceManagement/depOnboardingSettings"

foreach ($tkn in $tokensForCooldown.value) {
    $tknDetails = Invoke-GraphRequest -Method GET -Uri "$GraphBaseUrl/deviceManagement/depOnboardingSettings/$($tkn.id)"
    $lastTriggered = $tknDetails.lastSyncTriggeredDateTime
    
    if ($lastTriggered) {
        $lastTriggeredLocal = [DateTime]::Parse($lastTriggered).ToLocalTime()
        $timeSinceSync = (Get-Date) - $lastTriggeredLocal
        $cooldownMinutes = 15
        
        if ($timeSinceSync.TotalMinutes -lt $cooldownMinutes) {
            $nextAvailable = $lastTriggeredLocal.AddMinutes($cooldownMinutes)
            $remainingMins = [math]::Ceiling($cooldownMinutes - $timeSinceSync.TotalMinutes)
            Write-Host "  Token '$($tkn.tokenName)': " -NoNewline -ForegroundColor Yellow
            Write-Host "In cooldown - $remainingMins min remaining" -NoNewline -ForegroundColor Red
            Write-Host " (available at $($nextAvailable.ToString('h:mm:ss tt')))" -ForegroundColor Gray
        }
        else {
            Write-Host "  Token '$($tkn.tokenName)': " -NoNewline -ForegroundColor Yellow
            Write-Host "Ready" -ForegroundColor Green
        }
    }
    else {
        Write-Host "  Token '$($tkn.tokenName)': " -NoNewline -ForegroundColor Yellow
        Write-Host "Ready (never synced)" -ForegroundColor Green
    }
}

# =====================
# VALIDATION
# =====================

# 1. Validate device in Intune managed devices
Write-Host "`nValidating device in Intune..." -ForegroundColor Cyan
$intuneUri = "$GraphBaseUrl/deviceManagement/managedDevices?`$filter=serialNumber eq '$SerialNumber'"
$intuneResponse = Invoke-GraphRequest -Method GET -Uri $intuneUri
$intuneDevice = $intuneResponse.value | Select-Object -First 1

if ($intuneDevice) {
    Write-Host "  Intune record validated." -ForegroundColor Green
    Write-Host "    Device Name   : $($intuneDevice.deviceName)"
    Write-Host "    Serial Number : $($intuneDevice.serialNumber)"
    Write-Host "    OS            : $($intuneDevice.operatingSystem) $($intuneDevice.osVersion)"
    Write-Host "    Enrolled      : $($intuneDevice.enrolledDateTime)"
    Write-Host "    Device ID     : $($intuneDevice.id)"
}
else {
    Write-Host "  Device '$SerialNumber' was NOT found in Intune managed devices." -ForegroundColor Yellow
}

# 2. Validate device in DEP enrollment program token
Write-Host "`nValidating device in DEP token..." -ForegroundColor Cyan
$tokensResponse = Invoke-GraphRequest -Method GET -Uri "$GraphBaseUrl/deviceManagement/depOnboardingSettings"
$tokens = $tokensResponse.value

$foundToken = $null
$foundDepDevice = $null

if (-not $tokens -or $tokens.Count -eq 0) {
    Write-Host "  No Apple enrollment program tokens found in this tenant." -ForegroundColor Yellow
}
else {
    foreach ($token in $tokens) {
        $tokenId = $token.id
        $tokenName = $token.tokenName
        Write-Host "  Searching token: $tokenName..." -ForegroundColor Yellow

        # Get all devices with pagination and filter client-side
        $devicesUri = "$GraphBaseUrl/deviceManagement/depOnboardingSettings/$tokenId/importedAppleDeviceIdentities"
        $allDevices = @()
        $pageCount = 0
        
        while ($devicesUri) {
            $pageCount++
            $devicesResponse = Invoke-GraphRequest -Method GET -Uri $devicesUri
            if ($devicesResponse.value) {
                $allDevices += $devicesResponse.value
            }
            # Check for next page (handle strict mode)
            if ($devicesResponse.ContainsKey('@odata.nextLink')) {
                $devicesUri = $devicesResponse['@odata.nextLink']
            }
            else {
                $devicesUri = $null
            }
        }
        
        Write-Host "    Scanned $($allDevices.Count) devices across $pageCount page(s)" -ForegroundColor Gray
        $matchingDevices = @($allDevices | Where-Object { $_.serialNumber -ieq $SerialNumber })

        if ($matchingDevices.Count -gt 0) {
            $foundToken = $token
            $foundDepDevice = $matchingDevices[0]
            Write-Host "  DEP record validated in token '$tokenName'." -ForegroundColor Green
            Write-Host "    Serial Number : $($foundDepDevice.serialNumber)"
            Write-Host "    Device ID     : $($foundDepDevice.id)"
            Write-Host "    Platform      : $($foundDepDevice.platform)"
            Write-Host "    Model         : $($foundDepDevice.description)"
            break
        }
    }
}

if (-not $foundDepDevice) {
    Write-Host "  Device '$SerialNumber' was NOT found in any DEP token." -ForegroundColor Yellow
}

# Check we have at least one record to remove
if (-not $intuneDevice -and -not $foundDepDevice) {
    Write-Host "`nDevice '$SerialNumber' was not found in Intune or any DEP token. Nothing to remove." -ForegroundColor Red
    Disconnect-MgGraph | Out-Null
    return
}

# =====================
# STEP 1: REMOVE FROM INTUNE
# =====================

if ($intuneDevice) {
    Write-Host ""
    $confirmIntune = Read-Host "Delete device from Intune managed devices? (Y/N)"
    if ($confirmIntune -ne 'Y') {
        Write-Host "Intune deletion cancelled." -ForegroundColor Yellow
        Disconnect-MgGraph | Out-Null
        return
    }

    Write-Host "`nDeleting device from Intune..." -ForegroundColor Cyan
    try {
        Invoke-GraphRequest -Method DELETE -Uri "$GraphBaseUrl/deviceManagement/managedDevices/$($intuneDevice.id)"
        Write-Host "  Intune device record deleted." -ForegroundColor Green
    }
    catch {
        Write-Error "  Failed to delete Intune device: $_"
        Disconnect-MgGraph | Out-Null
        return
    }

    # Verify Intune removal
    Write-Host "`nWaiting 30 seconds for deletion to propagate..." -ForegroundColor Cyan
    Start-Sleep -Seconds 30
    Write-Host "Verifying Intune removal..." -ForegroundColor Cyan
    $verifyResponse = Invoke-GraphRequest -Method GET -Uri $intuneUri
    $verifyDevice = $verifyResponse.value | Select-Object -First 1
    if ($verifyDevice) {
        Write-Host "  Device is still present in Intune. Aborting DEP removal." -ForegroundColor Red
        Disconnect-MgGraph | Out-Null
        return
    }
    Write-Host "  Intune removal confirmed." -ForegroundColor Green
}

# =====================
# STEP 2: REMOVE FROM DEP TOKEN
# =====================

if ($foundDepDevice) {
    Write-Host ""
    $confirmDep = Read-Host "Remove device from DEP token '$($foundToken.tokenName)'? (Y/N)"
    if ($confirmDep -ne 'Y') {
        Write-Host "DEP removal cancelled." -ForegroundColor Yellow
        Disconnect-MgGraph | Out-Null
        return
    }

    Write-Host "`nRemoving device from DEP token..." -ForegroundColor Cyan
    try {
        Invoke-GraphRequest -Method DELETE -Uri "$GraphBaseUrl/deviceManagement/depOnboardingSettings/$($foundToken.id)/importedAppleDeviceIdentities/$($foundDepDevice.id)"
        Write-Host "  DEP token record removed." -ForegroundColor Green
    }
    catch {
        $statusCode = $_.Exception.Response.StatusCode.value__
        if ($statusCode -eq 404) {
            Write-Warning "  Device was already removed from DEP token."
        }
        else {
            Write-Error "  Failed to remove from DEP token: $_"
        }
    }
}

# =====================
# STEP 3: SYNC DEP TOKEN
# =====================

if ($foundToken) {
    Write-Host ""
    $confirmSync = Read-Host "Sync DEP token '$($foundToken.tokenName)' with Apple Business Manager? (Y/N)"
    if ($confirmSync -eq 'Y') {
        Write-Host "`nSyncing DEP token..." -ForegroundColor Cyan
        try {
            Invoke-GraphRequest -Method POST -Uri "$GraphBaseUrl/deviceManagement/depOnboardingSettings/$($foundToken.id)/syncWithAppleDeviceEnrollmentProgram"
            Write-Host "  DEP token sync initiated." -ForegroundColor Green
            
            # Show cooldown info
            $nextSyncTime = (Get-Date).AddMinutes(15)
            Write-Host "`n  " -NoNewline
            Write-Host "15-minute cooldown started" -ForegroundColor Yellow
            Write-Host "  Next sync available at: " -NoNewline -ForegroundColor White
            Write-Host "$($nextSyncTime.ToString('h:mm:ss tt'))" -ForegroundColor Cyan
            
            # Offer countdown timer
            Write-Host ""
            $waitChoice = Read-Host "  Wait for cooldown with countdown timer? (Y/N)"
            if ($waitChoice -eq 'Y') {
                $remainingSeconds = 15 * 60
                $exitedEarly = $false
                
                Write-Host "`n  Press " -NoNewline -ForegroundColor Gray
                Write-Host "Enter" -NoNewline -ForegroundColor White
                Write-Host " to exit countdown early" -ForegroundColor Gray
                Write-Host ""
                
                [Console]::CursorVisible = $false
                
                while ($remainingSeconds -gt 0) {
                    $minutes = [math]::Floor($remainingSeconds / 60)
                    $seconds = $remainingSeconds % 60
                    
                    $Host.UI.RawUI.CursorPosition = @{X=0; Y=$Host.UI.RawUI.CursorPosition.Y}
                    Write-Host "  Time remaining: " -NoNewline -ForegroundColor White
                    Write-Host "$($minutes.ToString('00')):$($seconds.ToString('00'))" -NoNewline -ForegroundColor Yellow
                    Write-Host "   " -NoNewline
                    
                    if ([Console]::KeyAvailable) {
                        $key = [Console]::ReadKey($true)
                        if ($key.Key -eq 'Enter') {
                            Write-Host "`n"
                            $exitedEarly = $true
                            break
                        }
                    }
                    
                    Start-Sleep -Seconds 1
                    $remainingSeconds--
                }
                
                [Console]::CursorVisible = $true
                
                if (-not $exitedEarly) {
                    Write-Host "`n`n  Cooldown complete!" -ForegroundColor Green
                }
                
                # Offer to re-run or exit
                Write-Host ""
                $rerunChoice = Read-Host "  [R] Remove another device  [X] Exit"
                if ($rerunChoice -eq 'R' -or $rerunChoice -eq 'r') {
                    Write-Host "`nRestarting tool...`n" -ForegroundColor Cyan
                    & $PSCommandPath
                    return
                }
                else {
                    Write-Host "`nDisconnecting from Microsoft Graph..." -ForegroundColor Gray
                    Disconnect-MgGraph | Out-Null
                    Write-Host "Goodbye!" -ForegroundColor Green
                    return
                }
            }
        }
        catch {
            Write-Warning "  Failed to sync DEP token: $($_.Exception.Message)"
        }
    }
    else {
        Write-Host "DEP token sync skipped." -ForegroundColor Yellow
    }
}

Write-Host "`nDone. Device '$SerialNumber' has been processed." -ForegroundColor Green
Disconnect-MgGraph | Out-Null
