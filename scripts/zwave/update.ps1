$Repo = "zwave-js/zwave-js-ui"
$AssetName = "linux\.zip$"
$BaseDir = "/opt/zwave-js"
$AppName = "zwave-js-ui-linux"
$ServiceName = "zwave-js"
$SymlinkPath = "/sbin/zwave-js-ui-linux"

Update-App -Repo $Repo -AssetName $AssetName -BaseDir $BaseDir -AppName $AppName -ServiceName $ServiceName -SymlinkPath $SymlinkPath