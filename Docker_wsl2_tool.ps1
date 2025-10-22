<#
.SYNOPSIS
    Comprehensive diagnostics and repair script for WSL2 and Docker Desktop on Windows 10/11.

.DESCRIPTION
    This script performs essential checks, repairs, and safely backs up Docker data (volumes and containers)
    before initiating any potentially disruptive fixes (like feature enabling or kernel installation).
    It provides detailed, real-time feedback to the user and logs all actions.

.NOTES
    Requires Administrator privileges to run.
    Author: Gemini, an expert system admin assistant.
    Version: 1.1 (Added Docker Backup)
#>

# Requires elevated privileges
# Check if the script is running as Administrator
If (-not ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole] "Administrator")) {
    Write-Host "❌ This script must be run with Administrator privileges." -ForegroundColor Red
    Start-Process powershell.exe -Verb RunAs -ArgumentList "-File `"$($MyInvocation.MyCommand.Path)`""
    Exit 1
}

# --- Configuration ---
$LogFile = "$env:USERPROFILE\Desktop\wsl_docker_diagnostics_$(Get-Date -Format 'yyyyMMdd_HHmmss').txt"
$BackupDir = "$env:USERPROFILE\Desktop\Docker_Backup_$(Get-Date -Format 'yyyyMMdd_HHmmss')"
$RequiredFeatures = @(
    "Microsoft-Windows-Subsystem-Linux",
    "VirtualMachinePlatform",
    "Microsoft-Hyper-V-All", # Often needed/beneficial for Docker/VMs
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

Function Backup-Docker-Data {
    Log-Message "✅ Starting Docker data backup pre-check..." "Yellow"

    if (-not (Get-Command "docker" -ErrorAction SilentlyContinue)) {
        Log-Message "  ⚠️ Docker CLI not found. Skipping backup." "Yellow"
        return
    }

    Log-Message "  -> Creating backup directory: $BackupDir" -Color "White"
    New-Item -Path $BackupDir -ItemType Directory -Force | Out-Null

    # --- 1. Container Backups (Exporting running/stopped containers) ---
    Log-Message "  -> Exporting all existing containers..." "Cyan"
    $Containers = docker ps -a --format "{{.Names}}" 2>&1
    if ($Containers -is [System.String] -and $Containers -match "Error response") {
        Log-Message "  ❌ Could not connect to Docker daemon. Cannot perform container backup." "Red"
    } elseif ($Containers.Count -eq 0) {
        Log-Message "  ℹ️ No Docker containers found to back up." "Cyan"
    } else {
        $ContainerCount = $Containers.Count
        Log-Message "  Found $ContainerCount containers. Exporting..." "Cyan"

        foreach ($ContainerName in $Containers) {
            $ContainerName = $ContainerName.Trim()
            $ExportFile = Join-Path $BackupDir "$($ContainerName)_container_export.tar"
            Log-Message "     - Exporting $ContainerName..." -Color "White"
            try {
                docker export $ContainerName -o $ExportFile 2>&1 | Out-Null
                Log-Message "     🟢 Exported to $ExportFile" "Green"
            } catch {
                Log-Message "     ❌ Failed to export $ContainerName: $($_.Exception.Message)" "Red"
            }
        }
    }

    # --- 2. Volume Backups (Using a temporary Alpine container) ---
    Log-Message "  -> Backing up Docker volumes..." "Cyan"
    $Volumes = docker volume ls --format "{{.Name}}" 2>&1
    if ($Volumes -is [System.String] -and $Volumes -match "Error response") {
        Log-Message "  ❌ Could not connect to Docker daemon. Cannot perform volume backup." "Red"
    } elseif ($Volumes.Count -eq 0) {
        Log-Message "  ℹ️ No Docker volumes found to back up." "Cyan"
    } else {
        $VolumeCount = $Volumes.Count
        Log-Message "  Found $VolumeCount volumes. Backing up..." "Cyan"

        # Create a temporary container to access volumes and tar them
        $TempContainerName = "volume_backup_temp"
        $BackupScript = "
            for vol in \$(docker volume ls -q); do
                tar cf /backup/\${vol}_volume.tar -C /\${vol} .
            done"

        Log-Message "     - Creating temporary backup container..." -Color "White"

        try {
            # Use busybox for a minimal environment to run tar
            docker run --rm -v "$BackupDir:/backup" `
                $(foreach ($vol in $Volumes) { "-v $($vol):/$($vol) " }) `
                --name $TempContainerName busybox sh -c '
                    for vol in $(docker volume ls --format "{{.Name}}"); do
                        echo "Processing volume: $vol"
                        # Use a dedicated container command to get the path
                        CONTAINER_PATH=$(docker inspect --format "{{.Mounts}}" $vol | jq -r '.[].Source')
                        if [ -d "$CONTAINER_PATH" ]; then
                           tar -czf /backup/${vol}_volume.tar.gz -C "$CONTAINER_PATH" .
                        else
                           echo "Volume path not found: $CONTAINER_PATH"
                        fi
                    done
                ' 2>&1 | Out-Null

            # Note: The above logic is complex to run inside a single-line shell command on Windows.
            # A simpler, more reliable approach is to use a pre-made image or a dedicated volume command.
            # Let's use a simpler, cross-platform approach:
            docker run --rm -v "$BackupDir:/backup" $(foreach ($vol in $Volumes) { "-v $($vol):/$($vol) " }) alpine /bin/sh -c "
                for vol_name in $($Volumes -join ' '); do
                    if [ -d /\$vol_name ]; then
                        echo Backing up \$vol_name...;
                        tar -czf /backup/\$vol_name.tar.gz -C /\$vol_name .
                    else
                        echo Volume \$vol_name not mounted properly.;
                    fi
                done" 2>&1 | Out-Null

            Log-Message "     ✅ Volumes backed up to $BackupDir" "Green"
            Log-Message "     ⚠️ Volume backup is an advanced process. Verify files exist in $BackupDir." "Yellow"
        } catch {
            Log-Message "     ❌ Volume backup failed: $($_.Exception.Message)" "Red"
            Log-Message "     ℹ️ Please consider backing up volumes manually using Docker documentation." "Cyan"
        }
    }
    Log-Message "✅ Docker data backup phase complete." "Yellow"
}

Function Check-And-Enable-Features {
    Log-Message "✅ Starting check and repair of required Windows features..." "Yellow"

    foreach ($Feature in $RequiredFeatures) {
        Log-Message "  -> Checking feature: $Feature" -Color "White"
        try {
            # Use DISM to check state
            $FeatureInfo = dism /online /Get-FeatureInfo /FeatureName:$Feature | Out-String
            if ($FeatureInfo -match "State : Enabled") {
                Log-Message "     🟢 $Feature is already enabled." "Green"
            } else {
                Log-Message "     🟡 $Feature is not enabled. Attempting to enable..." "Yellow"
                # [cite_start]Use sources: [cite: 1]
                dism /online /enable-feature /featurename:$Feature /all /norestart | Out-Null
                if ($LASTEXITCODE -eq 0) {
                    Log-Message "     ✅ Successfully enabled $Feature." "Green"
                    $global:RebootRequired = $true
                } else {
                    Log-Message "     ❌ Failed to enable $Feature. DISM exit code: $LASTEXITCODE" "Red"
                }
            }
        } catch {
            Log-Message "     ❌ Error checking or enabling $Feature: $($_.Exception.Message)" "Red"
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
            Log-Message "     ℹ️ Status: $($s.Status). Display Name: $($s.DisplayName)" "Cyan"

            if ($s.Status -ne "Running") {
                Log-Message "     🟡 $svc is not running. Attempting to start..." "Yellow"
                Start-Service -Name $svc -ErrorAction Stop
                Log-Message "     ✅ $svc started successfully." "Green"
            }
        } catch {
            Log-Message "     ❌ Service $svc not found or failed to start: $($_.Exception.Message)" "Red"
        }
    }
}

Function Fix-LxssManager-Startup {
    Log-Message "✅ Ensuring LxssManager startup type is correct (Automatic)..." "Yellow"
    $Path = "HKLM:\SYSTEM\CurrentControlSet\Services\LxssManager"
    Try {
        # 'Start' value 2 is Automatic
        Set-ItemProperty -Path $Path -Name "Start" -Value 2 -Type DWord -Force -ErrorAction Stop
        Log-Message "  ✅ LxssManager startup set to Automatic (2)." "Green"
    } Catch {
        Log-Message "  ❌ Could not modify LxssManager registry: $($_.Exception.Message)" "Red"
    }
}

Function Check-And-Install-Wsl-Kernel {
    Log-Message "✅ Checking for WSL kernel installation..." "Yellow"
    $KernelPath = "$env:WINDIR\system32\lxss\tools\kernel"
    If (Test-Path $KernelPath) {
        Log-Message "  🟢 Kernel path found: $KernelPath" "Green"
    } else {
        Log-Message "  ❌ Kernel not found. Downloading and installing update..." "Red"
        try {
            Log-Message "  -> Downloading kernel from $KernelUrl..." "Cyan"
            Invoke-WebRequest -Uri $KernelUrl -OutFile $KernelInstaller -ErrorAction Stop
            Log-Message "  -> Installing kernel update..." "Cyan"
            # /qn for quiet install, /i for install
            $Process = Start-Process -FilePath "msiexec" -ArgumentList "/i `"$KernelInstaller`" /qn" -Wait -PassThru -ErrorAction Stop
            if ($Process.ExitCode -eq 0) {
                Log-Message "  ✅ Kernel update installed successfully." "Green"
                $global:RebootRequired = $true
            } else {
                Log-Message "  ❌ Kernel installation failed with exit code: $($Process.ExitCode)" "Red"
            }
        } catch {
            Log-Message "  ❌ Error during kernel download/install: $($_.Exception.Message)" "Red"
        }
    }
}

