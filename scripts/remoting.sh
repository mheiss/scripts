if ! command -v pwsh >/dev/null 2>&1; then
    # Download the Microsoft repository GPG keys
    source /etc/os-release
    wget -q https://packages.microsoft.com/config/debian/$VERSION_ID/packages-microsoft-prod.deb
        
    # Register the Microsoft repository GPG keys
    dpkg -i packages-microsoft-prod.deb
    rm packages-microsoft-prod.deb
        
    # Update the list of packages after we added packages.microsoft.com
    apt-get update && apt-get install -y powershell
        
    #Start a PowerShell session on Linux
    pwsh -NoLogo -NoProfile -Command "Install-Module -Name Microsoft.PowerShell.RemotingTools -Force -Scope CurrentUser"
        
    # Restart daemon
    systemctl restart ssh
else
    echo "PowerShell already installed."
fi

# Ensure subsystem is configured
if ! grep -q "^Subsystem powershell" /etc/ssh/sshd_config; then
    echo "Configuring PowerShell SSH subsystem..."
    echo "Subsystem powershell /usr/bin/pwsh -sshs -NoLogo -NoProfile" >> /etc/ssh/sshd_config
else
    echo "PowerShell subsystem already configured."
fi

