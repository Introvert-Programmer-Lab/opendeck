# Flash the OpenDeck firmware over its USB cable, no buttons needed.
# The running firmware is a USB composite device (CDC + HID); we ask it to reboot
# into the ROM bootloader ({"t":"dfu"}), wait for the USB-Serial/JTAG port, then flash.
#   powershell -ExecutionPolicy Bypass -File tools\flash.ps1            # app only (keeps your deck)
#   powershell -ExecutionPolicy Bypass -File tools\flash.ps1 -All       # bootloader + app + default deck
param([switch]$All)
$ErrorActionPreference = 'Stop'
$repo = Split-Path -Parent $PSScriptRoot
function Get-DeckPorts($pid_) {
  Get-CimInstance Win32_PnPEntity | Where-Object { $_.DeviceID -match "VID_303A&PID_$pid_" -and $_.Name -match '\((COM\d+)\)' } |
    ForEach-Object { [regex]::Match($_.Name, 'COM\d+').Value }
}
$jtag = @(Get-DeckPorts '1001')
if (-not $jtag) {
  $cdc = @(Get-DeckPorts '4004')
  if (-not $cdc) { throw 'No OpenDeck found. Plug it in (data cable), or hold BOOT + tap RST to force download mode.' }
  Write-Host "Asking the deck on $($cdc[0]) to enter download mode..."
  $sp = New-Object System.IO.Ports.SerialPort $cdc[0], 115200
  $sp.Open(); $sp.WriteLine('{"t":"dfu"}'); Start-Sleep -Milliseconds 300; $sp.Close()
  for ($i = 0; $i -lt 40 -and -not $jtag; $i++) { Start-Sleep -Milliseconds 250; $jtag = @(Get-DeckPorts '1001') }
  if (-not $jtag) { throw 'The deck did not come back in download mode. Hold BOOT, tap RST, release BOOT, and run again.' }
}
$port = $jtag[0]
Write-Host "Flashing via $port"
$images = if ($All) { @('0x0', 'build\bootloader\bootloader.bin', '0x8000', 'build\partition_table\partition-table.bin', '0x10000', 'build\opendeck.bin', '0x310000', 'build\storage.bin') }
          else { @('0x10000', 'build\opendeck.bin') }
& powershell -ExecutionPolicy Bypass -File (Join-Path $repo 'tools\idf.ps1') --esptool --chip esp32s3 --port $port --baud 921600 --before no_reset --after hard_reset write_flash @images
exit $LASTEXITCODE
