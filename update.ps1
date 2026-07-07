Import-Module ./Automation

##-----------------
# Update all VMs
##------------------
$user = "root"
foreach ($vm in Get-VmList -Path './vm.txt') {
    Write-Header "Updating $vm"
    Invoke-PwshCommand -VmName $vm -User $User -FilePath ".\scripts\apt-get-update.ps1"

    # Check for a custom update script and execute it
    $name = $vm.Split('.')[0]
    $updateScript = ".\scripts\$name\update.ps1"
    if (Test-Path $updateScript) {
        Write-Host ""
        Invoke-PwshCommand -VmName $vm -User $user -FilePath $updateScript
    }
}

