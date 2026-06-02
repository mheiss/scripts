$Repo = "AlexxIT/go2rtc"
$AssetName = "linux_amd64"
$BaseDir = "/opt/go2rtc"
$ServiceName = "go2rtc"
$SymlinkPath = "/sbin/go2rtc"

Update-App -Repo $Repo -AssetName $AssetName -BaseDir $BaseDir -ServiceName $ServiceName -SymlinkPath $SymlinkPath