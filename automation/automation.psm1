
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
Reads VM records from directories in the VM folder.

.DESCRIPTION
Returns each VM's folder name, hostname, and absolute update-script path.
Appends the supplied domain to names without a dot, leaving full hostnames
unchanged. Throws if the VM folder does not exist.
#>
function Get-VmList {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Path,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$Domain
    )
    if (-not (Test-Path -LiteralPath $Path -PathType Container)) {
        throw "VM folder not found: $Path"
    }

    Get-ChildItem -LiteralPath $Path -Directory -ErrorAction Stop |
    Sort-Object Name |
    ForEach-Object {
        $hostName = if ($_.Name.Contains(".")) {
            $_.Name
        }
        else {
            "$($_.Name).$Domain"
        }

        [pscustomobject]@{
            Name = $_.Name
            HostName = $hostName
            UpdateScript = Join-Path $_.FullName 'update.ps1'
        }
    }
}

<#
.SYNOPSIS
Updates installed Debian packages.

.DESCRIPTION
Runs apt-get update and upgrade all installed packages.
Throws if either command fails.
#>
function Update-Apt {
    Write-Host "Updating installed packages."

    bash -c "export LC_ALL=C DEBIAN_FRONTEND=noninteractive && apt-get update -y"
    if ($LASTEXITCODE -ne 0) {
        throw "apt-get update failed with exit code $LASTEXITCODE."
    }
    bash -c "export LC_ALL=C DEBIAN_FRONTEND=noninteractive && apt-get upgrade -y"
    if ($LASTEXITCODE -ne 0) {
        throw "apt-get upgrade failed with exit code $LASTEXITCODE."
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
        Import-FunctionsToRemote -Session $session -Commands @("Update-App", "Update-Apt")
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
            Invoke-Expression ($cmds -join "`n") 6>&1 |
            ForEach-Object {
                if ($_ -is [System.Management.Automation.InformationRecord]) {
                    [string]$_.MessageData
                }
                else {
                    $_
                }
            }
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
function Wait-Resource {
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
    if (Test-Path $SymlinkPath) {
        $InstalledPath = bash -c "readlink -f '$SymlinkPath'"
        if ($LASTEXITCODE -eq 0 -and $InstalledPath) {
            $InstalledVersion = [System.IO.Path]::GetRelativePath($BaseDir, [string]$InstalledPath).Split('/')[0]
            Write-Host "Installed version: $InstalledVersion"
        }
    }
    
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
Reads automation.psm1 from the local module directory and
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

    $definition = Get-Content "$PSScriptRoot/automation.psm1" -Raw
    Invoke-Command -Session $Session -ArgumentList $definition -ScriptBlock { 
        param($def) 
        Invoke-Expression $def 
    }
}

<#
.SYNOPSIS
Runs a VM update script and returns structured summary records.

.DESCRIPTION
Writes an Updating heading, then runs the local script on the VM through
Invoke-PwshCommand. Captures all redirected output streams while displaying
progress on the host, using MessageData for information records.
Catches terminating execution errors, displays a failure message, and includes
the error in the captured output instead of rethrowing it. Returns the results
from Get-UpdateSummary in Custom mode, passing the failure flag when an error
was caught. Does not print the final combined update summary.

.PARAMETER VmName
VM hostname used for the remote connection and attached to summary records.

.PARAMETER User
SSH username used for PowerShell remoting to the VM.

.PARAMETER FilePath
Path to the local PowerShell update script. Its contents are sent to and
executed on the VM; this is not a path on the remote machine.

.OUTPUTS
System.Management.Automation.PSCustomObject
Update result records returned by Get-UpdateSummary, including failure status
when execution fails. Raw progress output is displayed on the host, not returned.

.EXAMPLE
$summary = Invoke-VmUpdate -VmName 'dashboard.home.arpa' -User 'root' -FilePath './vms/dashboard/update.ps1'

Runs the dashboard update and captures its structured results in $summary.
#>
function Invoke-VmUpdate {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$VmName,

        [Parameter(Mandatory)]
        [string]$User,

        [Parameter(Mandatory)]
        [string]$FilePath
    )

    Write-Header "Updating $VmName"
    $output = [System.Collections.Generic.List[object]]::new()
    $failed = $false
    try {
        Invoke-PwshCommand -VmName $VmName -User $User -FilePath $FilePath -ErrorAction Stop *>&1 |
        ForEach-Object {
            $output.Add($_)
            if ($_ -is [System.Management.Automation.InformationRecord]) {
                [string]$_.MessageData | Out-Host
            }
            else {
                $_ | Out-Host
            }
        }
    }
    catch {
        $failed = $true
        $output.Add($_)
        Write-Host "Update failed for ${VmName}: $_" -ForegroundColor Red
    }

    Get-UpdateSummary -VmName $VmName -Type Custom -Output $output.ToArray() -Failed:$failed
}

<#
.SYNOPSIS
Parses captured VM update output into structured result records.

.DESCRIPTION
Recognizes English APT package counts and unpacking messages, application release
versions and links, and systemd service status. Errors and warnings update the
current summary record and append diagnostic text to its Details property.
Unrecognized lines are ignored. If parsing creates no records, returns an Unknown
result with a no-recognized-result message. Does not execute updates or print output.

.PARAMETER VmName
VM hostname attached to every returned result.

.PARAMETER Type
Parsing mode: Apt or Custom. Apt starts with an apt-get summary record and parses
package updates. Custom recognizes application sections beginning with
"Checking for updates for <repository>..." and switches to APT parsing on the exact
line "Updating installed packages". It can therefore parse mixed script output.

.PARAMETER Output
Captured output records to parse. Uses MessageData for InformationRecord objects
and string representations for other records, splitting multiline text into lines.
ErrorRecord and WarningRecord objects also determine failure and warning status.
Accepts an empty collection and defaults to an empty array.

.PARAMETER Failed
Marks the current summary record as Failed after parsing, for example when the
caller caught a terminating error. Does not mark every returned record as failed.

.OUTPUTS
System.Management.Automation.PSCustomObject
Records with VM, Type, Application, Status, Version, and Details properties.
Application and individual package records also include PreviousVersion and
Changelog. Status is Unknown, Updated, Up to date, Warning, or Failed.

.EXAMPLE
Get-UpdateSummary -VmName 'dashboard.home.arpa' -Type Custom -Output $output

Parses captured output containing application updates and recognized APT sections.

.EXAMPLE
Get-UpdateSummary -VmName 'dashboard.home.arpa' -Type Apt -Output $output -Failed

Parses captured APT output and marks its current summary record as failed.
#>
function Get-UpdateSummary {
    param(
        [Parameter(Mandatory)]
        [string]$VmName,

        [Parameter(Mandatory)]
        [ValidateSet('Apt', 'Custom')]
        [string]$Type,

        [AllowEmptyCollection()]
        [object[]]$Output = @(),

        [switch]$Failed
    )

    $Rows = [System.Collections.Generic.List[object]]::new()
    $Current = $null
    if ($Type -eq 'Apt') {
        $Current = [pscustomobject]@{ VM = $VmName; Type = $Type; Application = 'apt-get'; Status = 'Unknown'; Version = ''; Details = '' }
        $Rows.Add($Current)
    }

    foreach ($Record in $Output) {
        $Text = if ($Record -is [System.Management.Automation.InformationRecord]) {
            [string]$Record.MessageData
        }
        else {
            [string]$Record
        }
        foreach ($Line in ($Text -split '\r?\n')) {
            if ($Type -eq 'Custom' -and $Line -eq 'Updating installed packages') {
                $Current = [pscustomobject]@{ VM = $VmName; Type = 'Apt'; Application = 'apt-get'; Status = 'Unknown'; Version = ''; Details = '' }
                $Rows.Add($Current)
            }
            if ($Type -eq 'Custom' -and $Line -match '^Checking for updates for (.+)\.\.\.$') {
                $Current = [pscustomobject]@{ VM = $VmName; Type = $Type; Application = $Matches[1]; Status = 'Unknown'; Version = ''; PreviousVersion = 'not installed'; Changelog = ''; Details = '' }
                $Rows.Add($Current)
            }

            if ($Record -is [System.Management.Automation.ErrorRecord] -or $Line -match '^(E:|Asset .+ not found!|Downloading .+ failed!)') {
                if (-not $Current) {
                    $Current = [pscustomobject]@{ VM = $VmName; Type = $Type; Application = 'Custom script'; Status = 'Unknown'; Version = ''; Details = '' }
                    $Rows.Add($Current)
                }
                $Current.Status = 'Failed'
                $Current.Details += "$Line; "
            }
            elseif ($Current -and $Current.Type -eq 'Apt') {
                if ($Line -match '^(\d+) upgraded, (\d+) newly installed, (\d+) to remove and (\d+) not upgraded\.') {
                    if ($Current.Status -notin @('Failed', 'Warning')) {
                        $Current.Status = if ([int]$Matches[1] + [int]$Matches[2] + [int]$Matches[3] -gt 0) { 'Updated' } else { 'Up to date' }
                    }
                    $Current.Details += "$Line; "
                }
                elseif ($Line -match '^Unpacking (\S+) \(([^)]+)\)(?: over \(([^)]+)\))?') {
                    $Rows.Add([pscustomobject]@{
                        VM = $VmName; Type = 'Apt'; Application = $Matches[1]; Status = 'Updated'
                        Version = $Matches[2]; PreviousVersion = $(if ($Matches[3]) { $Matches[3] } else { 'not installed' })
                        Changelog = ''; Details = ''
                    })
                }
            }
            elseif ($Current) {
                if ($Line -match '^Latest release (.+) is already installed\.') {
                    $Current.Version = $Matches[1]
                    if ($Current.Status -notin @('Failed', 'Warning')) { $Current.Status = 'Up to date' }
                }
                elseif ($Line -match '^Update available: (.+)\.$') {
                    $Current.Version = $Matches[1]
                }
                elseif ($Line -match '^Installed version: (.+)$') {
                    $Current.PreviousVersion = $Matches[1]
                }
                elseif ($Line -match '^Release notes: (https://\S+)$') {
                    $Current.Changelog = $Matches[1]
                }
                elseif ($Line -match '^Restarting service: (.+)$') {
                    $Current.Details += "Service: $($Matches[1]); "
                }
                elseif ($Line -match '^\s*Active:\s+active \(running\)' -and $Current.Status -notin @('Failed', 'Warning')) {
                    $Current.Status = 'Updated'
                }
                elseif ($Line -match '^\s*Active:\s+(failed|inactive)') {
                    $Current.Status = 'Failed'
                    $Current.Details += "$($Line.Trim()); "
                }
            }

            if ($Record -is [System.Management.Automation.WarningRecord] -or $Line -match '^W:') {
                if (-not $Current) {
                    $Current = [pscustomobject]@{ VM = $VmName; Type = $Type; Application = 'Custom script'; Status = 'Unknown'; Version = ''; Details = '' }
                    $Rows.Add($Current)
                }
                if ($Current.Status -ne 'Failed') { $Current.Status = 'Warning' }
                $Current.Details += "$Line; "
            }
        }
    }

    if ($Rows.Count -eq 0) {
        $Current = [pscustomobject]@{ VM = $VmName; Type = $Type; Application = 'Custom script'; Status = 'Unknown'; Version = ''; Details = 'No recognized update result.' }
        $Rows.Add($Current)
    }
    if ($Failed) { $Current.Status = 'Failed' }
    $Rows
}

<#
.SYNOPSIS
Formats recorded updates as one summary line per VM.

.DESCRIPTION
Includes only Updated results with a recorded version, ordered by VM and
application and grouped by VM. Each line lists application names
and previous-to-current version changes, with changelog URLs when available.
Returns no output when no results qualify. Does not write headings or fallback
messages to the host.

.PARAMETER Summary
Update result objects returned by Invoke-VmUpdate or Get-UpdateSummary.
Uses VM, Application, Status, Version, PreviousVersion, and optional Changelog
properties. Accepts an empty collection and defaults to an empty array.

.OUTPUTS
System.String
One line per VM in the form VM | application (previous -> current) [changelog].
Multiple applications are comma-separated; the changelog is optional.

.EXAMPLE
Format-UpdateSummary -Summary $summary
#>
function Format-UpdateSummary {
    param(
        [AllowEmptyCollection()]
        [object[]]$Summary = @()
    )

    $Updated = $Summary | Where-Object { $_.Status -eq 'Updated' -and $_.Version }
    foreach ($Group in ($Updated | Sort-Object VM, Application | Group-Object VM)) {
        $Packages = foreach ($Row in $Group.Group) {
            $Package = "$($Row.Application) ($($Row.PreviousVersion) -> $($Row.Version))"
            if ($Row.Changelog) { $Package += " [$($Row.Changelog)]" }
            $Package
        }
        "$($Group.Name) | " + ($Packages -join ', ')
    }
}

<#
.SYNOPSIS
Prints the final VM update summary.

.DESCRIPTION
Writes an Update Summary heading and surrounding blank lines to the host.
Returns the lines from Format-UpdateSummary, grouped by VM, for updated packages
and applications with recorded versions. When no such updates exist, returns an
error reminder if any result failed, or an all-up-to-date message otherwise.

.PARAMETER Summary
Update result objects returned by Invoke-VmUpdate or Get-UpdateSummary.
Accepts an empty collection and defaults to an empty array.

.OUTPUTS
System.String
Formatted update lines or a fallback status message.

.EXAMPLE
Write-UpdateSummary -Summary $summary
#>
function Write-UpdateSummary {
    param(
        [AllowEmptyCollection()]
        [object[]]$Summary = @()
    )

    Write-Host ""
    Write-Header 'Update Summary'
    $updates = @(Format-UpdateSummary -Summary $Summary)
    if ($updates.Count -gt 0) {
        $updates
    }
    elseif ($Summary.Status -contains 'Failed') {
        'No updates recorded. Check the errors above.'
    }
    else {
        'All VMs up-to-date.'
    }
    Write-Host ""
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
