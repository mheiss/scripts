$Repo = "zwave-js/zwave-js-ui"
$AssetName = "linux\.zip$"
$BaseDir = "/opt/zwave-js"
$ServiceName = "zwave-js"
$SymlinkPath = "/sbin/zwave-js-ui-linux"

Update-App -Repo $Repo -AssetName $AssetName -BaseDir $BaseDir -ServiceName $ServiceName -SymlinkPath $SymlinkPath