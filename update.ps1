Import-Module "$PSScriptRoot/automation" -Force
$config = Import-PowerShellDataFile "$PSScriptRoot/vms/config.psd1"

##-----------------
# Update all VMs
##------------------
$user = "root"
$summary = [System.Collections.Generic.List[object]]::new()
foreach ($vm in Get-VmList -Path "$PSScriptRoot/vms" -Domain $config.Domain) {
    Write-Header "Updating $vm"
    $name = if (Test-Path -LiteralPath "$PSScriptRoot/vms/$vm" -PathType Container) {
        $vm
    }
    else {
        $vm.Substring(0, $vm.Length - $config.Domain.Length - 1)
    }
    $updateScript = "$PSScriptRoot/vms/$name/update.ps1"

    $output = [System.Collections.Generic.List[object]]::new()
    $failed = $false
    try {
        Invoke-PwshCommand -VmName $vm -User $user -FilePath $updateScript -ErrorAction Stop *>&1 |
        ForEach-Object {
            $output.Add($_)
            if ($_ -is [System.Management.Automation.InformationRecord]) {
                [string]$_.MessageData | Out-Host
            }
            else {
                $_ | Out-Host
            }
        }
    }
    catch {
        $failed = $true
        $output.Add($_)
        Write-Host "Update failed for ${vm}: $_" -ForegroundColor Red
    }
    foreach ($result in Get-UpdateSummary -VmName $vm -Type Custom -Output $output.ToArray() -Failed:$failed) {
        $summary.Add($result)
    }
}

Write-Host ""
Write-Header 'Update Summary'
$info = @(Format-UpdateSummary -Summary $summary.ToArray())
if ($info.Count -gt 0) {
    $info
}
elseif ($summary.Status -contains 'Failed') {
    'No updates recorded. Check the errors above.'
}
else {
    'All VMs up-to-date.'
}
Write-Host ""

