<#
.SYNOPSIS
    Comprehensive diagnostics and repair script for WSL2 and Docker Desktop on Windows 10/11.

.DESCRIPTION
    This script performs essential checks and repairs for WSL2 and Docker Desktop. The Docker data backup
    feature has been removed to ensure maximum script stability. It uses ASCII-only text and highly stable
    variable syntax to ensure maximum compatibility across all PowerShell environments, fixing all known
    parsing issues related to exception messages.

.NOTES
    Requires Administrator privileges to run.
    Author: Gemini, an expert system admin assistant.
    Version: 2.1 (Final Stable Fix for Parser Errors)
#>

# Requires elevated privileges
If (-not ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole] "Administrator")) {
    Write-Host "[ERROR] This script must be run with Administrator privileges." -ForegroundColor Red
    Start-Process powershell.exe -Verb RunAs -ArgumentList "-File `"$($MyInvocation.MyCommand.Path)`""
    Exit 1
}

# --- Configuration ---
$LogFile = "$env:USERPROFILE\Desktop\wsl_docker_diagnostics_$(Get-Date -Format 'yyyyMMdd_HHmmss').txt"
$RequiredFeatures = @(
    "Microsoft-Windows-Subsystem-Linux",
    "VirtualMachinePlatform",
    "Microsoft-Hyper-V-All",
    "HypervisorPlatform"
)
$WslServices = @("LxssManager", "vmcompute", "hns")
$DockerServices = @("com.docker.service")
$KernelUrl = "https://aka.ms/wsl2kernel"
$KernelInstaller = "$env:TEMP\wsl_update_x64.msi"

# --- Functions ---

Function Log-Message {
    param(
        [Parameter(Mandatory=$true)]
        [string]$Message,
        [string]$Color = "Cyan"
    )
    $Timestamp = Get-Date -Format 'HH:mm:ss'
    $LogEntry = "[$Timestamp] $Message"
    Write-Host $LogEntry -ForegroundColor $Color
    $LogEntry | Out-File -FilePath $LogFile -Append -Encoding UTF8
}

Function Check-And-Enable-Features {
    Log-Message "[STATUS] Starting check and repair of required Windows features..." "Yellow"

    foreach ($Feature in $RequiredFeatures) {
        Log-Message "  -> Checking feature: $Feature" -Color "White"
        try {
            # Use DISM to check state
            $FeatureInfo = dism /online /Get-FeatureInfo /FeatureName:$Feature | Out-String
            if ($FeatureInfo -match "State : Enabled") {
                Log-Message "     [OK] $Feature is already enabled." "Green"
            } else {
                Log-Message "     [ACTION] $Feature is not enabled. Enabling feature: $Feature..." "Yellow"
                dism /online /enable-feature /featurename:$Feature /all /norestart | Out-Null
                if ($LASTEXITCODE -eq 0) {
                    Log-Message "     [SUCCESS] Successfully enabled $Feature." "Green"
                    $global:RebootRequired = $true
                } else {
                    Log-Message "     [ERROR] Failed to enable $Feature. DISM exit code: $LASTEXITCODE" "Red"
                }
            }
        } catch {
            # FINAL FIX: Assign message to variable, then use single quotes in Log-Message
            $ErrorMessage = $($_.Exception.Message).Trim()
            Log-Message '     [ERROR] Error checking or enabling $Feature: $ErrorMessage' "Red"
        }
    }
}

Function Manage-Services {
    param(
        [Parameter(Mandatory=$true)]
        [string[]]$ServiceNames
    )

    foreach ($svc in $ServiceNames) {
        Log-Message "  -> Checking service: $svc" -Color "White"
        try {
            $s = Get-Service -Name $svc -ErrorAction Stop
            Log-Message "     [INFO] Status: $($s.Status). Display Name: $($s.DisplayName)" "Cyan"

            if ($s.Status -ne "Running") {
                Log-Message "     [ACTION] Service '$svc' is NOT running. Attempting to START..." "Yellow" 
                
                Start-Service -Name $svc -ErrorAction Stop
                
                Log-Message "     [SUCCESS] Service '$svc' started successfully." "Green" 
            } else {
                Log-Message "     [OK] Service '$svc' is running." "Green" 
            }
        } catch {
            # FINAL FIX: Assign message to variable, then use single quotes in Log-Message
            $ErrorMessage = $($_.Exception.Message).Trim()
            Log-Message '     [ERROR] Service $svc not found or failed to start: $ErrorMessage' "Red" 
        }
    }
}

Function Fix-LxssManager-Startup {
    Log-Message "[STATUS] Ensuring LxssManager startup type is correct (Automatic)..." "Yellow"
    $Path = "HKLM:\SYSTEM\CurrentControlSet\Services\LxssManager"
    Try {
        # 'Start' value 2 is Automatic
        Set-ItemProperty -Path $Path -Name "Start" -Value 2 -Type DWord -Force -ErrorAction Stop
        Log-Message "  [SUCCESS] LxssManager startup set to Automatic (2)." "Green"
    } Catch {
        # FINAL FIX: Assign message to variable, then use single quotes in Log-Message
        $ErrorMessage = $($_.Exception.Message).Trim()
        Log-Message '  [ERROR] Could not modify LxssManager registry: $ErrorMessage' "Red"
    }
}

Function Check-And-Install-Wsl-Kernel {
    Log-Message "[STATUS] Checking for WSL kernel installation..." "Yellow"
    $KernelPath = "$env:WINDIR\system32\lxss\tools\kernel"
    If (Test-Path $KernelPath) {
        Log-Message "  [OK] Kernel path found: $KernelPath" "Green"
    } else {
        Log-Message "  [ACTION] Kernel not found. Downloading and installing update..." "Red"
        try {
            Log-Message "  -> Downloading kernel from $KernelUrl..." -Color "Cyan"
            Invoke-WebRequest -Uri $KernelUrl -OutFile $KernelInstaller -ErrorAction Stop
            Log-Message "  -> Installing kernel update..." -Color "Cyan"
            # /qn for quiet install, /i for install
            $Process = Start-Process -FilePath "msiexec" -ArgumentList "/i `"$KernelInstaller`" /qn" -Wait -PassThru -ErrorAction Stop
            if ($Process.ExitCode -eq 0) {
                Log-Message "  [SUCCESS] Kernel update installed successfully." "Green"
                $global:RebootRequired = $true
            } else {
                Log-Message "  [ERROR] Kernel installation failed with exit code: $($Process.ExitCode)" "Red"
            }
        } catch {
            # FINAL FIX: Assign message to variable, then use single quotes in Log-Message
            $ErrorMessage = $($_.Exception.Message).Trim()
            Log-Message '  [ERROR] Error during kernel download/install: $ErrorMessage' "Red"
        }
    }
}

