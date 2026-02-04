<#
.SYNOPSIS
    Apple Device Enrollment (ADE/DEP) Sync Tool for Microsoft Intune
    
.DESCRIPTION
    This PowerShell script automates the synchronization of Apple Business Manager 
    (ADE/DEP) devices with Microsoft Intune. It provides an interactive interface 
    with real-time status updates, cooldown timers, and automatic retry functionality.
    
    The script connects to Microsoft Graph using delegated authentication and 
    continuously monitors and triggers ADE/DEP sync operations while respecting 
    Microsoft's 15-minute cooldown period between sync requests.

.PARAMETER None
    This script does not accept any parameters and runs interactively.

.EXAMPLE
    .\ADE-Sync.ps1
    Runs the ADE sync tool with interactive prompts and continuous monitoring.

.NOTES
    File Name      : ADE-Sync.ps1
    Author         : Mark Orr
    Prerequisite   : Microsoft Graph PowerShell SDK
    Created        : [Creation Date]
    Last Modified  : 2025-09-25
    Version        : 1.0
    
    Required Permissions:
    - DeviceManagementServiceConfig.ReadWrite.All (Delegated)
    
    Dependencies:
    - Microsoft Graph PowerShell SDK
    - Active Apple Business Manager tokens in Intune
    - Appropriate Azure AD permissions

.LINK
    https://docs.microsoft.com/en-us/graph/api/intune-enrollment-deponboardingsetting-sync
    
.COMPONENT
    Microsoft Graph PowerShell SDK
    Microsoft Intune
    Apple Business Manager Integration
#>

<#
Required Graph API Permissions:

DeviceManagementConfiguration.Read.All
DeviceManagementConfiguration.ReadWrite.All
DeviceManagementServiceConfig.Read.All
DeviceManagementServiceConfig.ReadWrite.All
#>

# ============================================================================
# SCRIPT PARAMETERS AND CONFIGURATION
# ============================================================================
# Define script parameters (none required for this script)
[CmdletBinding()]
param()

# ============================================================================
# MICROSOFT GRAPH MODULE REQUIREMENTS
# ============================================================================
Write-Host "`nChecking and installing required Microsoft Graph modules..." -ForegroundColor Cyan

# Required Modules - Install if not present:
$requiredModules = @(
    'Microsoft.Graph.Authentication',
    'Microsoft.Graph.Beta.DeviceManagement',
    'Microsoft.Graph.Beta.DeviceManagement.Actions',
    'Microsoft.Graph.Beta.DeviceManagement.Enrollment',
    'Microsoft.Graph.Beta.Devices.CorporateManagement'
)

foreach ($module in $requiredModules) {
    if (-not (Get-Module -ListAvailable -Name $module)) {
        Write-Host "  Installing $module..." -ForegroundColor Gray
        Install-Module $module -Force -AllowClobber -Scope CurrentUser
    } else {
        Write-Host "  $module already installed" -ForegroundColor DarkGray
    }
}

Write-Host "`nAll prerequisites met! Modules will auto-load when needed." -ForegroundColor Green
Write-Host ("=" * 60) -ForegroundColor DarkGray

# ============================================================================
# HELPER FUNCTIONS SECTION
# ============================================================================
# Custom output functions for consistent formatting and color coding
function Write-Info($msg)    { Write-Host $msg -ForegroundColor Cyan }
function Write-Success($msg) { Write-Host $msg -ForegroundColor DarkGreen }
function Write-Action($msg)  { Write-Host $msg -ForegroundColor White }
function Write-ErrorLine($m) { Write-Host $m   -ForegroundColor DarkRed }
function Write-Title($msg)   { Write-Host "`n$msg" -ForegroundColor Cyan }

# ============================================================================
# APPLICATION HEADER AND BRANDING
# ============================================================================
# Display ASCII art header and application title
Write-Host @"

 ▄▀█ █▀▄ █▀▀   █▀ █▄█ █▄░█ █▀▀
 █▀█ █▄▀ ██▄   ▄█ ░█░ █░▀█ █▄▄

"@ -ForegroundColor Cyan

Write-Host "Apple Device Enrollment Sync Tool" -ForegroundColor Yellow
Write-Host "Automated ADE/DEP synchronization with Microsoft Intune" -ForegroundColor Gray

# ============================================================================
# MICROSOFT GRAPH AUTHENTICATION SECTION
# ============================================================================
# Connect to Microsoft Graph using delegated permissions
# This requires interactive login and appropriate Azure AD permissions
$scopes = @('DeviceManagementServiceConfig.ReadWrite.All')
Write-Title "Connecting to Microsoft Graph (delegated)"
Connect-MgGraph -Scopes $scopes -NoWelcome

