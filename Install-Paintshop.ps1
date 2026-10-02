[CmdletBinding()]
param(
  [string]$Target = 'C:\Program Files (x86)\Steam\steamapps\common\assettocorsa\apps\lua\Paintshop',
  [string]$BackupDirectory = $PSScriptRoot
)
$ErrorActionPreference = 'Stop'
$source = Join-Path $PSScriptRoot 'Paintshop'
$targetPath = [System.IO.Path]::GetFullPath($Target).TrimEnd('\')
if (-not $targetPath.EndsWith('\apps\lua\Paintshop', [System.StringComparison]::OrdinalIgnoreCase)) {
  throw 'O destino deve ser uma pasta apps\lua\Paintshop.'
}
if (-not (Test-Path -LiteralPath $targetPath -PathType Container)) { throw 'Paintshop não encontrado no destino.' }
if (Get-Process -Name acs,acs_x86 -ErrorAction SilentlyContinue) { throw 'Feche o Assetto Corsa antes de instalar.' }
$main = Join-Path $targetPath 'Paintshop.lua'
$manifest = Join-Path $targetPath 'manifest.ini'
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
if ((FileHash (Join-Path $source 'Paintshop.lua')) -ne $enhancedMain -or
    (FileHash (Join-Path $source 'manifest.ini')) -ne $enhancedManifest) {
  throw 'O pacote mudou desde a validação. Revalide o código antes de instalar.'
}
$currentMain, $currentManifest = (FileHash $main), (FileHash $manifest)
$currentPair = "$currentMain|$currentManifest"
if ($currentPair -notin @("$originalMain|$originalManifest","$olderMain|$olderManifest","$previousMain|$previousManifest","$previousLocal3Main|$previousLocal3Manifest","$enhancedMain|$enhancedManifest")) {
  throw 'Os arquivos instalados diferem da versão analisada. Instalação interrompida para preservar suas alterações.'
}
$files = @('src\history.lua','src\files.lua','src\project.lua','src\portuguese_ui.lua','manifest.ini','Paintshop.lua')
$knownModuleHashes = @{
  'src\history.lua' = @('82290D0303918A8DC4073F18CA39CFAD20AC2128A67593DCCD3188184CC09580')
  'src\files.lua' = @('0113478642D07C2D291312B214CE438FC03CB052D450972C8AAEA592BBF29D26','946B6F4538D62ADA499863C54A3D8744AA8A538C540E7C24A69C4FC9A6D97E10')
  'src\project.lua' = @('928083D599A66B358309F4C4270AC90331273074324BABAC05A317303E956B34','7E20BDF0763F7F55492A1BEDC0C4521AE604989BDD005E7DB4ADC4F68549EA25','337EFDA34B9C6947D6713FA5E294DCBC40F87278AC37677DE1FF613726574EE2')
  'src\portuguese_ui.lua' = @('32BC46A9015FD25BF6D7ABD1F1E7FA0E83655999BBA9B86583C29D999EB11C51')
}
foreach ($relative in $files) {
  if (-not (Test-Path -LiteralPath (Join-Path $source $relative) -PathType Leaf)) { throw "Arquivo ausente: $relative" }
  if ($relative.StartsWith('src\')) {
    $existing = Join-Path $targetPath $relative
    if ((Test-Path -LiteralPath $existing) -and (FileHash $existing) -notin $knownModuleHashes[$relative]) {
      throw "Módulo existente com conteúdo diferente: $relative"
    }
  }
}
$snapshot = Join-Path $BackupDirectory ('Paintshop-before-install-' + (Get-Date -Format 'yyyyMMdd-HHmmss') + '-' + [guid]::NewGuid().ToString('N').Substring(0,8))
New-Item -Path $snapshot -ItemType Directory | Out-Null
New-Item -Path (Join-Path $snapshot 'src') -ItemType Directory | Out-Null
foreach ($relative in $files) {
  $existing = Join-Path $targetPath $relative
  if (Test-Path -LiteralPath $existing -PathType Leaf) {
    Copy-Item -LiteralPath $existing -Destination (Join-Path $snapshot $relative)
  }
}
try {
  $modules = Join-Path $targetPath 'src'
  if (-not (Test-Path -LiteralPath $modules)) { New-Item -Path $modules -ItemType Directory | Out-Null }
  foreach ($relative in $files) {
    $from, $to = (Join-Path $source $relative), (Join-Path $targetPath $relative)
    Copy-Item -LiteralPath $from -Destination $to -Force
    if ((FileHash $from) -ne (FileHash $to)) { throw "Falha na verificação: $relative" }
  }
} catch {
  foreach ($relative in $files) {
    $saved, $installed = (Join-Path $snapshot $relative), (Join-Path $targetPath $relative)
    if (Test-Path -LiteralPath $saved -PathType Leaf) { Copy-Item -LiteralPath $saved -Destination $installed -Force }
    elseif (Test-Path -LiteralPath $installed -PathType Leaf) { Remove-Item -LiteralPath $installed -Force }
  }
  throw
}
Write-Output 'Paintshop 1.1.4-local.4 instalado. Seis arquivos verificados por SHA256.'
Write-Output "Destino: $targetPath"
Write-Output "Backup anterior à instalação: $snapshot"
