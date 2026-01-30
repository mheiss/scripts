$Repo = "zwave-js/zwave-js-ui"
$ReleaseEndpoint = "https://api.github.com/repos/$Repo/releases/latest"

$BaseDir = "/opt/zwave-js"
$AppName = "zwave-js-ui-linux"
$ServiceName = "zwave-js"
$SymlinkPath = "/sbin/zwave-js-ui-linux"

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

New-Item -ItemType Directory -Path $TargetDir | Out-Null

# Select the Linux ZIP asset
$Asset = $Response.assets | Where-Object { $_.name -match "linux\.zip$" }
if (-not $Asset) {
    Write-Host "Linux ZIP asset not found!"
    exit 1
}

$DownloadUrl = $Asset.browser_download_url
$FileName = $Asset.name
$FilePath = Join-Path $TargetDir $FileName

Write-Host "Downloading $FileName..."
Invoke-WebRequest -Uri $DownloadUrl -OutFile $FilePath

Write-Host "Unpacking..."
Expand-Archive -Path $FilePath -DestinationPath $TargetDir -Force

# Cleanup Archive and useless folder
Remove-Item $FilePath -Force
$StorePath = Join-Path $TargetDir "store"
if (Test-Path $StorePath) {
    Remove-Item $StorePath -Recurse -Force
}

# Update symlink
$AppPath = Join-Path $TargetDir $AppName
Write-Host "Updating symlink to $AppPath"
bash -c "ln -s -f '$AppPath' '$SymlinkPath'"

# Restart service
Write-Host "Restarting service: $ServiceName"
bash -c "systemctl restart $ServiceName"
bash -c "systemctl status $ServiceName --no-pager"