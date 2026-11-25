# Refresh addon/ from the working copy in Garry's Mod (run from the repo root, or anywhere).
#   powershell -ExecutionPolicy Bypass -File tools\sync_addon.ps1
$repo = Split-Path -Parent $PSScriptRoot
$game = 'K:\SteamLibrary\steamapps\common\GarrysMod\garrysmod\addons\tactical_infantry_framework'
robocopy $game (Join-Path $repo 'addon') /MIR /NFL /NDL /NJH /XD __pycache__ | Out-Null
Copy-Item 'K:\SteamLibrary\steamapps\common\GarrysMod\garrysmod\addons\TIFDIDDY\*.md' (Join-Path $repo 'docs') -Force
Write-Output "addon/ and docs/ synced from $game"
