$ErrorActionPreference = 'Stop'
Set-Location $PSScriptRoot
# El servidor pide administrador para que el juego reciba las teclas.
python -m PyInstaller --noconfirm --onefile --windowed --uac-admin --name SC-Companion-Server server.py
python -m PyInstaller --noconfirm --onefile --windowed --name SC-Companion-Setup `
    --add-data "dist\SC-Companion-Server.exe;." installer.py
Write-Host "Listo: $PSScriptRoot\dist\SC-Companion-Setup.exe"
