$Repo = "traefik/traefik"
$AssetName = "linux_amd64"
$BaseDir = "/opt/traefik"
$AppName = "traefik"
$ServiceName = "traefik"
$SymlinkPath = "/sbin/traefik"


Update-App -Repo $Repo -AssetName $AssetName -BaseDir $BaseDir -AppName $AppName -ServiceName $ServiceName -SymlinkPath $SymlinkPath