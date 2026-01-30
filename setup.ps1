Import-Module ./automation

##-----------------
# Configure all VMs
##------------------
$user = "root"
foreach ($vm in Get-VmList './vm.txt') {
    Write-Header "Configuring $vm"
    Invoke-SshScript -VmName $vm -User $user -LocalPath ".\scripts\pwsh-remoting.sh"
}