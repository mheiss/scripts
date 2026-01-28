. ./utils.ps1

function ConfigureVM {
    param(
        [string]$VmName
    )
    Write-Host "------------------------------"
    Write-Host "Configuring $VmName.heiss.lan"
    Write-Host "------------------------------"
    $session = New-PSSession -HostName "$VmName.heiss.lan" -UserName "root" -ErrorAction SilentlyContinue

    if (-not $session) {
        Write-Host "SSH connection failed for $VmName"
        return
    }

    try {
        Invoke-Command -Session $session -ScriptBlock {
            param($cmds)
            foreach ($cmd in $cmds) {
                echo ">>> Running: $cmd"
                bash -c "$cmd"
            }
        } -ArgumentList ($remoteCommands)
    }
    finally {
        Remove-PSSession $session
    }

    Write-Host "Done with $VmName"
}

# Commands to configure PS Remoting on each VM
$remoteCommands = @(
    # Install PowerShell if missing
    'if ! command -v pwsh >/dev/null 2>&1; then
         echo "Installing PowerShell..."
         apt-get update -y
         apt-get install -y wget apt-transport-https software-properties-common
         wget -q https://packages.microsoft.com/config/debian/12/packages-microsoft-prod.deb -O /tmp/packages-microsoft-prod.deb
         dpkg -i /tmp/packages-microsoft-prod.deb
         apt-get update -y
         apt-get install -y powershell
     else
         echo "PowerShell already installed"
     fi',

    # Ensure subsystem is configured
    'if ! grep -q "^Subsystem powershell" /etc/ssh/sshd_config; then
         echo "Configuring PowerShell SSH subsystem..."
         echo "Subsystem powershell /usr/bin/pwsh -sshs -NoLogo -NoProfile" >> /etc/ssh/sshd_config
     else
         echo "PowerShell subsystem already configured"
     fi',

    # Restart SSH
    'echo "Restarting SSH..."
     systemctl restart sshd || systemctl restart ssh',

    # Verify subsystem
    'echo "Testing subsystem..."
     sshd -T | grep subsystem'
)

foreach ($vm in Get-VmList) {
    Configure-VM $vm
}
