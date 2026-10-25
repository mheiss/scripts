Import-Module ./Automation -Force

##-----------------
# Update all VMs
##------------------
$user = "root"
$summary = [System.Collections.Generic.List[object]]::new()
foreach ($vm in Get-VmList -Path './vm.txt') {
    Write-Header "Updating $vm"
    $name = $vm.Split('.')[0]
    $updateScript = ".\scripts\$name\update.ps1"
    $steps = @([pscustomobject]@{ Type = 'Apt'; Path = '.\scripts\apt-get-update.ps1' })
    if (Test-Path $updateScript) {
        $steps += [pscustomobject]@{ Type = 'Custom'; Path = $updateScript }
    }
    else {
        $summary.Add([pscustomobject]@{ VM = $vm; Type = 'Custom'; Application = ''; Status = 'Skipped'; Version = ''; Details = 'No custom update script.' })
    }

    foreach ($step in $steps) {
        $output = [System.Collections.Generic.List[object]]::new()
        $failed = $false
        try {
            Invoke-PwshCommand -VmName $vm -User $user -FilePath $step.Path -ErrorAction Stop *>&1 |
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
        foreach ($result in Get-UpdateSummary -VmName $vm -Type $step.Type -Output $output.ToArray() -Failed:$failed) {
            $summary.Add($result)
        }
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

