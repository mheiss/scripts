# Function that runs the given process and prints the result to the console
function RunCommands {
    param(
        [string]$user,
        [string]$destination,
        [string]$command
    )

    $arguments = @("$user@$destination", $command)
    $argumentsString = $arguments -join " "

    $pinfo = New-Object System.Diagnostics.ProcessStartInfo
    $pinfo.FileName = "ssh"
    $pinfo.RedirectStandardError = $true
    $pinfo.RedirectStandardOutput = $true
    $pinfo.UseShellExecute = $false
    $pinfo.Arguments = $argumentsString
    $p = New-Object System.Diagnostics.Process
    $p.StartInfo = $pinfo
    $p.Start() | Out-Null
    $p.WaitForExit()

    $stdout = $p.StandardOutput.ReadToEnd()
    Write-Host "$stdout"
}

# Writes out a nice header 
function Write-Header {
    param(
        [string]$header
    )
    for ($i = 0; $i -le $header.Length; $i++) {
        if ($i -le $header.Length - 1) {
            Write-Host -NoNewline "-"
        }
        else {
            Write-Host "-"
        }
    }
    Write-Host $header
    for ($i = 0; $i -le $header.Length; $i++) {
        if ($i -le $header.Length - 1) {
            Write-Host -NoNewline "-"
        }
        else {
            Write-Host "-"
        }
    }
}

##-----------------
# Update all VMs
##------------------
$vms = 'evcc', 'influx', 'dyndns', 'traefik', 'grafana', 'keycloak', "oauth2-proxy", "zwave", "openhab5", "dashboard"
$script = @"
  DEBIAN_FRONTEND=noninteractive apt-get update && apt-get upgrade --yes &&
  [ -f update.ps1 ] && echo '' && pwsh './update.ps1'
"@

foreach ($vm in $vms) {
    $user = "root"
    $destination = "$vm.heiss.lan"

    Write-Header "Updating $destination"
    RunCommands -user $user -destination $destination -command $script
}

