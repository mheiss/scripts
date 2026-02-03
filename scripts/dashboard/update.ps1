$Repo = "AlexxIT/go2rtc"
$AssetName = "linux_amd64"
$BaseDir = "/opt/go2rtc"
$AppName = "go2rtc_linux_amd64"
$ServiceName = "go2rtc"
$SymlinkPath = "/sbin/go2rtc"

Update-App -Repo $Repo -AssetName $AssetName -BaseDir $BaseDir -AppName $AppName -ServiceName $ServiceName -SymlinkPath $SymlinkPath