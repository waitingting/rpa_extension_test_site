param(
  [string]$Text = "rpad browser lab",
  [int]$StartX = 300,
  [int]$StartY = 300
)

$ErrorActionPreference = "Stop"

Add-Type -AssemblyName System.Windows.Forms

[System.Windows.Forms.Cursor]::Position = New-Object System.Drawing.Point($StartX, $StartY)
Start-Sleep -Milliseconds 300
[System.Windows.Forms.SendKeys]::SendWait("{TAB}")
Start-Sleep -Milliseconds 200
[System.Windows.Forms.SendKeys]::SendWait($Text)
Start-Sleep -Milliseconds 200
[System.Windows.Forms.SendKeys]::SendWait("{ENTER}")

Write-Host "Input smoke sent: $Text"
