# Prints this PC's LAN IPv4 address (the adapter that has a default gateway)
$cfg = Get-NetIPConfiguration | Where-Object { $_.IPv4DefaultGateway -ne $null -and $_.NetAdapter.Status -eq 'Up' } | Select-Object -First 1
if ($cfg) { Write-Output $cfg.IPv4Address.IPAddress }
