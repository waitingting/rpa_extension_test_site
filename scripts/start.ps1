$ErrorActionPreference = "Stop"

$root = Split-Path -Parent $PSScriptRoot
$httpServer = Join-Path $root "node_modules\.bin\http-server.cmd"
if (-not (Test-Path $httpServer)) {
  $httpServer = "http-server"
}

$servers = @(
  @{ Name = "main"; Path = "sites\extension-fixtures\main"; Host = "127.0.0.1"; Port = 8007 },
  @{ Name = "cross-a"; Path = "sites\extension-fixtures\cross-a"; Host = "127.0.0.1"; Port = 8008 },
  @{ Name = "cross-b"; Path = "sites\extension-fixtures\cross-b"; Host = "127.0.0.1"; Port = 8009 }
)

foreach ($server in $servers) {
  $sitePath = Join-Path $root $server.Path
  $args = @(
    $sitePath,
    "-a", $server.Host,
    "-p", [string]$server.Port,
    "-c-1",
    "--cors"
  )
  $process = Start-Process -FilePath $httpServer -ArgumentList $args -WorkingDirectory $root -PassThru -WindowStyle Hidden
  Write-Host ("{0,-8} http://{1}:{2}/ pid={3}" -f $server.Name, $server.Host, $server.Port, $process.Id)
}

Write-Host ""
Write-Host "Open http://127.0.0.1:8007/ in Chrome/Edge/360/Firefox."
Write-Host "Press Ctrl+C here when done, then stop the printed PIDs if needed."

while ($true) {
  Start-Sleep -Seconds 3600
}
