Import-Module ./automation

##-----------------
# Configure all VMs
##------------------
foreach ($vm in Get-VmList './vm.txt') {
    Write-Header "Configuring $vm"
    Enable-VmRemoting -VmName $vm -User "root"
}
