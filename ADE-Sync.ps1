<#
.SYNOPSIS
  Triggers Apple Business Manager (ADE/DEP) sync in Intune using interactive (delegated) auth only.
.NOTES
  Requires Microsoft Graph PowerShell SDK already installed.
  Delegated permission needed on first run: DeviceManagementServiceConfig.ReadWrite.All
#>

[CmdletBinding()]
param()

function Write-Info($msg)    { Write-Host $msg -ForegroundColor Cyan }
function Write-Success($msg) { Write-Host $msg -ForegroundColor DarkGreen }
function Write-Action($msg)  { Write-Host $msg -ForegroundColor White }
function Write-ErrorLine($m) { Write-Host $m   -ForegroundColor DarkRed }
function Write-Title($msg)   { Write-Host "`n$msg" -ForegroundColor Cyan }

# Display header
Write-Host @"

 ▄▀█ █▀▄ █▀▀   █▀ █▄█ █▄░█ █▀▀
 █▀█ █▄▀ ██▄   ▄█ ░█░ █░▀█ █▄▄

"@ -ForegroundColor Cyan

Write-Host "Apple Device Enrollment Sync Tool" -ForegroundColor Yellow
Write-Host "Automated ADE/DEP synchronization with Microsoft Intune" -ForegroundColor Gray

# Connect (delegated)
$scopes = @('DeviceManagementServiceConfig.ReadWrite.All')
Write-Title "Connecting to Microsoft Graph (delegated)"
Connect-MgGraph -Scopes $scopes -NoWelcome

# ADE / DEP sync (beta cmdlets; no profile switch needed)
Write-Title "Syncing Apple Business Manager (ADE/DEP) with Intune"

# Infinite sync loop
while ($true) {
  $depSettings = Get-MgBetaDeviceManagementDepOnboardingSetting
  if (-not $depSettings) {
    Write-Info "No ADE/DEP tokens found."
    return
  }

  foreach ($dep in $depSettings) {
  Write-Host "`n📱 " -NoNewline -ForegroundColor Blue
  Write-Host "Token: " -NoNewline -ForegroundColor White
  Write-Host "$($dep.TokenName)" -NoNewline -ForegroundColor Yellow
  Write-Host " (Apple ID: " -NoNewline -ForegroundColor Gray
  Write-Host "$($dep.AppleIdentifier)" -NoNewline -ForegroundColor Cyan
  Write-Host ")" -ForegroundColor Gray
  
  try {
    $pre = Get-MgBetaDeviceManagementDepOnboardingSetting -DepOnboardingSettingId $dep.Id |
      Select-Object TokenName, AppleIdentifier, LastSuccessfulSyncDateTime, LastSyncTriggeredDateTime, SyncedDeviceCount

    # Convert UTC times to local time for display
    $lastSuccess = if ($pre.LastSuccessfulSyncDateTime) { 
      [DateTime]::Parse($pre.LastSuccessfulSyncDateTime).ToLocalTime() 
    } else { "Never" }
    
    $lastTriggered = if ($pre.LastSyncTriggeredDateTime) { 
      [DateTime]::Parse($pre.LastSyncTriggeredDateTime).ToLocalTime() 
    } else { "Never" }

    Write-Host "   📊 " -NoNewline -ForegroundColor Green
    Write-Host "Last success: " -NoNewline -ForegroundColor White
    Write-Host "$lastSuccess" -ForegroundColor Green
    
    Write-Host "   🕒 " -NoNewline -ForegroundColor Blue
    Write-Host "Last triggered: " -NoNewline -ForegroundColor White
    Write-Host "$lastTriggered" -ForegroundColor Blue
    
    Write-Host "   📱 " -NoNewline -ForegroundColor Magenta
    Write-Host "Device count: " -NoNewline -ForegroundColor White
    Write-Host "$($pre.SyncedDeviceCount)" -ForegroundColor Magenta

    # Check 15-minute cooldown
    if ($lastTriggered -ne "Never") {
      $timeSinceLastSync = (Get-Date) - $lastTriggered
      $cooldownMinutes = 15
      
      if ($timeSinceLastSync.TotalMinutes -lt $cooldownMinutes) {
        $nextSyncTime = $lastTriggered.AddMinutes($cooldownMinutes)
        $remainingSeconds = [math]::Ceiling(($nextSyncTime - (Get-Date)).TotalSeconds)
        
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
          $remainingSeconds = [math]::Ceiling(($nextSyncTime - (Get-Date)).TotalSeconds)
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

    Sync-MgBetaDeviceManagementDepOnboardingSettingWithAppleDeviceEnrollmentProgram `
      -DepOnboardingSettingId $dep.Id -ErrorAction Stop

    Write-Host "`n   ✅ " -NoNewline -ForegroundColor Green
    Write-Host "ADE sync action submitted successfully!" -ForegroundColor White
    
    # Always show 15-minute countdown after sync - starts immediately
    $nextSyncTime = (Get-Date).AddMinutes(15)
    $remainingSeconds = [math]::Ceiling(($nextSyncTime - (Get-Date)).TotalSeconds)
    
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
      $remainingSeconds = [math]::Ceiling(($nextSyncTime - (Get-Date)).TotalSeconds)
    }
    
    # Show cursor again
    [Console]::CursorVisible = $true
    
    Write-Host "`n   ✅ " -NoNewline -ForegroundColor Green
    Write-Host "Cooldown period completed!" -ForegroundColor White
    
    # Automatically continue to next cycle after 2 seconds
    Write-Host "`n   🔄 " -NoNewline -ForegroundColor Green
    Write-Host "Starting next sync cycle in 3 seconds..." -ForegroundColor White
    Start-Sleep -Seconds 3
    
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
  catch {
    Write-Host "`n   ❌ " -NoNewline -ForegroundColor Red
    Write-Host "ADE sync failed for token '" -NoNewline -ForegroundColor White
    Write-Host "$($dep.TokenName)" -NoNewline -ForegroundColor Yellow
    Write-Host "'" -ForegroundColor White
    Write-Host "   💬 " -NoNewline -ForegroundColor Red
    Write-Host "Error: $($_.Exception.Message)" -ForegroundColor Gray
  }
  }
}
