Import-Module "$PSScriptRoot/automation" -Force

$vmPath = "$PSScriptRoot/vms"
$config = Import-PowerShellDataFile "$vmPath/config.psd1"

##-----------------
# Configure all VMs
##------------------
foreach ($vm in Get-VmList -Path $vmPath -Domain $config.Domain) {
    Write-Header "Configuring $($vm.HostName)"
    Invoke-SshScript -VmName $vm.HostName -User $config.User -LocalPath "$PSScriptRoot/scripts/pwsh-remoting.sh"
}