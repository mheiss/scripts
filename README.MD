# Smart Home VM Automation Scripts

## Overview

PowerShell and shell scripts for preparing and maintaining smart-home virtual machines over SSH and PowerShell remoting.

A central feature is full automation for applications published as GitHub Releases. For supported services, the scripts handle the release lifecycle end to end:

- Check the latest GitHub release.
- Select the configured release asset.
- Download and extract the asset.
- Update the executable symlink.
- Restart the related systemd service.
- Print service status after the restart.

The repository has two main workflows:

1. Bootstrap each VM so PowerShell remoting over SSH is available.
2. Update each VM by running package updates and fully automated service-specific GitHub Release updates.

## Notice

> This repository is provided for inspiration and reference only. It reflects my specific smart-home environment and is not intended to be used directly without careful review, adaptation, and testing in your own infrastructure.

## Requirements

### Local Machine

- PowerShell.
- SSH client tools: `ssh` and `scp`.
- Access to the target VMs as `root`.
- SSH key authentication configured or otherwise available.

### Target VMs

- Debian-like Linux distribution.
- `bash`, `apt-get`, `systemctl`, `wget`, and `dpkg`.
- Network access to Microsoft package repositories for initial PowerShell installation.
- Network access to GitHub for application release updates.

## VM Inventory

Each immediate subdirectory of `vms/` represents a target VM. Every VM has an
`update.ps1` script, including machines that only need APT updates.

The shared default DNS domain and SSH user are configured in `vms/config.psd1`:

```powershell
@{
	Domain = 'home.arpa'
	User = 'root'
}
```

This is an example domain; set it to the domain used by your VMs. The automation
appends it to folder names without a dot, so `vms/evcc/` targets `evcc.home.arpa`
with the example configuration. Folder names containing a dot are treated as
full hostnames and left unchanged. VMs are processed in folder-name order.

Both setup and update use the configured `User`. The scripts require root
privileges and do not automatically elevate with `sudo`.

To add an APT-only VM, create `vms/<vm-name>/update.ps1` containing:

```powershell
Update-Apt
```

## Initial VM Setup

Run:

```powershell
.\setup.ps1
```

This script:

1. Imports the local `Automation` module.
2. Reads the domain and user from `vms/config.psd1` and discovers VM folders under `vms/`.
3. Connects to each VM with SSH as the configured user.
4. Uploads `scripts/pwsh-remoting.sh` to a temporary path on the remote host.
5. Executes the script with `bash`.
6. Removes the temporary remote script.

The bootstrap script `scripts/pwsh-remoting.sh`:

- Installs PowerShell if `pwsh` is missing.
- Adds the Microsoft Debian package repository.
- Installs `Microsoft.PowerShell.RemotingTools`.
- Enables SSH public key authentication.
- Adds the PowerShell SSH subsystem to `sshd_config`:

```text
Subsystem powershell /usr/bin/pwsh -sshs -NoLogo -NoProfile
```

- Restarts `ssh` or `sshd`.

## Updating VMs

Run:

```powershell
.\update.ps1
```

This script:

1. Imports the local `Automation` module.
2. Reads the domain and user from `vms/config.psd1` and discovers VM folders under `vms/`.
3. Opens a PowerShell remoting session to each VM as the configured user.
4. Runs that VM's `vms/<vm-name>/update.ps1` script remotely.
5. The VM script calls `Update-Apt` first, followed by any service-specific updates.
6. Prints a final `Update Summary` section with one line per VM with recorded updates.

A missing VM update script is reported as a failure. If APT fails, the VM script
stops before its service updates; other VMs are still processed.

```text
-----------
Update Summary
-----------
dashboard.home.arpa | curl (7.0 -> 8.0), mheiss/dashboard (1.0 -> 2.0) [https://github.com/mheiss/dashboard/releases/tag/v2.0]
```

