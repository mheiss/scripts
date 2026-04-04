#!/usr/bin/env pwsh
<#
.SYNOPSIS
Fetches the Marktpreis from https://www.oem-ag.at/marktpreis.

.DESCRIPTION
Downloads the OeMAG Marktpreis page and provides a JSON output.
#>

[CmdletBinding()]
param()

function Remove-HtmlTags {
    param(
        [string]$Html
    )

    $result = $Html -replace '(?si)<br\s*/?>', "`n"
    $result = $result -replace '(?si)<(script|style)\b.*?</\1>', ' '
    $result = $result -replace '<[^>]+>', ' '
    $result = [System.Net.WebUtility]::HtmlDecode($result)
    $result = $result -replace '\s+', ' '
    return $result.Trim()
}

function Convert-MonthNameToNumber {
    param(
        [string]$MonthName
    )

    $text = $MonthName.Trim()
    if (-not $text) {
        return $null
    }

    $culture = [System.Globalization.CultureInfo]::GetCultureInfo('de-AT')
    try {
        return ([DateTime]::ParseExact($text, 'MMMM', $culture)).Month
    }
    catch {
        return $null
    }
}

function Convert-CentsTextToEuro {
    param(
        [string]$Text
    )

    $normalized = $Text -replace '[^0-9,.-]', ''
    if ($normalized -match "^(?<whole>[0-9]{1,3}(?:\.[0-9]{3})+),(?<frac>[0-9]+)$") {
        $normalized = ($matches['whole'] -replace '\.', '') + '.' + $matches['frac']
    }
    elseif ($normalized -match ',') {
        $normalized = $normalized -replace ',', '.'
    }

    $centValue = 0
    $style = [System.Globalization.NumberStyles]::AllowDecimalPoint -bor [System.Globalization.NumberStyles]::AllowLeadingSign
    $culture = [System.Globalization.CultureInfo]::InvariantCulture
    if (-not [decimal]::TryParse($normalized, $style, $culture, [ref]$centValue)) {
        return $null
    }

    return [math]::Round($centValue / 100, 5)
}

try {
    $response = Invoke-WebRequest -Uri 'https://www.oem-ag.at/marktpreis' -UseBasicParsing -ErrorAction Stop
    $html = $response.Content

    # Find accordion-body elements
    $accordionBodies = [regex]::Matches($html, "<div class=`"accordion-body`">(.*?)</div>", [System.Text.RegularExpressions.RegexOptions]::Singleline)
    if ($accordionBodies.Count -lt 2) {
        throw "Found only $($accordionBodies.Count) accordion-body elements; requested index 2."
    }

    $elementHtml = $accordionBodies[1].Groups[1].Value

    # Find table
    $tableMatch = [regex]::Match($elementHtml, "<table.*?>(.*?)</table>", [System.Text.RegularExpressions.RegexOptions]::Singleline)
    if (-not $tableMatch.Success) {
        throw 'No table found in extracted Marktpreis block.'
    }

    $tableHtml = $tableMatch.Groups[1].Value

    # Find rows
    $rows = [regex]::Matches($tableHtml, "<tr.*?>(.*?)</tr>", [System.Text.RegularExpressions.RegexOptions]::Singleline)
    $items = @()

    foreach ($row in $rows) {
        $rowHtml = $row.Groups[1].Value
        if ($rowHtml -match "<th") {
            continue
        }

        $cells = [regex]::Matches($rowHtml, "<td.*?>(.*?)</td>", [System.Text.RegularExpressions.RegexOptions]::Singleline)
        if ($cells.Count -lt 2) {
            continue
        }

        $dateText = Remove-HtmlTags $cells[0].Groups[1].Value
        $revenueText = Remove-HtmlTags $cells[1].Groups[1].Value
        $month = Convert-MonthNameToNumber $dateText
        $euro = Convert-CentsTextToEuro $revenueText

        if ($dateText -and $revenueText) {
            $items += [pscustomobject]@{
                dateText = $dateText
                revenueText = $revenueText
                date = $month
                revenue = $euro
            }
        }
    }

    if (-not $items) {
        throw 'No data rows found in Marktpreis table.'
    }

    $items | ConvertTo-Json -Depth 3
}
catch {
    Write-Error "Failed to fetch Marktpreis: $($_.Exception.Message)"
    exit 1
}
