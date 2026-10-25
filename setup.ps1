Import-Module "$PSScriptRoot/automation" -Force
$config = Import-PowerShellDataFile "$PSScriptRoot/vms/config.psd1"


##-----------------
# Configure all VMs
##------------------
$user = "root"
foreach ($vm in Get-VmList -Path "$PSScriptRoot/vms" -Domain $config.Domain) {
    Write-Header "Configuring $vm"
    Invoke-SshScript -VmName $vm -User $user -LocalPath "$PSScriptRoot/scripts/pwsh-remoting.sh"
}