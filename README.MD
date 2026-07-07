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

Target machines and the default DNS domain are configured together in `vm.txt`.

Use a `domain=<name>` entry for the default domain, followed by one VM name or full hostname per line:

```text
domain=heiss.lan

evcc
influx
traefik
```

The automation appends the configured domain to VM entries that do not already contain a dot. With `domain=heiss.lan`, `evcc` becomes `evcc.heiss.lan`.

Blank lines and lines starting with `#` are ignored. VM entries that already contain a dot are treated as full hostnames and are not changed.

## Initial VM Setup

Run:

```powershell
.\setup.ps1
```

This script:

1. Imports the local `Automation` module.
2. Reads the domain and VMs from `vm.txt`.
3. Connects to each VM as `root` with SSH.
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
2. Reads the domain and VMs from `vm.txt`.
3. Opens a PowerShell remoting session to each VM as `root`.
4. Runs `scripts/apt-get-update.ps1` on each VM.
5. Looks for a custom update script at `scripts/<vm-short-name>/update.ps1`.
6. Runs that custom script when it exists.

The shared package update script runs:

```powershell
bash -c "export DEBIAN_FRONTEND=noninteractive && apt-get update -y"
bash -c "export DEBIAN_FRONTEND=noninteractive && apt-get upgrade -y"
```

## Service-Specific Updates

Custom service updates are stored under `scripts/<vm-name>/update.ps1`. The top-level `update.ps1` runs them only when the folder name matches the short VM name from `vm.txt`.

These scripts are thin service definitions around `Update-App`. Each one describes:

- GitHub repository.
- Release asset pattern.
- Install directory.
- systemd service.
- Symlink path.

`Update-App` handles latest-version detection, download, extraction, executable setup, symlink replacement, service restart, and status output.

| Folder                 | GitHub repo                 | Asset pattern           | Install base        | Service        | Symlink              |
| ---------------------- | --------------------------- | ----------------------- | ------------------- | -------------- | -------------------- |
| `scripts/dashboard`    | `AlexxIT/go2rtc`            | `linux_amd64`           | `/opt/go2rtc`       | `go2rtc`       | `/sbin/go2rtc`       |
| `scripts/dyndns`       | `mheiss/dyndns`             | `dyndns-app`            | `/opt/dyndns`       | `dyndns`       | `/sbin/dyndns`       |
| `scripts/oauth2-proxy` | `oauth2-proxy/oauth2-proxy` | `linux-amd64\.tar\.gz$` | `/opt/oauth2-proxy` | `oauth2-proxy` | `/sbin/oauth2-proxy` |
| `scripts/traefik`      | `traefik/traefik`           | `linux_amd64`           | `/opt/traefik`      | `traefik`      | `/sbin/traefik`      |
| `scripts/zwave`        | `zwave-js/zwave-js-ui`      | `linux\.zip$`           | `/opt/zwave-js`     | `zwave-js`     | `/sbin/zwave-js`     |

## Adding a New GitHub Release-Based Application Update

For any application that publishes installable assets through GitHub Releases, create `scripts/<vm-short-name>/update.ps1` with this pattern:

```powershell
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

Reads the VM list file, trims whitespace, ignores blank/comment lines, reads the `domain=<name>` entry, and appends the configured domain to short hostnames.

Parameters:

- `Path`: path to the VM list file.

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

### `Import-FunctionsToRemote`

Reads `Automation/automation.psm1` and evaluates it inside the remote PowerShell session. This makes local helper functions available to remote scripts.

### `Update-AutomationModule`

Reloads the local `Automation` module during interactive development.
