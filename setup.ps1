Import-Module ./automation

##-----------------
# Configure all VMs
##------------------
foreach ($vm in Get-VmList './vm.txt') {
    Write-Header "Configuring $vm"
    Invoke-SshScript -VmName $vm -User "root" -LocalPath .\scripts\remoting.sh
}
