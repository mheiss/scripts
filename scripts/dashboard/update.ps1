$Repo = "AlexxIT/go2rtc"
$ReleaseEndpoint = "https://api.github.com/repos/$Repo/releases/latest"

$BaseDir = "/opt/go2rtc"
$AppName = "go2rtc_linux_amd64"
$ServiceName = "go2rtc"
$SymlinkPath = "/sbin/go2rtc"

Write-Host "Updating $AppName..."

$Response = Invoke-RestMethod -Uri $ReleaseEndpoint -Headers @{ "User-Agent" = "PowerShell" }

$Tag = $Response.tag_name
$Version = $Tag.TrimStart("v")
$TargetDir = Join-Path $BaseDir $Version

# Exit early if already downloaded
if (Test-Path $TargetDir) {
    Write-Host "Latest release $Tag is already installed. Nothing to do."
    exit 0
}
Write-Host "Update available: $Version."

New-Item -ItemType Directory -Path $TargetDir | Out-Null

# Select the Linux ZIP asset
$Asset = $Response.assets | Where-Object { $_.name -match "linux_amd64" }
if (-not $Asset) {
    Write-Host "Linux asset not found!"
    exit 1
}

$DownloadUrl = $Asset.browser_download_url
$FileName = $Asset.name
$FilePath = Join-Path $TargetDir $FileName

Write-Host "Downloading $FileName..."
Invoke-WebRequest -Uri $DownloadUrl -OutFile $FilePath

# Update symlink
$AppPath = Join-Path $TargetDir $AppName
Write-Host "Updating symlink $AppPath -> $SymlinkPath"
bash -c "chmod +x $AppPath"
bash -c "ln -s -f '$AppPath' '$SymlinkPath'"

# Restart service
Write-Host "Restarting service: $ServiceName"
bash -c "systemctl restart $ServiceName"
bash -c "systemctl status $ServiceName --no-pager"