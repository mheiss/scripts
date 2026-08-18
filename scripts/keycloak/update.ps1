$Repo = "keycloak/keycloak"
$AssetName = "^keycloak-[0-9]+(\.[0-9]+)*\.tar\.gz$"
$BaseDir = "/opt/keycloak"
$ServiceName = "keycloak"
$SymlinkPath = "/opt/keycloak/latest"
$User = "keycloak"
$Group = "keycloak"

Update-App -Repo $Repo -AssetName $AssetName -BaseDir $BaseDir -ServiceName $ServiceName -SymlinkPath $SymlinkPath -User $User -Group $Group