# reset_dns_zones.ps1
# Șterge toate zonele DNS definite în registry, fișierele .dns și din DNS Server (live)

# Verifică permisiuni administrative
if (-not ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole('Administrator')) {
    Write-Host "[ERROR] Scriptul trebuie rulat ca Administrator." -ForegroundColor Red
    exit 1
}

Write-Host "[INFO] Încep ștergerea zonelor din registry, fișiere și DNS Server..." -ForegroundColor Cyan

# 1. Șterge zonele din registry (definiții rămase)
$zonesKey = "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\DNS Server\Zones"
if (Test-Path $zonesKey) {
    Get-ChildItem -Path $zonesKey | ForEach-Object {
        Write-Host " - Șterg din registry: $($_.PSChildName)"
        Remove-Item -Path $_.PSPath -Recurse -Force
    }
} else {
    Write-Host "[INFO] Cheia registry pentru zone DNS nu există (posibil deja curatată)."
}

# 2. Șterge fișierele .dns corespunzătoare (exceptând cache și TrustAnchors)
$dnsPath = "$env:SystemRoot\System32\dns"
Get-ChildItem -Path $dnsPath -Filter "*.dns" | Where-Object {
    $_.BaseName -notin @("cache", "TrustAnchors")
} | ForEach-Object {
    Write-Host " - Șterg fișier: $($_.Name)"
    Remove-Item $_.FullName -Force
}

# 3. Șterge zonele active din DNS Server (care apar în Get-DnsServerZone)
Write-Host "`n[INFO] Ștergere din DNS Server (live)..." -ForegroundColor Cyan
$activeZones = Get-DnsServerZone | Where-Object { $_.ZoneName -notin @("TrustAnchors", "0.in-addr.arpa", "127.in-addr.arpa", "255.in-addr.arpa") }
foreach ($zone in $activeZones) {
    Write-Host " - Șterg din DNS Server: $($zone.ZoneName)"
    try {
        Remove-DnsServerZone -Name $zone.ZoneName -Force -ErrorAction Stop
    } catch {
        Write-Host "   [WARNING] Nu am putut șterge: $($zone.ZoneName) — $($_.Exception.Message)" -ForegroundColor Yellow
    }
}

Write-Host "[✓] Resetare completă a zonelor DNS finalizată." -ForegroundColor Green