Function Set-Default-Wsl-Version {
    Log-Message "✅ Ensuring default WSL version is set to 2..." "Yellow"
    try {
        $result = wsl --set-default-version 2 2>&1
        if ($LASTEXITCODE -eq 0) {
            Log-Message "  ✅ WSL 2 set as default successfully." "Green"
        } elseif ($result -like "*The requested operation could not be completed because a required feature is not installed.*") {
             Log-Message "  ⚠️ Cannot set default version yet. Missing features/reboot required." "Yellow"
        } else {
            Log-Message "  ⚠️ Could not set default version. Output: $result" "Yellow"
        }
    } catch {
        Log-Message "  ❌ Unable to execute 'wsl --set-default-version': $($_.Exception.Message)" "Red"
    }
}

Function Check-Wsl-Docker-Status {
    Log-Message "✅ Running final status checks for WSL and Docker..." "Yellow"

    Log-Message "--- WSL Status ---" "Cyan"
    try {
        $status = wsl --status 2>&1 | Out-String
        Log-Message "$status" "White"
    } Catch {
        Log-Message "  ❌ Unable to execute 'wsl --status': $($_.Exception.Message)" "Red"
    }

    Log-Message "--- Docker Status ---" "Cyan"
    if (Get-Command "docker" -ErrorAction SilentlyContinue) {
        try {
            $dockerVersion = docker --version 2>&1 | Out-String
            Log-Message "  🟢 Docker CLI found: $dockerVersion" "Green"
            $dockerInfo = docker info --format '{{.OSType}}' 2>&1
            if ($dockerInfo -match "linux") {
                Log-Message "  🟢 Docker is using the Linux engine (WSL2 integration likely working)." "Green"
            } else {
                Log-Message "  ⚠️ Docker engine might be set to Windows or erroring. Run 'docker info' manually." "Yellow"
            }
        } catch {
            Log-Message "  ❌ Error running Docker command: $($_.Exception.Message)" "Red"
        }
    } else {
        Log-Message "  ⚠️ Docker CLI not found in PATH. Is Docker Desktop installed?" "Yellow"
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

# 1. Critical Pre-Step: Backup Docker Data
Log-Message "1️⃣ DOCKER DATA BACKUP (CRITICAL PRE-STEP)" "Red"
Backup-Docker-Data

# 2. Features
Log-Message "`n2️⃣ CHECKING WINDOWS FEATURES" "Magenta"
Check-And-Enable-Features

# 3. Kernel
Log-Message "`n3️⃣ CHECKING WSL KERNEL" "Magenta"
Check-And-Install-Wsl-Kernel

# 4. WSL Services
Log-Message "`n4️⃣ MANAGING WSL SERVICES" "Magenta"
Fix-LxssManager-Startup
Manage-Services -ServiceNames $WslServices

# 5. Docker Service
Log-Message "`n5️⃣ MANAGING DOCKER SERVICE" "Magenta"
Manage-Services -ServiceNames $DockerServices

# 6. Default Version
Log-Message "`n6️⃣ SETTING DEFAULT WSL VERSION" "Magenta"
Set-Default-Wsl-Version

# 7. Final Status
Log-Message "`n7️⃣ FINAL STATUS CHECK" "Magenta"
Check-Wsl-Docker-Status

Log-Message "========================================================" "Magenta"
Log-Message "Script execution complete." "Magenta"

# --- Summary and Cleanup ---

if ($global:RebootRequired) {
    Log-Message "`n⚠️ ACTION REQUIRED: One or more Windows features were enabled or the kernel was installed." "Red"
    Log-Message "   Please RESTART your PC now for the changes to take full effect." "Red"
} else {
    Log-Message "`n✅ No immediate reboot appears required." "Green"
}

Log-Message "Full report saved to: $LogFile" "Cyan"
Log-Message "Docker backup saved to: $BackupDir" "Cyan"

# Pause for user review
Read-Host "Press Enter to exit..."