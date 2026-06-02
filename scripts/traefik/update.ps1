$Repo = "traefik/traefik"
$AssetName = "linux_amd64"
$BaseDir = "/opt/traefik"
$ServiceName = "traefik"
$SymlinkPath = "/sbin/traefik"

Update-App -Repo $Repo -AssetName $AssetName -BaseDir $BaseDir -ServiceName $ServiceName -SymlinkPath $SymlinkPath