VMs without changes are omitted. If no changes are recorded, the section shows
`All VMs up-to-date.`, or an error reminder if an update failed. Newly installed packages show
`not installed` as their previous version. Custom application versions are read
from the existing installation symlink, and GitHub release links are included
when available. Detailed progress and errors still appear during updates.

The shared `Update-Apt` helper runs these commands and checks their exit codes:

```powershell
bash -c "export LC_ALL=C DEBIAN_FRONTEND=noninteractive && apt-get update -y"
bash -c "export LC_ALL=C DEBIAN_FRONTEND=noninteractive && apt-get upgrade -y"
```

## Service-Specific Updates

Service updates are stored under `vms/<vm-name>/update.ps1`, after the
`Update-Apt` call. The top-level `update.ps1` runs one script per VM folder.

These scripts are thin service definitions around `Update-App`. Each one describes:

- GitHub repository.
- Release asset pattern.
- Install directory.
- systemd service.
- Symlink path.

`Update-App` handles latest-version detection, download, extraction, executable setup, symlink replacement, service restart, and status output.

| Folder                 | GitHub repo                 | Asset pattern           | Install base        | Service        | Symlink              |
| ---------------------- | --------------------------- | ----------------------- | ------------------- | -------------- | -------------------- |
| `vms/dashboard`    | `AlexxIT/go2rtc`            | `linux_amd64`           | `/opt/go2rtc`       | `go2rtc`       | `/sbin/go2rtc`       |
| `vms/dyndns`       | `mheiss/dyndns`             | `dyndns-app`            | `/opt/dyndns`       | `dyndns`       | `/sbin/dyndns`       |
| `vms/oauth2-proxy` | `oauth2-proxy/oauth2-proxy` | `linux-amd64\.tar\.gz$` | `/opt/oauth2-proxy` | `oauth2-proxy` | `/sbin/oauth2-proxy` |
| `vms/traefik`      | `traefik/traefik`           | `linux_amd64`           | `/opt/traefik`      | `traefik`      | `/sbin/traefik`      |
| `vms/zwave`        | `zwave-js/zwave-js-ui`      | `linux\.zip$`           | `/opt/zwave-js`     | `zwave-js`     | `/sbin/zwave-js`     |

## Adding a New GitHub Release-Based Application Update

For any application that publishes installable assets through GitHub Releases, create `vms/<vm-name>/update.ps1` with this pattern:

```powershell
Update-Apt

$Repo = "owner/repository"
$AssetName = "asset-name-or-regex"
$BaseDir = "/opt/app-name"
$ServiceName = "systemd-service-name"
$SymlinkPath = "/sbin/app-name"

Update-App -Repo $Repo -AssetName $AssetName -BaseDir $BaseDir -ServiceName $ServiceName -SymlinkPath $SymlinkPath
```

Then run:

```powershell
.\update.ps1
```

## Automation Module

The reusable functions live in `Automation/automation.psm1`. The module manifest `Automation/Automation.psd1` exports all functions.

### `Write-Header`

Prints a dashed heading for the current operation.

### `Get-VmList`

Reads immediate child directories in name order and appends the configured domain
to short folder names. Returns one object per VM:

- `Name`: original folder name.
- `HostName`: hostname used for remote connections.
- `UpdateScript`: absolute path to that folder's `update.ps1` script.

Parameters:

- `Path`: path to the VM folder.
- `Domain`: default DNS domain from `vms/config.psd1`.

### `Update-Apt`

Runs noninteractive APT package-list refresh and package upgrades. Throws on a
nonzero exit code. Every VM update script calls this helper before service updates.

### `New-VmSession`

Creates a PowerShell remoting session with:

```powershell
New-PSSession -HostName $VmName -UserName $User
```

It also imports the automation module functions into the remote session so custom update scripts can call helpers such as `Update-App`.

### `Invoke-PwshCommand`

Runs commands or a local script file on a remote VM through PowerShell remoting.

Supported modes:

- `-Commands <string[]>`
- `-FilePath <string>`

