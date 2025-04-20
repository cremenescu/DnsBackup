$zonesPath = "C:\Windows\System32\dns"
Get-ChildItem -Path $zonesPath -Filter "*.dns" |
Where-Object { $_.BaseName -notin @("cache", "TrustAnchors") } |
ForEach-Object {
    $zoneName = $_.BaseName
    if (-not (Get-DnsServerZone -Name $zoneName -ErrorAction SilentlyContinue)) {
        Write-Host "Creating zone: $zoneName"
        Add-DnsServerPrimaryZone -Name $zoneName -ZoneFile "$zoneName.dns" -DynamicUpdate None
    } else {
        Write-Host "Skipping existing zone: $zoneName" -ForegroundColor DarkGray
    }
}
