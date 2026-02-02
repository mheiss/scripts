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
fi

# Enable authentication via public key
SSH_CONFIG_FILE=/etc/ssh/sshd_config
sed -i 's/^#[[:space:]]*PubkeyAuthentication[[:space:]]\+yes$/PubkeyAuthentication yes/' "$SSH_CONFIG_FILE"

# Ensure subsystem is configured
SUBSYSTEM="Subsystem powershell /usr/bin/pwsh -sshs -NoLogo -NoProfile"
grep -qxF "$SUBSYSTEM" "$SSH_CONFIG_FILE" || sed -i "/^Subsystem[[:space:]]\+sftp[[:space:]]\+/a $SUBSYSTEM" "$SSH_CONFIG_FILE"

# Restart daemon
systemctl restart ssh