When `-FilePath` is used, the file is read locally, sent to the remote session, and executed remotely.

### `Invoke-SshScript`

Uploads a local script to a remote host with `scp`, runs it with `ssh`, then deletes the uploaded file. This is used by `setup.ps1` before PowerShell remoting is available.

### `Wait-Resource`

Polls an HTTP or HTTPS resource until it returns HTTP 2xx. Returns `$true` on
success, or warns and returns `$false` on timeout. Redirects are not followed,
so a redirect to a login page does not count as readiness. Requests bypass proxies.

Parameters:

- `Uri`: required HTTP or HTTPS resource URL.
- `TimeoutSeconds`: overall polling timeout, default `120`.
- `RetryIntervalSeconds`: delay between attempts, default `2`.
- `RequestTimeoutSeconds`: timeout per request, default `5`, capped to the remaining polling time (rounded up to seconds).

The dashboard update uses this helper before refreshing Fully:

```powershell
if (Wait-Resource -Uri "http://localhost:8082") {
	Update-FullyDisplay -SecretFile "/etc/dashboard/fully.env"
}
```

Use the local URL on the dashboard VM to check application readiness without
depending on external DNS, TLS, reverse proxy, or authentication. A public URL
such as `https://dashboard.home.arpa` can instead check the full route, provided
it returns HTTP 2xx without authentication. On timeout, the display refresh is
skipped and the remaining application updates continue.

### `Update-FullyDisplay`

Requests a Fully Kiosk Browser display to refresh the smart-home dashboard.

The command reads an env-style secrets file on the target VM. The file must define:

```text
FULLY_URL=http://display-host:2323
FULLY_PASSWORD=<password>
```

Keep this file outside the repository and restrict it to the account running the update, for example with root ownership and `600` permissions.

Parameters:

- `SecretFile`: path to the env-style secrets file. Defaults to `/etc/dashboard/fully.env`.

Example:

```powershell
Update-FullyDisplay -SecretFile "/etc/dashboard/fully.env"
```

Behavior:

1. Loads `FULLY_URL` and `FULLY_PASSWORD` from the configured secrets file.
2. Checks that `FULLY_URL` is valid and that its host resolves from the target VM.
3. Sends `clearCache`, `loadStartUrl`, and `screenOn` commands to the Fully remote admin API.
4. Prints a warning and returns without failing the full update when the secrets file, required values, DNS lookup, or HTTP request fails.

If the command reports `Name or service not known` or cannot resolve the Fully host, fix DNS for the target VM or use an IP address in `FULLY_URL`.

### `Update-App`

Updates an application distributed through GitHub releases.

Parameters:

- `Repo`: GitHub repository, for example `traefik/traefik`.
- `AssetName`: regex used to select a release asset.
- `BaseDir`: versioned install directory root.
- `ServiceName`: systemd service to restart.
- `SymlinkPath`: stable executable path to update.

Behavior:

1. Fetches the latest GitHub release metadata.
2. Derives the version from the release tag.
3. Skips the update if the version directory already exists.
4. Downloads the matching release asset.
5. Extracts `.tar.gz` or `.zip` assets.
6. Flattens a single top-level extracted directory.
7. Detects whether the extracted app is a single file or a directory.
8. Makes single-file applications executable.
9. Updates the symlink with `ln -sfn`.
10. Restarts the systemd service.
11. Prints service status with `systemctl status --no-pager`.
12. Removes old version directories, keeping only the latest release and the previous installed release.

### `Remove-OldAppVersion`

Removes old application release directories from a versioned install root, keeping the specified latest version and the newest previous installed version.

Parameters:

- `BaseDir`: versioned install directory root.
- `LatestVersion`: latest version directory name to keep.

### `Import-FunctionsToRemote`

Reads `Automation/automation.psm1` and evaluates it inside the remote PowerShell session. This makes local helper functions available to remote scripts.

### `Update-AutomationModule`

Reloads the local `Automation` module during interactive development.
