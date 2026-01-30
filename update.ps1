Import-Module ./automation

##-----------------
# Update all VMs
##------------------
$user = "root"
foreach ($vm in Get-VmList './vm.txt') {
    Write-Header "Updating $vm"
    #Invoke-SshScript -VmName $vm -User $User -LocalPath ".\scripts\apt-get-update.sh"

    # Check for a custom update script and execute it
    $name = $vm.Split('.')[0]
    $updateScript = ".\scripts\$name\update.ps1"
    if (Test-Path $updateScript) {
       $script = Get-Content $updateScript -Raw
       Invoke-PwshCommand -VmName $vm -User $user -Commands @($script)
    }
}

