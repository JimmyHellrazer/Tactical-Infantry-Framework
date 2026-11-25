$repo = Split-Path -Parent $PSScriptRoot
Copy-Item 'K:\SteamLibrary\steamapps\common\GarrysMod\garrysmod\addons\TIFDIDDY\*.md' (Join-Path $repo 'docs') -Force
Write-Output "docs/ synced from TIFDIDDY"
