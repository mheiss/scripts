$Repo = "oauth2-proxy/oauth2-proxy"
$AssetName = "linux-amd64\.tar\.gz$"
$BaseDir = "/opt/oauth2-proxy"
$AppName = "oauth2-proxy"
$ServiceName = "oauth2-proxy"
$SymlinkPath = "/sbin/oauth2-proxy"

Update-App -Repo $Repo -AssetName $AssetName -BaseDir $BaseDir -AppName $AppName -ServiceName $ServiceName -SymlinkPath $SymlinkPath