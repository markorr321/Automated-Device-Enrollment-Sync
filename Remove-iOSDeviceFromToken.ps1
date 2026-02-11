#Requires -Version 5.1
#Requires -Modules Microsoft.Graph.Authentication
<#
.SYNOPSIS
    Removes an iOS device from Intune and its Apple enrollment program token.

.DESCRIPTION
    Uses the Microsoft Graph Beta API to locate an iOS device by serial number,
    validates it exists in both Intune managed devices and the DEP/ADE enrollment
    program token, then deletes from Intune first followed by the DEP token.
    Authenticates interactively with delegated user permissions via browser sign-in.

.PARAMETER SerialNumber
    The serial number of the iOS device to remove.

.EXAMPLE
    .\Remove-iOSDeviceFromToken.ps1 -SerialNumber "DNQJC123ABCD"
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

        $devicesUri = "$GraphBaseUrl/deviceManagement/depOnboardingSettings/$tokenId/importedAppleDeviceIdentities?`$filter=serialNumber eq '$SerialNumber'"
        try {
            $devicesResponse = Invoke-GraphRequest -Method GET -Uri $devicesUri
        }
        catch {
            $devicesUri = "$GraphBaseUrl/deviceManagement/depOnboardingSettings/$tokenId/importedAppleDeviceIdentities"
            $devicesResponse = Invoke-GraphRequest -Method GET -Uri $devicesUri
            $devicesResponse.value = @($devicesResponse.value | Where-Object { $_.serialNumber -eq $SerialNumber })
        }

        if ($devicesResponse.value -and $devicesResponse.value.Count -gt 0) {
            $foundToken = $token
            $foundDepDevice = $devicesResponse.value[0]
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
    Write-Host "`nVerifying Intune removal..." -ForegroundColor Cyan
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
