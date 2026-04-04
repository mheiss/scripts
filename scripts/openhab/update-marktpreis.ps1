#!/usr/bin/env pwsh
<#
.SYNOPSIS
Runs the Marktpreis script and updates OpenHAB items with the values.

.DESCRIPTION
Executes get-oemag-marktpreis.ps1, parses the JSON output, and sends updates to OpenHAB via REST API.

.PARAMETER OpenHabUrl
The base URL of your OpenHAB instance (e.g., 'http://localhost:8080').

.PARAMETER ItemPrefix
The prefix for OpenHAB item names (e.g., 'MarketPrice_').

.EXAMPLE
.\update-openhab-marktpreis.ps1 -OpenHabUrl 'http://openhab:8080' -ItemPrefix 'OEMAG_'
#>

param(
    [Parameter(Mandatory)]
    [string]$OpenHabUrl,

    [Parameter(Mandatory)]
    [string]$ItemPrefix
)

# Path to the Marktpreis script
$scriptPath = Join-Path $PSScriptRoot 'oemag\get-oemag-marktpreis.ps1'

# Run the script and capture output
try {
    $jsonOutput = & pwsh -NoProfile -File $scriptPath
    $data = $jsonOutput | ConvertFrom-Json
} catch {
    Write-Error "Failed to run Marktpreis script: $_"
    exit 1
}

# Function to update OpenHAB item
function Update-OpenHabItem {
    param(
        [string]$ItemName,
        [string]$Value
    )

    $url = "$OpenHabUrl/rest/items/$ItemName"
    try {
        Invoke-WebRequest -Uri $url -Method POST -Body $Value -ContentType 'text/plain' -ErrorAction Stop
        Write-Host "Updated $ItemName with $Value"
    } catch {
        Write-Warning "Failed to update $ItemName: $_"
    }
}

# Update items for each month
foreach ($item in $data) {
    $month = $item.date
    $revenue = $item.revenue

    # Item names: e.g., OEMAG_1, OEMAG_2, etc.
    $itemName = "$ItemPrefix$month"
    Update-OpenHabItem -ItemName $itemName -Value $revenue.ToString()
}

Write-Host "OpenHAB update completed."