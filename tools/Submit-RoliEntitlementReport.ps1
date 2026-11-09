#Requires -Version 7.0

[CmdletBinding()]
param(
    [switch]$DryRun
)

$ErrorActionPreference = 'Stop'
$api = 'https://api.roli.com/api/v1'
$userAgent = 'ROLI_CONNECT/1.6.4'
$issuePage = 'https://github.com/Stoom/Roli-Specs/issues/new'
$entryFields = @('enabled', 'expiration', 'id', 'name', 'licences', 'trial_id', 'valid_until')

function Get-RoliSessionToken {
    $identity = Read-Host 'ROLI email or username'
    $password = Read-Host 'ROLI password' -AsSecureString
    try {
        $credential = [pscredential]::new($identity, $password)
        $loginBody = @{
            identity = $identity
            password = $credential.GetNetworkCredential().Password
        } | ConvertTo-Json -Compress
        $login = (Invoke-WebRequest -Uri "$api/authenticate/roli-hub" -Method Post `
            -ContentType 'application/json' -Body $loginBody -UserAgent $userAgent -MaximumRedirection 0 `
            -TimeoutSec 20 -Verbose:$false -Debug:$false).Content | ConvertFrom-Json -AsHashtable
        $token = $login['token']
        if ($token -isnot [string] -or [string]::IsNullOrWhiteSpace($token)) {
            throw 'Missing session token.'
        }
        return $token
    } catch {
        throw 'ROLI sign-in failed. Check the credentials and try again.'
    } finally {
        $password.Dispose()
        $identity = $credential = $loginBody = $login = $token = $null
    }
}

function Add-CatalogMatches($Products, $Payload, $CatalogMatches) {
    foreach ($product in $Products) {
        if ($product -isnot [System.Collections.IDictionary]) { continue }
        $productId = $product['public_id']
        if ($productId -is [string] -and $Payload['entitlements'].Contains($productId)) {
            $entry = $Payload['entitlements'][$productId]
            if ($entry -is [System.Collections.IDictionary]) {
                $id = $product['id']
                $name = $product['name']
                if (!$CatalogMatches.ContainsKey($productId)) { $CatalogMatches[$productId] = @{} }
                if ($id -is [string] -and $id -cmatch '^[a-f0-9]{24}$' -and
                    $id -ceq $entry['id'] -and $id -cne $Payload['uid']) {
                    $CatalogMatches[$productId]['id'] = $id
                }
                if ($name -is [string] -and $name.Length -le 120 -and
                    $name -match '^[\p{L}\p{N} .&()+_''\u2019/-]+$' -and $name -ceq $entry['name']) {
                    $CatalogMatches[$productId]['name'] = $name
                }
            }
        }
        Add-CatalogMatches $product['included_additional_content'] $Payload $CatalogMatches
    }
}

function Get-RoliEntitlements {
    $token = Get-RoliSessionToken
    try {
        $payload = (Invoke-WebRequest -Uri "$api/user/entitlements" -Method Get `
            -Headers @{ 'X-Access-Token' = $token; Accept = 'application/json' } `
            -UserAgent $userAgent -MaximumRedirection 0 -TimeoutSec 20 -Verbose:$false -Debug:$false).Content |
            ConvertFrom-Json -AsHashtable
        if ($payload -isnot [System.Collections.IDictionary] -or
            $payload['entitlements'] -isnot [System.Collections.IDictionary]) {
            throw 'Unexpected entitlement response.'
        }
    } catch {
        $token = $null
        throw 'Could not read the ROLI entitlement response.'
    }

    $catalogMatches = @{}
    try {
        foreach ($route in @('user/products', 'products/software', 'products/trials')) {
            try {
                $products = (Invoke-WebRequest -Uri "$api/$route" -Method Get `
                    -Headers @{ 'X-Access-Token' = $token; Accept = 'application/json' } `
                    -UserAgent $userAgent -MaximumRedirection 0 -TimeoutSec 5 -Verbose:$false -Debug:$false).Content |
                    ConvertFrom-Json -AsHashtable
                Add-CatalogMatches $products $payload $catalogMatches
            } catch {
                # Catalog data is optional. Unmatched values are withheld.
            }
        }
        return @{ Entries = $payload['entitlements']; CatalogMatches = $catalogMatches }
    } finally {
        $token = $payload = $null
    }
}

