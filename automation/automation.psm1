
# Prints out a nice header
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
    } |
    ForEach-Object { 
        if ($_.Contains(".")) { 
            $_ 
        }
        else { 
            "$_.$Domain" 
        } 
    }
}

# Starts a new power shell session
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

# Invokes the given command via PWSH remoting.
function Invoke-PwshCommand {
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
                Write-Host ">>> $cmd"
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

# Invokes the given file via SSH
function Invoke-SshScript {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$VmName,

        [Parameter(Mandatory)]
        [string]$User,

        [Parameter(Mandatory)]
        [string]$LocalPath
    )

    if (-not (Test-Path $LocalPath)) {
        throw "Local file not found: $LocalPath"
    }

    # Extract extension (.ps1, .sh, etc.)
    $extension = [IO.Path]::GetExtension($LocalPath)

    # Generate random filename
    $random = -join ((48..57) + (97..122) | Get-Random -Count 12 | ForEach-Object {[char]$_})
    $fileName = "script-$random$extension"

    # Determine remote home directory
    $remoteHome = if ($User -eq "root") { 
        "/root" 
    } else { 
        "/home/$User" 
    }

    # Final remote path
    $remotePath = "$remoteHome/$fileName"

    Write-Host ">>> Uploading $LocalPath to $remotePath"
    & scp $LocalPath "${User}@${VmName}:${remotePath}"

    Write-Host ">>> Executing remote script"
    & ssh $User@$VmName "bash $remotePath"
    & ssh $User@$VmName "rm -rf $remotePath"

}

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

    Invoke-PwshCommand -VmName $VmName -User $User -Commands $commands
}
