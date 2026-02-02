
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

# Invokes the given script via PWSH remoting.
function Invoke-PwshCommand {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$VmName,

        [Parameter(Mandatory)]
        [string]$User,

        [Parameter(Mandatory, ParameterSetName = 'Array')] 
        [string[]]$Commands, 
        
        [Parameter(Mandatory, ParameterSetName = 'File')] 
        [string]$FilePath
    )
    switch ($PSCmdlet.ParameterSetName) { 
        'Array' { 
            $cmds = $Commands 
        } 
        'File' { 
            if (-not (Test-Path -Path $FilePath -PathType Leaf)) { 
                throw "File not found: $FilePath" 
            } 
            $cmds = Get-Content -Path $FilePath -Raw -ErrorAction Stop 
        } 
    }

    $session = New-VmSession -VmName $VmName -User $User
    try {
        Invoke-Command -Session $session -ScriptBlock { 
            param($cmds) 
            Invoke-Expression ($cmds -join "`n") 
        } -ArgumentList ($cmds)
    }
    finally {
        if ($session -and $session.State -eq 'Opened') {
            Remove-PSSession $session
        }
    }
}

# Uploads a script file via SSH and executes it
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
    
    # Generate random filename
    $extension = [IO.Path]::GetExtension($LocalPath)
    $random = -join ((48..57) + (97..122) | Get-Random -Count 12 | ForEach-Object { [char]$_ })
    $fileName = "script-$random$extension"

    # Determine remote home directory
    $remoteHome = if ($User -eq "root") { 
        "/root" 
    }
    else { 
        "/home/$User" 
    }
    $remotePath = "$remoteHome/$fileName"

    Write-Host ">>> Uploading $LocalPath to $remotePath"
    & scp $LocalPath "${User}@${VmName}:${remotePath}"

    Write-Host ">>> Executing remote script"
    & ssh $User@$VmName "bash $remotePath"
    & ssh $User@$VmName "rm -rf $remotePath"
}
