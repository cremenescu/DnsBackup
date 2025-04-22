 param (
    [switch]$Export,
    [switch]$Import,
    [string]$Path,
    [switch]$IncludeRegistry,
    [switch]$CreateZones
)

<#
    DnsBackup.ps1
    - Exportă și importă configurația DNS (fișiere .dns + registry)
    - Exportă doar definițiile zonelor active din registry către un singur fișier .reg
    - Mesaje verbose pas-cu-pas
#>

# -----------------------------------------
# 1) START & PARAMETERS
# -----------------------------------------
Write-Host "`n[DEBUG] Script start at $(Get-Date)" -ForegroundColor Cyan
Write-Host "[DEBUG] Params: Export=$Export, Import=$Import, Path='$Path', IncludeRegistry=$IncludeRegistry, CreateZones=$CreateZones" -ForegroundColor Cyan

if (-not ($Export -or $Import)) {
    Write-Host "[ERROR] Must specify -Export or -Import" -ForegroundColor Red
    exit 1
}

# Calea implicită pentru fișierele DNS
$dnsPath = "$env:SystemRoot\System32\dns"

# -----------------------------------------
# EXPORT SECTION
# -----------------------------------------
if ($Export) {
    Write-Host "`n=== EXPORT MODE ===" -ForegroundColor Green

    # Step 1) Prepare folders
    Write-Host "[Step 1/11] Preparing export folders..." -ForegroundColor Cyan
    if (-not $Path) {
        $Path = "C:\DNS-Backup-$(Get-Date -Format 'yyyyMMdd-HHmmss')"
        Write-Host " -> No -Path given, defaulting to: $Path"
    } elseif (Test-Path $Path) {
        Write-Host "[ERROR] Path already exists: $Path" -ForegroundColor Red
        exit 1
    } else {
        New-Item -ItemType Directory -Path $Path -Force | Out-Null
        Write-Host " -> Created root folder: $Path"
    }
    $zoneFolder = Join-Path $Path "zones"
    New-Item -ItemType Directory -Path $zoneFolder -Force | Out-Null
    Write-Host " -> Created 'zones' folder: $zoneFolder"

    # Step 2) Export DNS service config
#    Write-Host "`n[Step 2/11] Exporting DNS service registry..." -ForegroundColor Cyan
#    $regFile = Join-Path $Path "dns_config.reg"
#    reg export "HKLM\SYSTEM\CurrentControlSet\Services\DNS" $regFile /y > $null
#    if (Test-Path $regFile) {
#        Write-Host "    • Saved service config to: $regFile"
#    } else {
#        Write-Host "    X Failed to export DNS service config" -ForegroundColor Red
#    }

    # Step 3) Export active zones registry definitions to single file
    Write-Host "`n[Step 3/11] Exporting active zones definitions..." -ForegroundColor Cyan

    $dnsZones      = Get-DnsServerZone | Where-Object { $_.ZoneName -ne 'TrustAnchors' }
    $zonesRegFile  = Join-Path $Path 'dns_zones.reg'
    'Windows Registry Editor Version 5.00' | Out-File -FilePath $zonesRegFile -Encoding Unicode

    $zonesKeyBase  = 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\DNS Server\Zones'

    foreach ($zone in $dnsZones) {
    $name      = $zone.ZoneName
    $dnsFile   = Join-Path $dnsPath "$name.dns"

    # Exportăm zona dacă e Conditional Forwarder sau dacă e Primary/Secondary cu fișier .dns
    if ((Test-Path "$zonesKeyBase\$name") -and 
        (($zone.ZoneType -eq 'Forwarder') -or (Test-Path $dnsFile))) {
        $tempFile = Join-Path $env:TEMP "$name.reg"
        Write-Host "    • Exporting '$name' (type: $($zone.ZoneType)) to temp file" -ForegroundColor Yellow
        reg export "HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion\DNS Server\Zones\$name" $tempFile /y > $null

        Get-Content $tempFile -Encoding Unicode | Select-Object -Skip 2 |
            Out-File -FilePath $zonesRegFile -Encoding Unicode -Append

        Remove-Item $tempFile -Force
    }
    else {
        Write-Host "    • (skip) '$name' – registry key or .dns file missing" -ForegroundColor DarkGray
    }
    }
    Write-Host "    • Aggregated registry saved to: $zonesRegFile"

    # Step 4) Enumerate zones
    Write-Host "`n[Step 4/11] Enumerating DNS zones..." -ForegroundColor Cyan
    Write-Host "    • Active zones count: $($dnsZones.Count)"

    # Step 5) Scan for DNSSEC
    Write-Host "`n[Step 5/11] Scanning zone files for DNSSEC..." -ForegroundColor Cyan
    $secondaryZones = $dnsZones | Where-Object { $_.ZoneType -eq 'Secondary' }
    $zonesList = @()
    $dnssecDetected = $false
    foreach ($zone in $dnsZones) {
        Write-Host "`n -> Zone: $($zone.ZoneName) [Type: $($zone.ZoneType)]" -ForegroundColor Yellow
        $fileName = "$($zone.ZoneName).dns"
        $fullPath = Join-Path $dnsPath $fileName
        if (-not (Test-Path $fullPath)) {
            Write-Host "    [SKIP] File not found: $fileName" -ForegroundColor DarkGray
            continue
        }
        Write-Host "    [OK] Found: $fileName"
        $foundSig = $false
        $lines = Get-Content $fullPath
        for ($i=0; $i -lt $lines.Count; $i++) {
            $l = $lines[$i].Trim()
            if ($l -like '' -or $l.StartsWith(';')) { continue }
            if ($l -match '^\S+\s+\d+\s+IN\s+(RRSIG|DNSKEY|NSEC|DS)\b') {
                Write-Host "    [DNSSEC] line $($i+1): $l" -ForegroundColor Magenta
                $foundSig = $true; $dnssecDetected = $true; break
            }
        }
        Write-Host "    [INFO] DNSSEC detected: $foundSig"
        $masters = ''
        if ($zone.ZoneType -eq 'Secondary') {
            $masters = ($secondaryZones | Where-Object { $_.ZoneName -eq $zone.ZoneName }).MasterServers -join ','
            Write-Host "    [INFO] MasterServers: $masters"
        }
        $zonesList += [PSCustomObject]@{
            ZoneName  = $zone.ZoneName
            FileName  = $fileName
            ZoneType  = $zone.ZoneType
            MasterIPs = $masters
            DnsSec    = $foundSig
        }
    }
    Write-Host "`n[DEBUG] Overall DNSSEC detected: $dnssecDetected" -ForegroundColor Cyan

    # Step 6) Copy zone files
    Write-Host "`n[Step 6/11] Copying zone files..." -ForegroundColor Cyan
    foreach ($z in $zonesList) {
        Write-Host "    • Copying $($z.FileName)"
        Copy-Item (Join-Path $dnsPath $z.FileName) -Destination (Join-Path $zoneFolder $z.FileName) -Force
    }
    Write-Host "    [DONE] Copied $($zonesList.Count) files"

    # Step 7) Handle TrustAnchors
    Write-Host "`n[Step 7/11] Handling TrustAnchors.dns..." -ForegroundColor Cyan
    if ($dnssecDetected) {
        Write-Host "    • DNSSEC present – copying TrustAnchors.dns"
        $ta = Join-Path $dnsPath 'TrustAnchors.dns'
        if (Test-Path $ta) { Copy-Item $ta -Destination (Join-Path $zoneFolder 'TrustAnchors.dns') -Force; Write-Host '    [OK] TrustAnchors.dns copied' }
        else           { Write-Host '    [SKIP] TrustAnchors.dns not found' -ForegroundColor DarkGray }
    } else {
        Write-Host '    • No DNSSEC – skip TrustAnchors.dns' -ForegroundColor DarkGray
    }

    # Step 8) Save CSV
    Write-Host "`n[Step 8/11] Saving metadata CSV..." -ForegroundColor Cyan
    $csvFile = Join-Path $Path 'zones.csv'
    $zonesList | Export-Csv -Path $csvFile -NoTypeInformation -Encoding UTF8
    Write-Host "    [OK] CSV saved: $csvFile"

    # Step 9) Create ZIP
    Write-Host "`n[Step 9/11] Creating ZIP archive..." -ForegroundColor Cyan
    $zipPath = "$Path.zip"
    if (Get-Command Compress-Archive -ErrorAction SilentlyContinue) {
        Write-Host '    • Using Compress-Archive'
        Compress-Archive -Path "$Path\*" -DestinationPath $zipPath -Force
    } else {
        Write-Host '    • Using .NET ZipFile fallback'
        Add-Type -AssemblyName System.IO.Compression.FileSystem
        [IO.Compression.ZipFile]::CreateFromDirectory($Path, $zipPath)
    }
    if (Test-Path $zipPath) { Write-Host "[✓] EXPORT COMPLETE – $zipPath" -ForegroundColor Green }
    else                    { Write-Host "[ERROR] ZIP failed" -ForegroundColor Red }

    # Step 10) End
    Write-Host "`n[DEBUG] Export finished at $(Get-Date)" -ForegroundColor Cyan
}

