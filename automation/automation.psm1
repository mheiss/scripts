
#region Writes out a nice header 
function Write-Header {
    param(
        [string]$header
    )
    for ($i = 0; $i -le $header.Length; $i++) {
        if ($i -le $header.Length - 1) {
            Write-Host -NoNewline "-"
        }
        else {
            Write-Host "-"
        }
    }
    Write-Host $header
    for ($i = 0; $i -le $header.Length; $i++) {
        if ($i -le $header.Length - 1) {
            Write-Host -NoNewline "-"
        }
        else {
            Write-Host "-"
        }
    }
}
#endregion

# Reads the list of VMs from the file
# If the entry already contains a dot, assume it's a full hostname
function Get-VmList {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Path,

        [string]$Domain = "heiss.lan"
    )

    if (-not (Test-Path $Path)) {
        throw "VM list file not found: $Path"
    }

    Get-Content $Path |
    ForEach-Object { $_.Trim() } |
    Where-Object {
        $_ -ne "" -and
        -not $_.StartsWith("#")
    }
    ForEach-Object { 
        if ($_.Contains(".")) { 
            $_ 
        }
        else { 
            "$_.$Domain" 
        } 
    }
}
#endregion

#region New Session
function New-VmSession {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$VmName,

        [Parameter(Mandatory)]
        [string]$User
    )

    New-PSSession -HostName $VmName -UserName $User
}
#endregion

#region Invoke command
function Invoke-VmCommand {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$VmName,

        [Parameter(Mandatory)]
        [string]$User,

        [Parameter(Mandatory)]
        [string[]]$Commands
    )

    $session = New-VmSession -VmName $VmName -User $User

    try {
        Invoke-Command -Session $session -ScriptBlock {
            param($cmds)
            foreach ($cmd in $cmds) {
                Write-Host "[$env:COMPUTERNAME] >>> $cmd"
                Invoke-Expression $cmd
            }
        } -ArgumentList ($Commands)
    }
    finally {
        if ($session) {
            Remove-PSSession $session
        }
    }
}
#endregion

#region VM remoting
function Enable-VmRemoting {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$VmName,

        [Parameter(Mandatory)]
        [string]$User
    )

    $commands = @(
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
         systemctl restart sshd || systemctl restart ssh'
    )

    Invoke-VmCommand -VmName $VmName -User $User -Commands $commands
}
#endregion

#region Update
function Update-Vm {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$VmName,

        [Parameter(Mandatory)]
        [string]$User
    )

    $commands = @(
        'export DEBIAN_FRONTEND=noninteractive',
        'apt-get update -y',
        'apt-get upgrade -y',
        'if [ -f ./update.ps1 ]; then pwsh ./update.ps1; fi'
    )

    Invoke-VmCommand -VmName $VmName -User $User -Commands $commands
}
#endregion

Export-ModuleMember -Function Get-VmList, New-VmSession, Invoke-VmCommand, Enable-VmRemoting, Update-Vm, Write-Header