Function Set-Default-Wsl-Version {
    Log-Message "[STATUS] Ensuring default WSL version is set to 2..." "Yellow"
    try {
        $result = wsl --set-default-version 2 2>&1
        if ($LASTEXITCODE -eq 0) {
            Log-Message "  [SUCCESS] WSL 2 set as default successfully." "Green"
        } elseif ($result -like "*The requested operation could not be completed because a required feature is not installed.*") {
             Log-Message "  [WARNING] Cannot set default version yet. Missing features/reboot required." "Yellow"
        } else {
            Log-Message "  [WARNING] Could not set default version. Output: $result" "Yellow"
        }
    } catch {
        # FINAL FIX: Assign message to variable, then use single quotes in Log-Message
        $ErrorMessage = $($_.Exception.Message).Trim()
        Log-Message '  [ERROR] Unable to execute "wsl --set-default-version": $ErrorMessage' "Red"
    }
}

Function Check-Wsl-Docker-Status {
    Log-Message "[STATUS] Running final status checks for WSL and Docker..." "Yellow"

    Log-Message "--- WSL Status ---" "Cyan"
    try {
        $status = wsl --status 2>&1 | Out-String
        Log-Message "$status" "White"
    } Catch {
        # FINAL FIX: Assign message to variable, then use single quotes in Log-Message
        $ErrorMessage = $($_.Exception.Message).Trim()
        Log-Message '  [ERROR] Unable to execute "wsl --status": $ErrorMessage' "Red"
    }

    Log-Message "--- Docker Status ---" "Cyan"
    if (Get-Command "docker" -ErrorAction SilentlyContinue) {
        try {
            $dockerVersion = docker --version 2>&1 | Out-String
            Log-Message "  [OK] Docker CLI found: $dockerVersion" "Green"
            $dockerInfo = docker info --format '{{.OSType}}' 2>&1
            if ($dockerInfo -match "linux") {
                Log-Message "  [OK] Docker is using the Linux engine (WSL2 integration likely working)." "Green"
            } else {
                Log-Message "  [WARNING] Docker engine might be set to Windows or erroring. Run 'docker info' manually." "Yellow"
            }
        } catch {
            # FINAL FIX: Assign message to variable, then use single quotes in Log-Message
            $ErrorMessage = $($_.Exception.Message).Trim()
            Log-Message '  [ERROR] Error running Docker command (Daemon likely stopped): $ErrorMessage' "Red"
        }
    } else {
        Log-Message "  [WARNING] Docker CLI not found in PATH. Is Docker Desktop installed?" "Yellow"
    }
}

# --- Main Execution ---

$global:RebootRequired = $false
Clear-Host
"=== WSL2 & Docker Repair Script ===" | Out-File -FilePath $LogFile -Encoding UTF8
"Date: $(Get-Date)" | Out-File -FilePath $LogFile -Append
"Running as: $env:USERNAME (Administrator)" | Out-File -FilePath $LogFile -Append
"-------------------------------------------`n" | Out-File -FilePath $LogFile -Append

Log-Message "Starting WSL2 and Docker Desktop Diagnostics and Repair." "Magenta"
Log-Message "Output log file: $LogFile" "Cyan"
Log-Message "========================================================" "Magenta"

# 1. Features
Log-Message "`n[1] CHECKING WINDOWS FEATURES" "Magenta"
Check-And-Enable-Features

# 2. Kernel
Log-Message "`n[2] CHECKING WSL KERNEL" "Magenta"
Check-And-Install-Wsl-Kernel

# 3. WSL Services
Log-Message "`n[3] MANAGING WSL SERVICES" "Magenta"
Fix-LxssManager-Startup
Manage-Services -ServiceNames $WslServices

# 4. Docker Service
Log-Message "`n[4] MANAGING DOCKER SERVICE" "Magenta"
Manage-Services -ServiceNames $DockerServices

# 5. Default Version
Log-Message "`n[5] SETTING DEFAULT WSL VERSION" "Magenta"
Set-Default-Wsl-Version

# 6. Final Status
Log-Message "`n[6] FINAL STATUS CHECK" "Magenta"
Check-Wsl-Docker-Status

Log-Message "========================================================" "Magenta"
Log-Message "Script execution complete." "Magenta"

# --- Summary and Cleanup ---

if ($global:RebootRequired) {
    Log-Message "`n[WARNING] ACTION REQUIRED: One or more Windows features were enabled or the kernel was installed." "Red"
    Log-Message "   Please RESTART your PC now for the changes to take full effect." "Red"
} else {
    Log-Message "`n[SUCCESS] No immediate reboot appears required." "Green"
}

Log-Message "Full report saved to: $LogFile" "Cyan"

# Pause for user review
Read-Host "Press Enter to exit..."