# ============================================================================
# MAIN ADE/DEP SYNC PROCESSING SECTION
# ============================================================================
# Initialize the ADE/DEP synchronization process using Microsoft Graph Beta cmdlets
Write-Title "Syncing Apple Business Manager (ADE/DEP) with Intune"

# ============================================================================
# CONTINUOUS MONITORING LOOP
# ============================================================================
# Main infinite loop that continuously monitors and processes ADE/DEP tokens
while ($true) {
  # Retrieve all configured ADE/DEP onboarding settings from Intune
  $depSettings = Get-MgBetaDeviceManagementDepOnboardingSetting
  
  # Exit if no ADE/DEP tokens are configured in Intune
  if (-not $depSettings) {
    Write-Info "No ADE/DEP tokens found."
    return
  }

  # ============================================================================
  # TOKEN PROCESSING LOOP
  # ============================================================================
  # Process each ADE/DEP token individually
  foreach ($dep in $depSettings) {
    # ========================================================================
    # TOKEN INFORMATION DISPLAY
    # ========================================================================
    # Display current token name and associated Apple ID
    Write-Host "`n📱 " -NoNewline -ForegroundColor Blue
    Write-Host "Token: " -NoNewline -ForegroundColor White
    Write-Host "$($dep.TokenName)" -NoNewline -ForegroundColor Yellow
    Write-Host " (Apple ID: " -NoNewline -ForegroundColor Gray
    Write-Host "$($dep.AppleIdentifier)" -NoNewline -ForegroundColor Cyan
    Write-Host ")" -ForegroundColor Gray
    
    try {
      # ======================================================================
      # SYNC STATUS RETRIEVAL AND PROCESSING
      # ======================================================================
      # Get detailed sync information for the current token
      $pre = Get-MgBetaDeviceManagementDepOnboardingSetting -DepOnboardingSettingId $dep.Id |
        Select-Object TokenName, AppleIdentifier, LastSuccessfulSyncDateTime, LastSyncTriggeredDateTime, SyncedDeviceCount

      # Convert UTC timestamps to local time for calculations and display
      $lastSuccessDateTime = if ($pre.LastSuccessfulSyncDateTime) { 
        [DateTime]::Parse($pre.LastSuccessfulSyncDateTime).ToLocalTime()
      } else { $null }
      
      $lastTriggeredDateTime = if ($pre.LastSyncTriggeredDateTime) { 
        [DateTime]::Parse($pre.LastSyncTriggeredDateTime).ToLocalTime()
      } else { $null }
      
      # Format for display with 12-hour format
      $lastSuccess = if ($lastSuccessDateTime) { 
        $lastSuccessDateTime.ToString("MM/dd/yyyy h:mm:ss tt")
      } else { "Never" }
      
      $lastTriggered = if ($lastTriggeredDateTime) { 
        $lastTriggeredDateTime.ToString("MM/dd/yyyy h:mm:ss tt")
      } else { "Never" }

      # Display sync status information with icons and color coding
      Write-Host "   📊 " -NoNewline -ForegroundColor Green
      Write-Host "Last success: " -NoNewline -ForegroundColor White
      Write-Host "$lastSuccess" -ForegroundColor Green
      
      Write-Host "   🕒 " -NoNewline -ForegroundColor Blue
      Write-Host "Last triggered: " -NoNewline -ForegroundColor White
      Write-Host "$lastTriggered" -ForegroundColor Blue
      
      Write-Host "   📱 " -NoNewline -ForegroundColor Magenta
      Write-Host "Device count: " -NoNewline -ForegroundColor White
      Write-Host "$($pre.SyncedDeviceCount)" -ForegroundColor Magenta

      # ======================================================================
      # COOLDOWN PERIOD VALIDATION
      # ======================================================================
      # Microsoft enforces a 15-minute cooldown between ADE sync requests
      # Check if we need to wait before allowing another sync
      if ($lastTriggeredDateTime) {
        $timeSinceLastSync = (Get-Date) - $lastTriggeredDateTime
        $cooldownMinutes = 15
        
        # If cooldown period is still active, start countdown timer
        if ($timeSinceLastSync.TotalMinutes -lt $cooldownMinutes) {
          $nextSyncTime = $lastTriggeredDateTime.AddMinutes($cooldownMinutes)
          $remainingSeconds = [math]::Max(0, [math]::Floor(($nextSyncTime - (Get-Date)).TotalSeconds))
        
        Write-Host "`n   ⏱️  " -NoNewline -ForegroundColor Red
        Write-Host "Cooldown active for token: " -NoNewline -ForegroundColor White
        Write-Host "$($dep.TokenName)" -ForegroundColor Yellow
        
        Write-Host "   📅 " -NoNewline -ForegroundColor Green
        Write-Host "Next sync available at: " -NoNewline -ForegroundColor White
        Write-Host "$($nextSyncTime.ToString('h:mm:ss tt'))" -ForegroundColor Green
        
        Write-Host "   ⏳ " -NoNewline -ForegroundColor Cyan
        Write-Host "Starting countdown timer..." -ForegroundColor White
        Write-Host "   💡 " -NoNewline -ForegroundColor Yellow
        Write-Host "Press " -NoNewline -ForegroundColor Gray
        Write-Host "Enter" -NoNewline -ForegroundColor White
        Write-Host " to exit or " -NoNewline -ForegroundColor Gray
        Write-Host "Ctrl+C" -NoNewline -ForegroundColor White
        Write-Host " to cancel" -ForegroundColor Gray
        Write-Host ""
        
        # Hide cursor during countdown
        [Console]::CursorVisible = $false
        
        # Countdown timer with Enter to Exit option
        while ($remainingSeconds -gt 0) {
          $minutes = [math]::Floor($remainingSeconds / 60)
          $seconds = $remainingSeconds % 60
          
          $Host.UI.RawUI.CursorPosition = @{X=0; Y=$Host.UI.RawUI.CursorPosition.Y}
          Write-Host "   " -NoNewline -ForegroundColor Yellow
          Write-Host "Time remaining: " -NoNewline -ForegroundColor White
          Write-Host "$($minutes.ToString('00')):$($seconds.ToString('00'))" -NoNewline -ForegroundColor Yellow
          Write-Host " " -NoNewline
          
          # Check if Enter was pressed
          if ([Console]::KeyAvailable) {
            $key = [Console]::ReadKey($true)
            if ($key.Key -eq 'Enter') {
              Write-Host "`n`n   👋 " -NoNewline -ForegroundColor Green
              Write-Host "Closing terminal..." -ForegroundColor White
              Start-Sleep -Seconds 1
              # Force close the entire terminal window
              $parentProcess = (Get-WmiObject Win32_Process -Filter "ProcessId=$PID").ParentProcessId
              Stop-Process -Id $parentProcess -Force
            }
          }
          
          Start-Sleep -Seconds 1
          $remainingSeconds--
        }
        
        # Show cursor again
        [Console]::CursorVisible = $true
        
        Write-Host "`n   ✅ " -NoNewline -ForegroundColor Green
        Write-Host "Cooldown period completed!" -ForegroundColor White
        
        # Prompt to kick off the sync
        Write-Host "`n   🔄 " -NoNewline -ForegroundColor Green
        Write-Host "Press Enter to kick off sync..." -ForegroundColor White
        Read-Host
        
        # Clear screen and continue to next cycle
        Clear-Host
        
        # Show header again
        Write-Host @"

 ▄▀█ █▀▄ █▀▀   █▀ █▄█ █▄░█ █▀▀
 █▀█ █▄▀ ██▄   ▄█ ░█░ █░▀█ █▄▄

"@ -ForegroundColor Cyan

        Write-Host "Apple Device Enrollment Sync Tool" -ForegroundColor Yellow
        Write-Host "Automated ADE/DEP synchronization with Microsoft Intune" -ForegroundColor Gray
        
        Write-Title "Syncing Apple Business Manager (ADE/DEP) with Intune"
        
        # Continue to show fresh token info and restart the sync process
        continue
      }
    }

      # ======================================================================
      # ADE SYNC EXECUTION
      # ======================================================================
      # Execute the actual ADE/DEP sync operation via Microsoft Graph API
      # This triggers Intune to sync with Apple Business Manager
      Sync-MgBetaDeviceManagementDepOnboardingSettingWithAppleDeviceEnrollmentProgram `
        -DepOnboardingSettingId $dep.Id -ErrorAction Stop

      Write-Host "`n   ✅ " -NoNewline -ForegroundColor Green
      Write-Host "ADE sync action submitted successfully!" -ForegroundColor White
    
    # Always show 15-minute countdown after sync - starts immediately
    $nextSyncTime = (Get-Date).AddMinutes(15)
    $remainingSeconds = [math]::Max(0, [math]::Floor(($nextSyncTime - (Get-Date)).TotalSeconds))
    
    Write-Host "`n   ⏱️  " -NoNewline -ForegroundColor Red
    Write-Host "Starting 15-minute cooldown period..." -ForegroundColor White
    
    Write-Host "   📅 " -NoNewline -ForegroundColor Green
    Write-Host "Next sync available at: " -NoNewline -ForegroundColor White
    Write-Host "$($nextSyncTime.ToString('h:mm:ss tt'))" -ForegroundColor Green
    
    Write-Host "   ⏳ " -NoNewline -ForegroundColor Cyan
    Write-Host "Starting countdown timer..." -ForegroundColor White
    Write-Host "   💡 " -NoNewline -ForegroundColor Yellow
    Write-Host "Press " -NoNewline -ForegroundColor Gray
    Write-Host "Enter" -NoNewline -ForegroundColor White
    Write-Host " to exit or " -NoNewline -ForegroundColor Gray
    Write-Host "Ctrl+C" -NoNewline -ForegroundColor White
    Write-Host " to cancel" -ForegroundColor Gray
    Write-Host ""
    
    # Hide cursor during countdown
    [Console]::CursorVisible = $false
    
    # 15-minute countdown timer - starts automatically
    while ($remainingSeconds -gt 0) {
      $minutes = [math]::Floor($remainingSeconds / 60)
      $seconds = $remainingSeconds % 60
      
      $Host.UI.RawUI.CursorPosition = @{X=0; Y=$Host.UI.RawUI.CursorPosition.Y}
      Write-Host "   ⏰ " -NoNewline -ForegroundColor Yellow
      Write-Host "Time remaining: " -NoNewline -ForegroundColor White
      Write-Host "$($minutes.ToString('00')):$($seconds.ToString('00'))" -NoNewline -ForegroundColor Yellow
      Write-Host " " -NoNewline
      
      # Check if Enter was pressed
      if ([Console]::KeyAvailable) {
        $key = [Console]::ReadKey($true)
        if ($key.Key -eq 'Enter') {
          Write-Host "`n`n   👋 " -NoNewline -ForegroundColor Green
          Write-Host "Closing terminal..." -ForegroundColor White
          Start-Sleep -Seconds 1
          # Force close the entire terminal window
          $parentProcess = (Get-WmiObject Win32_Process -Filter "ProcessId=$PID").ParentProcessId
          Stop-Process -Id $parentProcess -Force
        }
      }
      
      Start-Sleep -Seconds 1
      $remainingSeconds--
    }
    
    # Show cursor again
    [Console]::CursorVisible = $true
    
    Write-Host "`n   ✅ " -NoNewline -ForegroundColor Green
    Write-Host "Cooldown period completed!" -ForegroundColor White
    
    # Prompt user before continuing to next cycle
    Write-Host "`n   🔄 " -NoNewline -ForegroundColor Green
    Write-Host "Press Enter to start next sync cycle..." -ForegroundColor White
    Read-Host
    
    # Clear screen and continue to next cycle
    Clear-Host
    
    # Show header again
    Write-Host @"

 ▄▀█ █▀▄ █▀▀   █▀ █▄█ █▄░█ █▀▀
 █▀█ █▄▀ ██▄   ▄█ ░█░ █░▀█ █▄▄

"@ -ForegroundColor Cyan

    Write-Host "Apple Device Enrollment Sync Tool" -ForegroundColor Yellow
    Write-Host "Automated ADE/DEP synchronization with Microsoft Intune" -ForegroundColor Gray
    
    Write-Title "Syncing Apple Business Manager (ADE/DEP) with Intune"
    }
    # ========================================================================
    # ERROR HANDLING SECTION
    # ========================================================================
    # Catch and display any errors that occur during the sync process
    # This includes authentication errors, API failures, or network issues
    catch {
      Write-Host "`n   ❌ " -NoNewline -ForegroundColor Red
      Write-Host "ADE sync failed for token '" -NoNewline -ForegroundColor White
      Write-Host "$($dep.TokenName)" -NoNewline -ForegroundColor Yellow
      Write-Host "'" -ForegroundColor White
      Write-Host "   💬 " -NoNewline -ForegroundColor Red
      Write-Host "Error: $($_.Exception.Message)" -ForegroundColor Gray
    }
  } # End of foreach token loop
} # End of main while loop

# ============================================================================
# SCRIPT END
# ============================================================================
