# generate_zones_from_backup.ps1
# Generează zones.csv pe baza fișierelor .dns și dns_zones.reg dintr-un backup DNS

param (
    [Parameter(Mandatory = $true)]
    [string]$BackupPath
)

$dnsFolder = Join-Path $BackupPath "zones"
$regFile   = Join-Path $BackupPath "dns_zones.reg"
$outputCsv = Join-Path $BackupPath "zones.csv"

if (-not (Test-Path $dnsFolder)) {
    Write-Host "[ERROR] Folderul cu fișiere .dns nu există: $dnsFolder" -ForegroundColor Red
    exit 1
}

if (-not (Test-Path $regFile)) {
    Write-Host "[ERROR] Fișierul dns_zones.reg nu a fost găsit: $regFile" -ForegroundColor Red
    exit 1
}

$dnsFiles = Get-ChildItem -Path $dnsFolder -Filter "*.dns" | Where-Object { $_.BaseName -notin @("cache", "TrustAnchors") }
$regLines = Get-Content $regFile -Encoding Unicode

$zoneList = @()
foreach ($file in $dnsFiles) {
    $zoneName = $file.BaseName
    $fileName = $file.Name
    $zoneType = "Primary"
    $masters  = ""

    # Caută blocul din .reg pentru zona curentă
    $startIndex = ($regLines | Select-String -Pattern "\\Zones\\$zoneName\]" -SimpleMatch).LineNumber
    if ($startIndex) {
        $endIndex = ($regLines[$startIndex..($regLines.Count - 1)] | Select-String -Pattern "^\[" -SimpleMatch -NotMatch | Select-Object -First 1).LineNumber
        $zoneBlock = if ($endIndex) { $regLines[$startIndex..($startIndex + $endIndex - 2)] } else { $regLines[$startIndex..($regLines.Count - 1)] }

        foreach ($line in $zoneBlock) {
            if ($line -match '"ZoneType"=dword:(\d+)') {
                switch ($matches[1]) {
                    "1" { $zoneType = "Secondary" }
                    "2" { $zoneType = "Stub" } # not used here
                    default { $zoneType = "Primary" }
                }
            }
            if ($line -match '"MasterServers"=hex\(7\):(.+?)\\0') {
                $hex = $matches[1] -replace ",00", ""
                $masters = ($hex -split ",") -join ""
            }
        }
    }

    $zoneList += [PSCustomObject]@{
        ZoneName  = $zoneName
        FileName  = $fileName
        ZoneType  = $zoneType
        MasterIPs = $masters
    }
}

$zoneList | Export-Csv -Path $outputCsv -NoTypeInformation -Encoding UTF8
Write-Host "[✓] zones.csv generat: $outputCsv" -ForegroundColor Green