function Test-ReportableLicenceLabel($Value) {
    # Accept readable labels and screen out opaque or grouped key formats.
    return $Value -is [string] -and $Value.Length -le 64 -and
        $Value -cmatch '\A[a-z]{2,24}[0-9]{0,2}(?:[-_.][a-z]{2,24}[0-9]{0,2})*\z' -and
        $Value -cnotmatch '\A(?:[a-z0-9]{4}-){2,}[a-z0-9]{4}\z|\A(?:[a-z0-9]{5}-){2,}[a-z0-9]{5}\z'
}

function Format-Licences([System.Collections.IList]$Licences) {
    if (!$Licences.Count) { return '    licences: []' }
    $items = @($Licences | Where-Object { Test-ReportableLicenceLabel $_ })
    if (!$items.Count) { return }
    '    licences:'
    $items | Sort-Object -Unique | ForEach-Object { '      - "{0}"' -f $_ }
}

function Format-EntitlementObservation([string]$ProductId, $Entitlement, $Observed, $CatalogMatch, $KnownObservations) {
    $variants = $KnownObservations["  - product_id: '$ProductId'"]
    # Public product aliases can share the same catalog record.
    $knownRecord = $Observed.ContainsKey('id') -and $Observed.ContainsKey('name') -and
        $Observed['id'] -cmatch "^'[a-f0-9]{24}'$" -and
        ($KnownObservations.Values | ForEach-Object { $_ } | Where-Object {
            $_['id'] -ceq $Observed['id'] -and $_['name'] -ceq $Observed['name']
        } | Select-Object -First 1)
    $fields = @(foreach ($field in $entryFields) {
        if (!$Entitlement.Contains($field)) { continue }
        $value = $Entitlement[$field]
        if ($field -in 'id', 'name' -and $value -is [string] -and
            ($ProductId -cne 'unlisted product ID') -and
            (($CatalogMatch -and $CatalogMatch.ContainsKey($field)) -or $knownRecord -or
                ($variants | Where-Object { $_[$field] -ceq $Observed[$field] } | Select-Object -First 1))) {
            $summary = $Observed[$field]
        } elseif ($field -eq 'enabled' -and $value -is [bool]) {
            $summary = $value.ToString().ToLowerInvariant()
        } elseif ($field -eq 'licences' -and $value -is [System.Collections.IList]) {
            Format-Licences $value
            continue
        } elseif ($null -eq $value) {
            $summary = 'null'
        } else {
            continue
        }
        "    ${field}: $summary"
    })
    return (@("  - product_id: '$ProductId'") + $fields) -join "`n"
}

function Get-ComparableFields($Entitlement) {
    $fields = @{}
    foreach ($field in $entryFields) {
        if (!$Entitlement.Contains($field)) { continue }
        $value = $Entitlement[$field]
        $fields[$field] = if ($field -eq 'licences' -and $value -is [System.Collections.IList]) {
            $withheld = @($value | Where-Object { !(Test-ReportableLicenceLabel $_) })
            if ($withheld.Count) { '<withheld>' }
            else { ((Format-Licences $value) -join "`n").Substring('    licences:'.Length).Trim() }
        } elseif ($value -is [string]) {
            "'" + $value.Replace("'", "''") + "'"
        } elseif ($value -is [System.Collections.IDictionary] -or $value -is [System.Collections.IList]) {
            '<withheld>'
        } else {
            ConvertTo-Json -InputObject $value -Compress
        }
    }
    return $fields
}

function Read-ObservationFields([string]$Entry) {
    $fields = @{}
    foreach ($fieldMatch in [regex]::Matches($Entry, '(?ms)^    ([a-z_]+):(.*?)(?=^    [a-z_]+:|\z)')) {
        $fields[$fieldMatch.Groups[1].Value] = $fieldMatch.Groups[2].Value.Trim()
    }
    return $fields
}

function Get-KnownEntitlementObservations {
    $path = Join-Path $PSScriptRoot 'known-entitlements.yaml'
    if (!(Test-Path -LiteralPath $path -PathType Leaf)) {
        throw 'Place known-entitlements.yaml alongside the report script before running it.'
    }

    $lines = @(Get-Content -LiteralPath $path -Encoding utf8 |
        Where-Object { $_ -notmatch '^\s*(#.*)?$' } |
        ForEach-Object { $_.TrimEnd() })
    if ($lines.Count -eq 0 -or $lines[0] -cne 'entitlements:') {
        throw 'known-entitlements.yaml must start with entitlements: and contain report-format entries.'
    }

    $known = @{}
    $entryText = ($lines | Select-Object -Skip 1) -join "`n"
    foreach ($entry in ($entryText -csplit '(?m)(?=^  - product_id: )')) {
        $entry = $entry.TrimEnd()
        if (!$entry) { continue }
        if (!$entry.StartsWith('  - product_id: ', [StringComparison]::Ordinal)) {
            throw 'known-entitlements.yaml contains an entry outside the report format.'
        }
        $header = ($entry -split "`n", 2)[0]
        $fields = Read-ObservationFields $entry
        if (!$known.ContainsKey($header)) { $known[$header] = [System.Collections.Generic.List[hashtable]]::new() }
        $known[$header].Add($fields)
    }
    return $known
}