# -----------------------------------------
# IMPORT SECTION
# -----------------------------------------
if ($Import) {
    Write-Host "`n=== IMPORT MODE ===" -ForegroundColor Green

    # Step 1) Validate Path
    Write-Host "[Step 1/6] Validating import path..." -ForegroundColor Cyan
    if (-not (Test-Path $Path)) { Write-Host "[ERROR] Path not found: $Path" -ForegroundColor Red; exit 1 }

    # Step 2) Import service registry
    if ($IncludeRegistry) {
        Write-Host "`n[Step 2/6] Importing DNS service registry..." -ForegroundColor Cyan
#        $regFile = Join-Path $Path 'dns_config.reg'
#        if (Test-Path $regFile) { reg import $regFile > $null; Write-Host "    [OK] Service registry imported" }
#        else                  { Write-Host "    [SKIP] dns_config.reg missing" -ForegroundColor DarkGray }

        # Import zones registry definitions
        Write-Host "`n[Step 3/6] Importing zones registry definitions..." -ForegroundColor Cyan
        $zonesRegFile = Join-Path $Path 'dns_zones.reg'
        if (Test-Path $zonesRegFile) { reg import $zonesRegFile > $null; Write-Host "    [OK] Zones registry imported" }
        else                         { Write-Host "    [SKIP] dns_zones.reg missing" -ForegroundColor DarkGray }
    }

    # Step 4) Copy .dns files
    Write-Host "`n[Step 4/6] Copying .dns files..." -ForegroundColor Cyan
    $zoneFolder = Join-Path $Path 'zones'
    $files = Get-ChildItem $zoneFolder -Filter '*.dns'
    Write-Host "    • Files to copy: $($files.Count)"
    foreach ($f in $files) { Write-Host "    • Copying $($f.Name)"; Copy-Item $f.FullName -Destination $dnsPath -Force }

    # Step 5) Restore TrustAnchors
    Write-Host "`n[Step 5/6] Restoring TrustAnchors.dns..." -ForegroundColor Cyan
    $taFile = Join-Path $zoneFolder 'TrustAnchors.dns'
    if (Test-Path $taFile) { Copy-Item $taFile -Destination $dnsPath -Force; Write-Host "    [OK] TrustAnchors.dns restored" }
    else                   { Write-Host "    [SKIP] TrustAnchors.dns missing" -ForegroundColor DarkGray }

    # Step 6) Recreate zones optionally
    if ($CreateZones) {
        Write-Host "`n[Step 6/6] Recreating zones from CSV..." -ForegroundColor Cyan
        $csvFile = Join-Path $Path 'zones.csv'
        if (-not (Test-Path $csvFile)) { Write-Host "[ERROR] zones.csv missing" -ForegroundColor Red; exit 1 }
        $csv = Import-Csv $csvFile
        Write-Host "    • CSV entries: $($csv.Count)"
        foreach ($z in $csv) {
            if (Get-DnsServerZone -Name $z.ZoneName -ErrorAction SilentlyContinue) { Write-Host "    • Zone exists: $($z.ZoneName)" -ForegroundColor DarkGray }
            elseif ($z.ZoneType -eq 'Primary')     { Write-Host "    • Creating Primary: $($z.ZoneName)"; Add-DnsServerPrimaryZone -Name $z.ZoneName -ZoneFile $z.FileName -DynamicUpdate None }
            elseif ($z.ZoneType -eq 'Secondary')   {
                $masters = $z.MasterIPs -split ',' | Where-Object { $_ }
                if ($masters) { Write-Host "    • Creating Secondary: $($z.ZoneName)"; Add-DnsServerSecondaryZone -Name $z.ZoneName -ZoneFile $z.FileName -MasterServers $masters }
                else          { Write-Host "    • Skipped Secondary (no masters): $($z.ZoneName)" -ForegroundColor DarkGray }
            }
        }
    }

    Write-Host "`n[✓] IMPORT COMPLETE at $(Get-Date)" -ForegroundColor Green
}

Write-Host "`n[DEBUG] Script end at $(Get-Date)" -ForegroundColor Cyan
 
