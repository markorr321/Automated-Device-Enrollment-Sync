# ADE Sync - Apple Device Enrollment Sync Tool

```
 ▄▀█ █▀▄ █▀▀   █▀ █▄█ █▄░█ █▀▀
 █▀█ █▄▀ ██▄   ▄█ ░█░ █░▀█ █▄▄
```

## Description

An automated PowerShell tool for synchronizing Apple Business Manager (ADE/DEP) devices with Microsoft Intune. This script automates the synchronization process and provides an interactive interface with real-time status updates, cooldown timers, and automatic retry functionality.

## Features

- **Automated Synchronization**: Continuously monitors and syncs ADE/DEP tokens with Microsoft Intune
- **Interactive UI**: Color-coded console output with emoji indicators for easy status tracking
- **Cooldown Management**: Respects Microsoft's 15-minute cooldown period between sync requests
- **Real-time Countdown Timer**: Visual countdown display showing time remaining until next sync
- **Multi-Token Support**: Processes multiple ADE/DEP tokens in sequence
- **Error Handling**: Robust error handling with detailed error messages
- **Status Monitoring**: Displays last sync time, device count, and sync status for each token
- **User Controls**: Press Enter to exit during countdown, or wait for automatic continuation

## Prerequisites

### Required Software

- PowerShell 5.1 or later
- Microsoft Graph PowerShell SDK modules:
  - Microsoft.Graph.Authentication
  - Microsoft.Graph.Beta.DeviceManagement
  - Microsoft.Graph.Beta.DeviceManagement.Actions
  - Microsoft.Graph.Beta.DeviceManagement.Enrollment
  - Microsoft.Graph.Beta.Devices.CorporateManagement

### Required Permissions

Entra ID Delegated Permissions:
- `DeviceManagementServiceConfig.ReadWrite.All`
- `DeviceManagementConfiguration.Read.All` (recommended)
- `DeviceManagementConfiguration.ReadWrite.All` (recommended)

### Prerequisites in Intune

- Active Apple Business Manager integration
- Valid ADE/DEP token(s) uploaded to Microsoft Intune
- Appropriate Entra ID role assignments (Intune Administrator or Global Administrator)

## Installation

### 1. Install Microsoft Graph PowerShell SDK

The script will prompt you to install required modules if they're not already installed. Alternatively, you can install them manually:

```powershell
# Install required modules
Install-Module Microsoft.Graph.Authentication -Force -AllowClobber
Install-Module Microsoft.Graph.Beta.DeviceManagement -Force -AllowClobber
Install-Module Microsoft.Graph.Beta.DeviceManagement.Actions -Force -AllowClobber
Install-Module Microsoft.Graph.Beta.DeviceManagement.Enrollment -Force -AllowClobber
Install-Module Microsoft.Graph.Beta.Devices.CorporateManagement -Force -AllowClobber
```

### 2. Download the Script

Clone this repository or download the ADE-Sync.ps1 file:

```bash
git clone https://github.com/markorr321/Automated-Device-Enrollment-Sync.git
cd Automated-Device-Enrollment-Sync
```

## Usage

### Running the Script

1. Open PowerShell as Administrator
2. Navigate to the script directory
3. Execute the script:

```powershell
.\ADE-Sync.ps1
```

### What Happens When You Run It

1. **Module Check**: The script checks for required modules and prompts to install if missing
2. **Authentication**: You'll be prompted to sign in with your Microsoft 365 credentials
3. **Token Discovery**: The script automatically discovers all configured ADE/DEP tokens in your Intune tenant
4. **Status Display**: For each token, the script displays:
   - Token name and associated Apple ID
   - Last successful sync date/time
   - Last triggered sync date/time
   - Current synced device count
5. **Sync Execution**: The script triggers a sync operation for each token
6. **Cooldown Period**: After each sync, a 15-minute countdown timer begins
7. **Continuous Monitoring**: The process repeats automatically after the cooldown period

### Interactive Controls

- **Press Enter**: Exit the script during countdown
- **Press Ctrl+C**: Cancel the script at any time

## How It Works

### Sync Process Flow

```
┌─────────────────────────────────────┐
│   Connect to Microsoft Graph        │
└──────────────┬──────────────────────┘
               │
               ▼
┌─────────────────────────────────────┐
│   Retrieve ADE/DEP Tokens           │
└──────────────┬──────────────────────┘
               │
               ▼
┌─────────────────────────────────────┐
│   For Each Token:                   │
│   - Display Current Status          │
│   - Check Cooldown Period           │
│   - Trigger Sync (if allowed)       │
│   - Wait 15 Minutes                 │
└──────────────┬──────────────────────┘
               │
               ▼
┌─────────────────────────────────────┐
│   Repeat Process                    │
└─────────────────────────────────────┘
```

### Cooldown Period

Microsoft enforces a 15-minute cooldown between ADE/DEP sync requests. This script:

- Automatically detects when a token is in cooldown
- Displays a countdown timer showing time remaining
- Prevents sync attempts during the cooldown period
- Automatically resumes syncing when the cooldown expires

## Configuration

No configuration file is needed. The script uses delegated authentication and automatically discovers your Intune environment settings.

### Custom Scopes (Optional)

If you need to modify the required permissions, edit line 135 in ADE-Sync.ps1:

```powershell
$scopes = @('DeviceManagementServiceConfig.ReadWrite.All')
```

## Troubleshooting

### Common Issues

**Issue**: "No ADE/DEP tokens found"
- **Solution**: Verify you have uploaded ADE/DEP tokens in the Microsoft Intune admin center under Devices > Enrollment > Apple enrollment > Enrollment program tokens

**Issue**: Authentication fails
- **Solution**: Ensure your account has the required Entra ID permissions and is assigned an appropriate Intune role

**Issue**: Sync fails with API error
- **Solution**: Check that your ADE/DEP token is not expired in Apple Business Manager

**Issue**: Module not found errors
- **Solution**: The script will prompt you to install required modules. Answer 'Y' when prompted, or install them manually using the commands above

### Debug Mode

To enable verbose output for troubleshooting, run:

```powershell
$VerbosePreference = "Continue"
.\ADE-Sync.ps1
```

## API Reference

This script uses the Microsoft Graph Beta API:

- `GET /deviceManagement/depOnboardingSettings` - Retrieve ADE tokens
- `GET /deviceManagement/depOnboardingSettings/{id}` - Get token details
- `POST /deviceManagement/depOnboardingSettings/{id}/syncWithAppleDeviceEnrollmentProgram` - Trigger sync

See the [Microsoft Graph API documentation](https://docs.microsoft.com/en-us/graph/api/intune-enrollment-deponboardingsetting-sync) for more details.

## Version History

**v1.0** (2025-09-25)
- Initial release
- Interactive UI with countdown timers
- Multi-token support
- Automatic cooldown management
- Enhanced error handling
- Optional module installation

## Author

**Mark Orr**

## Contributing

Contributions are welcome! Please feel free to submit a Pull Request.

## License

This project is provided as-is for use with Microsoft Intune and Apple Business Manager integration.

## Acknowledgments

- Built using the Microsoft Graph PowerShell SDK
- Designed for integration with Microsoft Intune and Apple Business Manager

## Support

For issues, questions, or contributions, please open an issue in the [GitHub repository](https://github.com/markorr321/Automated-Device-Enrollment-Sync).

---

**Note**: This tool is designed for IT administrators managing Apple devices in enterprise environments using Microsoft Intune and Apple Business Manager.