function Get-ChangedEntitlementFields($Observed, $KnownVariants) {
    $closest = $entryFields
    foreach ($variant in $KnownVariants) {
        $changed = @(foreach ($field in $entryFields) {
            if ($Observed.ContainsKey($field) -ne $variant.ContainsKey($field) -or
                $Observed[$field] -cne $variant[$field]) { $field }
        })
        if (!$changed.Count) { return }
        if ($changed.Count -lt $closest.Count) { $closest = $changed }
    }
    return $closest
}

function New-EntitlementReport($Entitlements, $KnownObservations) {
    if (!$Entitlements.Entries.Count) { return }

    $complete = @()
    $partial = @()
    foreach ($entry in $Entitlements.Entries.GetEnumerator()) {
        if ($entry.Value -isnot [System.Collections.IDictionary]) { continue }
        $product = $entry.Key
        $catalogMatch = $Entitlements.CatalogMatches[$product]
        if ($product -cnotmatch '^com\.(roli|fxpansion)(\.[a-z0-9_-]+){1,5}$' -or $product.Length -gt 80) {
            $product = 'unlisted product ID'
            $catalogMatch = $null
        }
        $variants = $KnownObservations["  - product_id: '$product'"]
        $observed = Get-ComparableFields $entry.Value
        $changed = @(if ($variants) { Get-ChangedEntitlementFields $observed $variants }
            else { $entryFields | Where-Object { $observed.ContainsKey($_) } })
        if (!$changed.Count) { continue }

        $observation = Format-EntitlementObservation $product $entry.Value $observed $catalogMatch $KnownObservations
        $withheld = @(Get-ChangedEntitlementFields $observed @((Read-ObservationFields $observation)))
        if ($withheld.Count -or $product -ceq 'unlisted product ID') {
            $partial += "$observation`n    # Changed fields: $($changed -join ', ')"
        } else {
            $complete += $observation
        }
    }
    if (!$complete.Count -and !$partial.Count) { return }
    $fence = '```'

    $sections = @(
        if ($complete.Count) {
            @"
## Entitlement variants

Append reviewed list items under entitlements: in the known file.

$($fence)yaml
entitlements:
$(($complete | Sort-Object -CaseSensitive -Unique) -join "`n")
$fence
"@
        }
        if ($partial.Count) {
            @"
## Partial observations

These observations have withheld values or an unlisted product ID. They are for review and cannot be copied into the known file as complete variants.

$($fence)yaml
entitlements:
$(($partial | Sort-Object -CaseSensitive -Unique) -join "`n")
$fence
"@
        }
    )
    return @{
        Title = 'Entitlement response variation'
        Body = @"
$($sections -join "`n`n")

## Optional context

Add any relevant product or app version details here. Leave out account details, serial numbers, tokens, and response headers.
"@
    }
}

function Open-EntitlementIssue([string]$Title, [string]$Body) {
    Write-Host "`n$Body`n"
    if ((Read-Host 'Submit the entitlement report? [Y/n]') -notmatch '^n(o)?$') { return }

    $url = $issuePage + '?template=entitlements-report.md&title=' + [uri]::EscapeDataString($Title)
    if ($Body.Length -lt 7000) {
        $prefilled = $url + '&body=' + [uri]::EscapeDataString($Body)
        if ($prefilled.Length -le 7500) { $url = $prefilled }
    }
    if ($url -notlike '*&body=*') {
        Write-Host 'The report is too long for a prefilled URL. Copy the preview above into the issue body.'
    }
    Start-Process -FilePath $url
}

$knownObservations = Get-KnownEntitlementObservations
$entitlements = Get-RoliEntitlements
if (!$entitlements.Entries.Count) {
    Write-Host 'The response contained no entitlement entries.'
    return
}
$report = New-EntitlementReport $entitlements $knownObservations
$entitlements = $null
if (!$report) {
    Write-Host 'No new reportable entitlement variants.'
    return
}

if ($DryRun) {
    Write-Output "Title: $($report.Title)"
    Write-Output ''
    Write-Output $report.Body
    return
}

Open-EntitlementIssue -Title $report.Title -Body $report.Body
