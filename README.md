
🔧** WSL2 and Docker Desktop Repair Script**
**https://github.com/jimmi0623/Docker-wsl2-tool**

This repository contains a comprehensive PowerShell script designed to diagnose and fix common startup errors for Windows Subsystem for Linux 2 (WSL2) and Docker Desktop on Windows 10 and 11.

The script, Docker-wsl2-tool, is to be run with Administrator privileges, offering robust checks, automatic fixes, detailed logging, and, critically, automated docker data backup (Volumes and Containers) before any system modifications.

💾 Files

    Docker-wsl2-tool: The main, comprehensive PowerShell repair and diagnostic script.

⚠️ Prerequisites

    Windows 10 (version 2004 or later) or Windows 11.

    Administrator privileges are required to run the script.

    An Internet connection is needed (to download the official WSL kernel update, if missing).

    Docker Desktop should be installed (even if it's currently failing to start).

🚀 How to Use

    Download the Docker-wsl2-tool file.

    Right-click on the script file and select "Run with PowerShell" or open a PowerShell window as Administrator and execute the script:
    PowerShell

    .\Docker-wsl2-tool

    The script will execute the steps sequentially, providing real-time status updates and logging all actions.

✨ Features and Actions

The script is structured to prioritize data safety and system integrity in the repair process.
Step	Action	Description
1. Data Backup (CRITICAL)	Backs up Docker Data	Creates a timestamped directory on the Desktop. Attempts to export all existing containers and backup all named volumes into compressed .tar.gz archives for recovery.
2. Features	Checks/Enables DISM features	Ensures core Windows features like Microsoft-Windows-Subsystem-Linux, VirtualMachinePlatform, Microsoft-Hyper-V-All, and HypervisorPlatform are enabled.
3. Kernel	Checks/Installs WSL Kernel	Downloads and installs the latest official WSL2 kernel update (wsl_update_x64.msi) if the kernel file is missing from the system path.
4. WSL Services	Manages WSL Services	Sets the LxssManager service to Automatic startup (registry value Start=2) and attempts to start LxssManager, vmcompute, and hns.
5. Docker Service	Manages Docker Service	Attempts to check and start the Docker service (com.docker.service).
6. Default Version	Sets Default WSL Version	Executes wsl --set-default-version 2 to ensure new WSL distributions use the required architecture.
7. Final Status	Checks WSL/Docker Status	Runs wsl --status and docker info to confirm the successful configuration and system state post-repair.

📊 Output and Logging

    Console Output: Provides step-by-step progress and status updates in real-time, using clear color coding (Green for success, Yellow for warnings, Red for errors).

    Log File: A comprehensive log file (wsl_docker_diagnostics_YYYYMMDD_HHMMSS.txt) is saved to your Desktop with a complete, timestamped record of all checks, actions, and errors.

    Backup Folder: The Docker container and volume backups are saved to a dedicated, timestamped folder named Docker_Backup_YYYYMMDD_HHMMSS on your Desktop.

❗ Important Note

If the script enables any new Windows features or installs the WSL kernel update (Steps 2 or 3), it will notify you that a system restart is mandatory.

Always restart your PC immediately after the script completes if it reports that a reboot is required for the changes to fully integrate and for WSL/Docker to function correctly.

🤝 Contribution

Suggestions, issues, and pull requests are welcome! Feel free to help improve this utility. 
**https://github.com/jimmi0623/Docker-wsl2-tool**
