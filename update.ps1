Import-Module "$PSScriptRoot/automation" -Force

$vmPath = "$PSScriptRoot/vms"
$config = Import-PowerShellDataFile "$vmPath/config.psd1"

$summary = @(
    foreach ($vm in Get-VmList -Path $vmPath -Domain $config.Domain) {
        Invoke-VmUpdate -VmName $vm.HostName -User $config.User -FilePath $vm.UpdateScript
    }
)

Write-UpdateSummary -Summary $summary

