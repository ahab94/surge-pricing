# One-command install of the latest Surge Pricing release on Windows.
#
#   irm https://raw.githubusercontent.com/ahab94/surge-pricing/main/install.ps1 | iex
#
# Installs into %LOCALAPPDATA%\SurgePricing (no admin rights needed),
# adds a Start menu shortcut, and starts the game.
# Uninstall: delete that folder and the "Surge Pricing" Start menu shortcut.
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'   # makes Invoke-WebRequest much faster

$repo = 'ahab94/surge-pricing'
$name = 'Surge Pricing'
$dest = Join-Path $env:LOCALAPPDATA 'SurgePricing'

Write-Host 'Finding the latest release...'
$release = Invoke-RestMethod "https://api.github.com/repos/$repo/releases/latest"
$asset = $release.assets | Where-Object { $_.name -like '*-windows.zip' } | Select-Object -First 1
if (-not $asset) { throw "No Windows build in the latest release. See https://github.com/$repo/releases" }

$zip = Join-Path $env:TEMP $asset.name
Write-Host "Downloading $($asset.name)..."
Invoke-WebRequest $asset.browser_download_url -OutFile $zip -UseBasicParsing
# Verify the download against the release's published SHA-256 sums; refuse to
# install anything that doesn't match (corrupted or tampered download).
$sums = $release.assets | Where-Object { $_.name -eq 'SHA256SUMS' } | Select-Object -First 1
if (-not $sums) { Remove-Item $zip; throw 'This release has no SHA256SUMS; not installing.' }
$lines = (Invoke-WebRequest $sums.browser_download_url -UseBasicParsing).Content -split "`n"
$want = ($lines | Where-Object { $_ -match ("\s" + [regex]::Escape($asset.name) + "$") } | Select-Object -First 1) -replace '\s.*$', ''
$got = (Get-FileHash $zip -Algorithm SHA256).Hash.ToLower()
if (-not $want -or $want.Trim().ToLower() -ne $got) { Remove-Item $zip; throw "Checksum mismatch for $($asset.name); not installing." }
Write-Host 'Checksum OK.'
if (Test-Path $dest) { Remove-Item $dest -Recurse -Force }
Expand-Archive $zip -DestinationPath $dest -Force
Remove-Item $zip

$exe = Join-Path $dest 'SurgePricing.exe'
$shortcut = Join-Path ([Environment]::GetFolderPath('Programs')) "$name.lnk"
$link = (New-Object -ComObject WScript.Shell).CreateShortcut($shortcut)
$link.TargetPath = $exe
$link.WorkingDirectory = $dest
$link.Save()

Write-Host "Installed to $dest"
Write-Host "Find '$name' in the Start menu. If SmartScreen warns, choose More info > Run anyway (the game isn't code-signed)."
Start-Process $exe
