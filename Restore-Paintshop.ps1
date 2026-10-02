[CmdletBinding()]
param(
  [string]$Target = 'C:\Program Files (x86)\Steam\steamapps\common\assettocorsa\apps\lua\Paintshop',
  [switch]$AllowChangedFiles,
  [string]$BackupDirectory = $PSScriptRoot
)
$ErrorActionPreference = 'Stop'
$targetPath = [System.IO.Path]::GetFullPath($Target).TrimEnd('\')
if (-not $targetPath.EndsWith('\apps\lua\Paintshop', [System.StringComparison]::OrdinalIgnoreCase)) { throw 'Destino inválido.' }
if (Get-Process -Name acs,acs_x86 -ErrorAction SilentlyContinue) { throw 'Feche o Assetto Corsa antes de restaurar.' }
$archive = Join-Path $PSScriptRoot 'Paintshop-original-1.1.4.zip'
$main, $manifest = (Join-Path $targetPath 'Paintshop.lua'), (Join-Path $targetPath 'manifest.ini')
$originalMain = '86934F253878B1DC0CD5A9634BB5EB2B5CB2DB314FB61B361F49AED429F573B0'
$originalManifest = '426EEFB7171F6FB6919B9B5F01194F126B5F4180ED85440AD01DC04906EAFD1B'
$olderMain = 'B25604EBCC03B41E5AA195E30B1569FB0A6B1B8DEB6F37A9613C66A1CB8A65AC'
$olderManifest = '683DF6A523DCA7E23CCC9C3BE6FC850D1C70258029409F5367BD598EFC33942C'
$previousMain = 'BC37A3384578CF681EC06B045F8904A9C4D3FEBFAD8A9B9C45B7FE9DA4F307BE'
$previousManifest = '31A0A50261EFD610065F94E59B844BB349D2AFC5CB446CFA8C27077F5C915DC1'
$previousLocal3Main = '472D1CB19593A4360F5D3032711E918F57F81EF7E8DABC0CDB6FBF80F8FC7555'
$previousLocal3Manifest = '6BC46FEB6540CCE818FCF224B9F9021DE1EB37E39B4EFC3F021D4310F3A2246F'
$enhancedMain = '01D056F4F496F6858D4CE0391EEF3B8CEFE06ACBF30C4B7FDE3932C2F7238598'
$enhancedManifest = '6C57326C32609762F2CB9E91C013923424ABFCEE6C8A8F8470BF94C66D49E467'
function FileHash([string]$Path) { (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash }
$currentPair = "$(FileHash $main)|$(FileHash $manifest)"
if (-not $AllowChangedFiles -and $currentPair -notin @("$originalMain|$originalManifest","$olderMain|$olderManifest","$previousMain|$previousManifest","$previousLocal3Main|$previousLocal3Manifest","$enhancedMain|$enhancedManifest")) {
  throw 'A instalação mudou. Compare seus arquivos antes de usar -AllowChangedFiles.'
}
$staging = Join-Path ([System.IO.Path]::GetTempPath()) ('paintshop-restore-' + [guid]::NewGuid().ToString('N'))
New-Item -Path $staging -ItemType Directory | Out-Null
Expand-Archive -LiteralPath $archive -DestinationPath $staging
$restoredMain = Join-Path $staging 'Paintshop\Paintshop.lua'
$restoredManifest = Join-Path $staging 'Paintshop\manifest.ini'
if ((FileHash $restoredMain) -ne $originalMain -or (FileHash $restoredManifest) -ne $originalManifest) { throw 'O backup original não corresponde à versão analisada.' }
$snapshot = Join-Path $BackupDirectory ('Paintshop-before-restore-' + [guid]::NewGuid().ToString('N').Substring(0,8))
New-Item -Path $snapshot -ItemType Directory | Out-Null
Copy-Item -LiteralPath $main -Destination (Join-Path $snapshot 'Paintshop.lua')
Copy-Item -LiteralPath $manifest -Destination (Join-Path $snapshot 'manifest.ini')
try {
  Copy-Item -LiteralPath $restoredMain -Destination $main -Force
  Copy-Item -LiteralPath $restoredManifest -Destination $manifest -Force
  if ((FileHash $main) -ne $originalMain -or (FileHash $manifest) -ne $originalManifest) { throw 'Falha na verificação após restauração.' }
} catch {
  Copy-Item -LiteralPath (Join-Path $snapshot 'Paintshop.lua') -Destination $main -Force
  Copy-Item -LiteralPath (Join-Path $snapshot 'manifest.ini') -Destination $manifest -Force
  throw
}
Write-Output "Paintshop 1.1.4 original restaurado. Código anterior preservado em: $snapshot"
