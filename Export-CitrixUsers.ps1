#requires -Version 5.1

# --- Nastavení ---
$Server     = 'http://DDC01.example.local'  # HTTP nebo HTTPS
$MonthsBack = 3                           # Počet dokončených měsíců
$OutputDir  = $PSScriptRoot

$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Net.Http

if ($MonthsBack -lt 1 -or $MonthsBack -ne [int]$MonthsBack) {
    throw 'MonthsBack musí být celé číslo větší než 0.'
}

# --- Adresa API ---
$Server = $Server.Trim().TrimEnd('/')

if ($Server -notmatch '^[a-zA-Z][a-zA-Z0-9+.-]*://') {
    $Server = 'http://' + $Server
}

$serverUri = [uri]$Server

if (
    -not $serverUri.IsAbsoluteUri -or
    $serverUri.Scheme -notin @('http', 'https') -or
    [string]::IsNullOrWhiteSpace($serverUri.Host)
) {
    throw "Neplatná adresa serveru: $Server"
}

if ($serverUri.AbsolutePath -ne '/' -or $serverUri.Query -or $serverUri.Fragment) {
    throw 'Zadej pouze adresu serveru, například http://ddc01.firma.local'
}

$baseUri = [uri]::new(
    $serverUri,
    '/Citrix/Monitor/OData/v4/Data/'
)

# --- NTLM: aktuální Windows účet ---
$cache = [Net.CredentialCache]::new()
$cache.Add(
    $baseUri,
    'NTLM',
    [Net.CredentialCache]::DefaultNetworkCredentials
)

$handler = [Net.Http.HttpClientHandler]::new()
$handler.Credentials = $cache
$handler.AllowAutoRedirect = $false

$client = [Net.Http.HttpClient]::new($handler)
$client.Timeout = [TimeSpan]::FromMinutes(5)
$client.DefaultRequestHeaders.Accept.ParseAdd('application/json')

# --- České časové pásmo ---
$tz = [TimeZoneInfo]::FindSystemTimeZoneById(
    'Central Europe Standard Time'
)

$nowLocal = [TimeZoneInfo]::ConvertTimeFromUtc([datetime]::UtcNow, $tz)
$currentMonth = [datetime]::new($nowLocal.Year, $nowLocal.Month, 1)

$summary = @()

try {
    New-Item -ItemType Directory -Path $OutputDir -Force | Out-Null

    # --- Každý dokončený měsíc samostatně ---
    for ($i = 1; $i -le $MonthsBack; $i++) {
        $start = $currentMonth.AddMonths(-$i)
        $month = $start.ToString('yyyy-MM')
        $csv = Join-Path $OutputDir "Citrix-Users-$month.csv"

        Write-Host "Zpracovávám měsíc $month..."

        $from = [TimeZoneInfo]::ConvertTimeToUtc(
            $start, $tz
        ).ToString("yyyy-MM-dd'T'HH:mm:ss'Z'")

        $to = [TimeZoneInfo]::ConvertTimeToUtc(
            $start.AddMonths(1), $tz
        ).ToString("yyyy-MM-dd'T'HH:mm:ss'Z'")

        # Připojení včetně reconnectů během měsíce
        $filter = [uri]::EscapeDataString(
            "EstablishmentDate ge $from and EstablishmentDate lt $to"
        )
        $expand = [uri]::EscapeDataString(
            'Session($select=UserId;$expand=User($select=UserName))'
        )

        $query = 'Connections?$filter=' + $filter +
            '&$select=Id,IsReconnect&$orderby=Id&$expand=' + $expand

        $requestUri = [uri]::new($baseUri, $query)

        # --- Načtení všech stránek ---
        $connections = @(
            while ($null -ne $requestUri) {
                if (-not $baseUri.IsBaseOf($requestUri)) {
                    throw "Adresa požadavku je mimo původní API: $requestUri"
                }

                $json = $client.GetStringAsync(
                    $requestUri
                ).GetAwaiter().GetResult()

                $page = $json | ConvertFrom-Json

                if ($null -eq $page.PSObject.Properties['value']) {
                    throw 'API nevrátilo očekávaná OData data.'
                }

                $page.value

                $next = [string]$page.'@odata.nextLink'

                if ([string]::IsNullOrWhiteSpace($next)) {
                    $requestUri = $null
                }
                else {
                    $requestUri = [uri]::new($requestUri, $next)
                }
            }
        )

        # --- Jeden řádek na unikátní UserId ---
        $users = @(
            $connections |
                Sort-Object Id -Unique |
                Where-Object {
                    $null -ne $_.Session.User -and
                    $null -ne $_.Session.UserId
                } |
                Group-Object { $_.Session.UserId } |
                ForEach-Object {
                    [pscustomobject]@{
                        Month           = $month
                        UserId          = $_.Group[0].Session.UserId
                        UserName        = $_.Group[0].Session.User.UserName
                        ConnectionCount = $_.Count
                        ReconnectCount  = @(
                            $_.Group |
                                Where-Object { $_.IsReconnect -eq $true }
                        ).Count
                    }
                }
        )

        # --- Samostatné CSV ---
        if ($users.Count -gt 0) {
            $users |
                Sort-Object UserName |
                Export-Csv -LiteralPath $csv `
                    -Delimiter ';' -NoTypeInformation -Encoding UTF8
        }
        else {
            '"Month";"UserId";"UserName";"ConnectionCount";"ReconnectCount"' |
                Set-Content -LiteralPath $csv -Encoding UTF8
        }

        $summary += [pscustomobject]@{
            Mesic     = $month
            Uzivatele = $users.Count
        }

        Write-Host "Uloženo: $csv"
    }

    # --- Závěrečný přehled od nejstaršího měsíce ---
    Write-Host "`nPočet unikátních uživatelů podle měsíce:"
    $summary | Sort-Object Mesic | Format-Table -AutoSize
}
finally {
    $client.Dispose()
}
