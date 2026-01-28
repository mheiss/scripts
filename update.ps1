Import-Module ./automation

##-----------------
# Update all VMs
##------------------
foreach ($vm in Get-VmList './vm.txt') {
    Write-Header "Updating $vm"
    Update-Vm -VmName $vm -User "root"
}

