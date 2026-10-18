
<#
.SYNOPSIS
Prints a heading between dashed separator lines.

.DESCRIPTION
Writes the supplied heading and matching separator lines directly to the host.
Does not return pipeline output.
#>
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

<#
.SYNOPSIS
Reads VM hostnames and the default domain from an inventory file.

.DESCRIPTION
Ignores blank lines and comments, then appends the domain from the domain=<name>
entry to VM names without a dot. Returns names containing a dot unchanged.
Throws if the file is missing or does not define a default domain.
#>
function Get-VmList {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Path
    )
    if (-not (Test-Path $Path)) {
        throw "VM list file not found: $Path"
    }

    $entries = Get-Content $Path | 
    ForEach-Object { 
        $_.Trim() 
    } |
    Where-Object {
        $_ -ne "" -and
        -not $_.StartsWith("#")
    }

    $domain = $entries |
    Where-Object {
        $_ -match '^domain\s*='
    } |
    ForEach-Object {
        ($_ -split '=', 2)[1].Trim()
    } |
    Select-Object -First 1

    if (-not $domain) {
        throw "VM list file does not contain a domain=<name> entry: $Path"
    }

    $entries |
    Where-Object {
        $_ -notmatch '^domain\s*='
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

<#
.SYNOPSIS
Creates a PowerShell remoting session to a VM over SSH.

.DESCRIPTION
Connects to the supplied VM as the specified user and imports the automation
functions into the remote session. Returns the session on success and writes
an error if session creation or function import fails.
#>
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

<#
.SYNOPSIS
Runs commands or a local script on a VM through PowerShell remoting.

.DESCRIPTION
Accepts either an array of commands or a local script path. Creates an SSH-backed
PowerShell session with the automation functions loaded, executes the supplied
content on the VM, and removes the session afterward. Throws if the script file
does not exist.
#>
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

<#
.SYNOPSIS
Uploads a local shell script to a VM and executes it over SSH.

.DESCRIPTION
Copies the script with scp to a randomly named file in the remote user's home
directory, runs it with bash over SSH, then issues a command to delete the copy.
Uses /root for root and /home/<user> for other accounts. Throws if the local file
does not exist.
#>
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

<#
.SYNOPSIS
Removes old application releases while retaining two selected versions.

.DESCRIPTION
Keeps the directory matching LatestVersion and the most recently modified other
release directory. Recursively deletes the remaining release directories while
excluding symbolic links and other reparse points. Returns without changes if
the base directory does not exist.
#>
function Remove-OldAppVersion {
    param(
        [Parameter(Mandatory)]
        [string]$BaseDir,

        [Parameter(Mandatory)]
        [string]$LatestVersion
    )

    if (-not (Test-Path -Path $BaseDir -PathType Container)) {
        return
    }

    $VersionDirs = Get-ChildItem -Path $BaseDir -Directory |
    Where-Object { -not ($_.Attributes -band [IO.FileAttributes]::ReparsePoint) } |
    Sort-Object -Property LastWriteTime -Descending

    $VersionsToKeep = @($VersionDirs |
    Where-Object { $_.Name -eq $LatestVersion } |
    Select-Object -First 1)

    $VersionsToKeep += @($VersionDirs |
    Where-Object { $_.Name -ne $LatestVersion } |
    Select-Object -First 1)

    $VersionDirs |
    Where-Object { $_.FullName -notin $VersionsToKeep.FullName } |
    ForEach-Object {
        Write-Host "Removing old release: $($_.FullName)"
        Remove-Item -Path $_.FullName -Recurse -Force
    }
}

<#
.SYNOPSIS
Waits for an HTTP resource to return a successful status code.

.DESCRIPTION
Returns true on HTTP 2xx, or warns and returns false when the timeout expires.
Redirects are not followed so a login page cannot indicate application readiness.
#>
function Wait-For-Resource {
    param(
        [Parameter(Mandatory)]
        [ValidateScript({ $_.IsAbsoluteUri -and $_.Scheme -in @('http', 'https') })]
        [uri]$Uri,

        [ValidateRange(1, 2147483647)]
        [int]$TimeoutSeconds = 120,

        [ValidateRange(1, 2147483647)]
        [int]$RetryIntervalSeconds = 2,

        [ValidateRange(1, 2147483647)]
        [int]$RequestTimeoutSeconds = 5
    )

    $Timer = [System.Diagnostics.Stopwatch]::StartNew()
    while ($Timer.Elapsed.TotalSeconds -lt $TimeoutSeconds) {
        $RemainingSeconds = $TimeoutSeconds - $Timer.Elapsed.TotalSeconds
        $AttemptTimeout = [int][Math]::Ceiling([Math]::Min($RequestTimeoutSeconds, $RemainingSeconds))
        try {
            $Response = Invoke-WebRequest -Uri $Uri -NoProxy -UseBasicParsing -MaximumRedirection 0 -TimeoutSec $AttemptTimeout -ErrorAction Stop
            if ($Response.StatusCode -ge 200 -and $Response.StatusCode -lt 300) {
                return $true
            }
        }
        catch {
        }

        $RemainingMilliseconds = ($TimeoutSeconds - $Timer.Elapsed.TotalSeconds) * 1000
        if ($RemainingMilliseconds -gt 0) {
            Start-Sleep -Milliseconds ([int][Math]::Min($RetryIntervalSeconds * 1000.0, $RemainingMilliseconds))
        }
    }

    Write-Warning "HTTP resource '$Uri' did not become available within $TimeoutSeconds seconds."
    return $false
}

<#
.SYNOPSIS
Requests a Fully Kiosk Browser display to refresh the smart-home dashboard.

.DESCRIPTION
Reads FULLY_URL and FULLY_PASSWORD from a local env-style secrets file, then calls
the Fully remote admin API to clear the cache, reload the start URL, and turn the
screen on. The secrets file is expected to exist on the target VM where this
command runs, and FULLY_URL must resolve from that VM.

.PARAMETER SecretFile
Path to an env-style file containing FULLY_URL and FULLY_PASSWORD. Defaults to
/etc/dashboard/fully.env.

.EXAMPLE
Update-FullyDisplay -SecretFile "/etc/dashboard/fully.env"
#>
function Update-FullyDisplay {
    param(
        [string]$SecretFile = "/etc/dashboard/fully.env"
    )

    if (-not (Test-Path $SecretFile)) {
        Write-Warning "Fully display config not found: $SecretFile"
        return
    }

    Get-Content $SecretFile |
    Where-Object { $_ -match '^\s*[^#][^=]+=' } |
    ForEach-Object {
        $Name, $Value = $_ -split '=', 2
        Set-Item -Path "Env:$($Name.Trim())" -Value $Value.Trim()
    }

    if (-not $env:FULLY_URL -or -not $env:FULLY_PASSWORD) {
        Write-Warning "Fully display config must define FULLY_URL and FULLY_PASSWORD in $SecretFile."
        return
    }

    try {
        $FullyUri = [uri]$env:FULLY_URL
    }
    catch {
        Write-Warning "FULLY_URL is not a valid URL in ${SecretFile}: $env:FULLY_URL"
        return
    }

    try {
        $null = [System.Net.Dns]::GetHostAddresses($FullyUri.Host)
    }
    catch {
        Write-Warning "Fully display host '$($FullyUri.Host)' could not be resolved from this VM. Check DNS or use an IP address in FULLY_URL."
        return
    }

    $FullyUrl = $FullyUri.AbsoluteUri.TrimEnd("/")
    $FullyPassword = [uri]::EscapeDataString($env:FULLY_PASSWORD)

    foreach ($Command in @("clearCache", "loadStartUrl", "screenOn")) {
        try {
            $null = Invoke-WebRequest -Uri "$FullyUrl/?cmd=$Command&password=$FullyPassword" -NoProxy -ErrorAction Stop
        }
        catch {
            Write-Warning "Fully display command '$Command' failed for host '$($FullyUri.Host)': $($_.Exception.Message)"
            return
        }
    }

    Write-Output "Fully Smart-Home display updated."
}

<#
.SYNOPSIS
Updates an installed application from its latest GitHub release.

.DESCRIPTION
Selects a release asset by name pattern, downloads it into a versioned directory,
and extracts ZIP or TAR.GZ archives. Updates the executable or directory symlink,
restarts the systemd service, prints its status, and removes old releases.
Skips installation when the target version directory already exists, but still
cleans up old releases. Optional User and Group values must be supplied together
and set ownership of the downloaded release. Requires Linux tools through bash.
#>
function Update-App {
    param(
        [Parameter(Mandatory)]
        [string]$Repo,
        [Parameter(Mandatory)]
        [string]$AssetName,
        [Parameter(Mandatory)]
        [string]$BaseDir,
        [Parameter(Mandatory)]
        [string]$ServiceName,
        [Parameter(Mandatory)]
        [string]$SymlinkPath,
        [string]$User,
        [string]$Group
    )
    if (($User -and -not $Group) -or ($Group -and -not $User)) {
        throw "User and Group must be specified together."
    }

    Write-Host "Checking for updates for $Repo..."
    
    $ReleaseEndpoint = "https://api.github.com/repos/$Repo/releases/latest"
    $Response = Invoke-RestMethod -Uri $ReleaseEndpoint -Headers @{ "User-Agent" = "PowerShell" }
    
    $Tag = $Response.tag_name
    $Version = $Tag.TrimStart("v")
    $TargetDir = Join-Path $BaseDir $Version

    # Exit early if already downloaded
    if (Test-Path $TargetDir) {
        Write-Host "Latest release $Tag is already installed. Nothing to do."
        Remove-OldAppVersion -BaseDir $BaseDir -LatestVersion $Version
        return
    }

    Write-Host "Update available: $Version."
    Write-Host "Release notes: $($Response.html_url)"
    
    # Select the desired asset
    $Asset = $Response.assets | Where-Object { $_.name -match $AssetName }
    if (-not ($Asset -and 
            $Asset.PSObject.Properties.Match('browser_download_url') -and 
            $Asset.PSObject.Properties.Match('name'))) {
        Write-Host "Asset $AssetName not found!"
        return
    }
    
    $DownloadUrl = $Asset.browser_download_url
    $FileName = $Asset.name
    $FilePath = Join-Path $TargetDir $FileName
    
    Write-Host "Downloading $FileName..."
    New-Item -ItemType Directory -Path $TargetDir | Out-Null
    Invoke-WebRequest -Uri $DownloadUrl -OutFile $FilePath

    # Exit if downloading failed
    if (-not (Test-Path $FilePath)) {
        Write-Host "Downloading $DownloadUrl failed!"
        Remove-Item -Path $TargetDir -Recurse -Force
        return
    }

    # Unpack if TAR.GZ
    if ($FileName -imatch "\.tar\.gz$") { 
        Write-Host "Extracting archive to $TargetDir..." 
        bash -c "tar -xzf '$FilePath' -C '$TargetDir'"
        Remove-Item $FilePath
    }

    # Unpack if ZIP 
    if ($FileName -imatch "\.zip$") { 
        Write-Host "Extracting archive to $TargetDir..." 
        Expand-Archive -Path $FilePath -DestinationPath $TargetDir -Force 
        Remove-Item $FilePath
    }

    # Detect if the archive extracted into a single top-level directory
    $Children = Get-ChildItem -Path $TargetDir
    if ($Children.Count -eq 1 -and $Children[0].PSIsContainer) {
        $InnerDir = $Children[0].FullName
    
        Move-Item -Path "$InnerDir\*" -Destination $TargetDir
        Remove-Item -Path $InnerDir -Recurse -Force
    }

    # Detect app type by inspecting extracted directory
    $Children = Get-ChildItem -Path $TargetDir -Force
    if ($Children.Count -eq 1 -and -not $Children[0].PSIsContainer) {
        $SymlinkTarget = $Children[0].FullName
        Write-Host "Detected single-file application: $SymlinkTarget"
        bash -c "chmod +x '$SymlinkTarget'"
    }
    else {
        $SymlinkTarget = $TargetDir
        Write-Host "Detected directory-based application: $SymlinkTarget"
    }

    if ($User -and $Group) {
        Write-Host "Setting ownership of $TargetDir to ${User}:${Group}"
        bash -c "chown -R '${User}:${Group}' '$TargetDir'"
    }

    # Update symlink
    Write-Host "Updating symlink $SymlinkPath -> $SymlinkTarget"
    bash -c "ln -sfn '$SymlinkTarget' '$SymlinkPath'"

    # Restart service
    Write-Host "Restarting service: $ServiceName"
    bash -c "systemctl restart '$ServiceName'"
    bash -c "systemctl status '$ServiceName' --no-pager"

    Remove-OldAppVersion -BaseDir $BaseDir -LatestVersion $Version
}

<#
.SYNOPSIS
Loads the local automation functions into an existing remote session.

.DESCRIPTION
Reads ./Automation/Automation.psm1 relative to the current local directory and
evaluates its contents in the supplied PowerShell session. Loads the whole
module's function definitions; the required Commands argument is currently not
used to filter which functions are imported.
#>
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

<#
.SYNOPSIS
Reloads the local Automation module for interactive development.

.DESCRIPTION
Removes the loaded Automation module if present, then imports ./Automation with
Force relative to the current directory. Prints the available module function
names to the host after importing.
#>
function Update-AutomationModule {
    $module = "Automation"
    Remove-Module $module -ErrorAction SilentlyContinue
    Import-Module "./$module" -Force

    $commands = (Get-Command -Module $module -CommandType Function).Name -join ", "
    Write-Host "Automation module loaded. Available commands: $commands"
}
