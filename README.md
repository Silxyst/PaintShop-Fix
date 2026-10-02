# Paintshop — edição local 1.1.4-local.4

Versão aprimorada do app Lua Paintshop para Assetto Corsa + Custom Shaders Patch, baseada no projeto [ac-custom-shaders-patch/app-paintshop](https://github.com/ac-custom-shaders-patch/app-paintshop).

## O que inclui

- A pasta `Paintshop/` contém o app completo, seus módulos Lua e recursos (pincéis, adesivos, fonte e ícones).
- Camadas editáveis e projetos `.pspaint`, rascunho de recuperação, histórico limitado por memória e autosaves rotativos.
- Salvamento seguro com arquivo temporário e backup antes de substituir arquivos.
- Interface em português, ajustes de câmera e outros refinamentos descritos em [Resumo-Paintshop.md](Resumo-Paintshop.md).
- `Install-Paintshop.ps1` instala a edição local e cria backup dos arquivos substituídos; `Restore-Paintshop.ps1` restaura a versão original incluída.

## Instalação

1. Baixe o repositório em **Code → Download ZIP** e extraia todos os arquivos para uma pasta.
2. Feche o Assetto Corsa.
3. Execute `Install-Paintshop.ps1` no PowerShell. Como o destino padrão fica em `Program Files`, talvez seja necessário abrir o PowerShell como administrador.

O instalador confere os hashes dos arquivos, preserva recursos personalizados incompatíveis e grava um backup antes da instalação. Para restaurar, execute `Restore-Paintshop.ps1` a partir da mesma pasta extraída.

## Validação

A versão local.4 passou 103 asserções automatizadas e análise sintática Lua 5.1. A renderização, shaders e recuperação real ainda precisam de confirmação dentro do jogo.

## Licença

O repositório mantém a licença MIT escolhida ao ser criado. O app upstream de x4fab é disponibilizado sob Unlicense; veja [UPSTREAM-LICENSE-PAINTSHOP.txt](UPSTREAM-LICENSE-PAINTSHOP.txt) e o projeto original. Assetto Corsa e Custom Shaders Patch são marcas de seus respectivos titulares.
