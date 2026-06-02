$Repo = "mheiss/dyndns"
$AssetName = "dyndns-app"
$BaseDir = "/opt/dyndns"
$ServiceName = "dyndns"
$SymlinkPath = "/sbin/dyndns"

Update-App -Repo $Repo -AssetName $AssetName -BaseDir $BaseDir -ServiceName $ServiceName -SymlinkPath $SymlinkPath