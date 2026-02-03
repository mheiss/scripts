
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

        [Parameter(Mandatory)]
        [string]$Domain
    )
    if (-not (Test-Path $Path)) {
        throw "VM list file not found: $Path"
    }

    Get-Content $Path | 
    ForEach-Object { 
        $_.Trim() 
    } |
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

# Starts a new power shell session.
# Makes specific functions available in the remote side. 
function New-VmSession {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$VmName,

        [Parameter(Mandatory)]
        [string]$User
    )

    try {
        $session = New-PSSession -HostName $VmName -UserName $User
        Import-FunctionsToRemote -Session $session -Commands @("Update-App")
        return $session;
    }
    catch {
        Write-Error "Failed to create VM session: $_" return $null
    }
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
        Invoke-Command -Session $session -ArgumentList $cmds -ScriptBlock { 
            param($cmds) 
            Invoke-Expression ($cmds -join "`n") 
        } 
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
    $random = New-Guid
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

# Updates an existing application hosted on GitHub
function Update-App {
    param(
        [Parameter(Mandatory)]
        [string]$Repo,
        [Parameter(Mandatory)]
        [string]$AssetName,
        [Parameter(Mandatory)]
        [string]$BaseDir,
        [Parameter(Mandatory)]
        [string]$AppName,
        [Parameter(Mandatory)]
        [string]$ServiceName,
        [Parameter(Mandatory)]
        [string]$SymlinkPath
    )
    Write-Host "Checking for updates for $AppName..."
    
    $ReleaseEndpoint = "https://api.github.com/repos/$Repo/releases/latest"
    $Response = Invoke-RestMethod -Uri $ReleaseEndpoint -Headers @{ "User-Agent" = "PowerShell" }
    
    $Tag = $Response.tag_name
    $Version = $Tag.TrimStart("v")
    $TargetDir = Join-Path $BaseDir $Version

    # Exit early if already downloaded
    if (Test-Path $TargetDir) {
        Write-Host "Latest release $Tag is already installed. Nothing to do."
        return
    }

    Write-Host "Update available: $Version."
    New-Item -ItemType Directory -Path $TargetDir | Out-Null

    # Select the Linux ZIP asset
    $Asset = $Response.assets | Where-Object { $_.name -match $AssetName }
    if (-not $Asset) {
        Write-Host "Asset $AssetName not found!"
        return
    }

    $DownloadUrl = $Asset.browser_download_url
    $FileName = $Asset.name
    $FilePath = Join-Path $TargetDir $FileName

    Write-Host "Downloading $FileName..."
    Invoke-WebRequest -Uri $DownloadUrl -OutFile $FilePath

    # Unpack if ZIP 
    if ($FileName -match "\.zip$") { 
        Write-Host "Extracting ZIP..." 
        Expand-Archive -Path $FilePath -DestinationPath $TargetDir -Force 
    }

    # Update symlink
    $AppPath = Join-Path $TargetDir $AppName
    Write-Host "Updating symlink $AppPath -> $SymlinkPath"
    bash -c "chmod +x '$AppPath'"
    bash -c "ln -s -f '$AppPath' '$SymlinkPath'"

    # Restart service
    Write-Host "Restarting service: $ServiceName"
    bash -c "systemctl restart '$ServiceName'"
    bash -c "systemctl status '$ServiceName' --no-pager"
}

# Makes certain commands available to the remote session
function Import-FunctionsToRemote {
    param(
        [Parameter(Mandatory)]
        [System.Management.Automation.Runspaces.PSSession]$Session,

        [Parameter(Mandatory)] 
        [string[]]$Commands
    )

    $definition = Get-Content "./Automation/Automation.psm1" -Raw 
    Invoke-Command -Session $Session -ArgumentList $definition -ScriptBlock { 
        param($def) 
        Invoke-Expression $def 
    }
}

# Reloads this module
function Update-AutomationModule {
    $module = "Automation"
    Remove-Module $module -ErrorAction SilentlyContinue
    Import-Module "./$module" -Force

    $commands = (Get-Command -Module $module -CommandType Function).Name -join ", "
    Write-Host "Automation module loaded. Available commands: $commands"
}
