<div align="center">
<img src="assets/paint-hero.svg" alt="PaintShop Fix — pinte seu carro dentro do Assetto Corsa" width="100%">
<br>
<a href="https://github.com/Silxyst/PaintShop-Fix"><img src="https://readme-typing-svg.demolab.com?font=Fira+Code&weight=600&size=22&duration=2600&pause=900&color=ff4d8d&center=true&vCenter=true&width=720&lines=Pinte+seu+carro+DENTRO+do+Assetto+Corsa;32+camadas+%E2%80%A2+.pspaint+%E2%80%A2+autosave;Sem+Photoshop.+Sem+Alt+Tab." alt="Pinte seu carro dentro do Assetto Corsa"></a>

<p>
<img src="Paintshop/icon.png" width="120" alt="PaintShop Fix Logo">
</p>

<h1>🎨 PaintShop Fix</h1>

<p><b>Pinte seu carro DENTRO do Assetto Corsa. Sem Photoshop. Sem Alt+Tab. Sem dor de cabeça.</b><br>
A edição definitiva e corrigida do app Paintshop para <b>Custom Shaders Patch</b> — agora em português e com camadas!</p>

<p>
<a href="https://github.com/Silxyst/PaintShop-Fix/releases"><img src="https://img.shields.io/badge/BAIXAR-ULTIMA_VERSAO-2ea043?style=for-the-badge&logo=github&logoColor=white" alt="Download"></a>
</p>

<p>
<img src="https://img.shields.io/badge/version-1.1.4--local.4-blue?style=flat-square" alt="Version">
<img src="https://img.shields.io/badge/game-Assetto_Corsa-red?style=flat-square&logo=steam" alt="Assetto Corsa">
<img src="https://img.shields.io/badge/requires-Custom_Shaders_Patch-9e6a03?style=flat-square" alt="CSP">
<img src="https://img.shields.io/badge/Lua-5.1-2C2D72?style=flat-square&logo=lua" alt="Lua">
<img src="https://img.shields.io/badge/lang-PT--BR-green?style=flat-square" alt="PT-BR">
<img src="https://img.shields.io/github/license/Silxyst/PaintShop-Fix?style=flat-square" alt="License">
<img src="https://img.shields.io/github/stars/Silxyst/PaintShop-Fix?style=flat-square&logo=github" alt="Stars">
</p>

<p><a href="#-instalação-em-1-minuto">📥 Instalação</a> • <a href="#-o-que-este-fix-resolve">✨ Novidades</a> • <a href="#-demonstração">🎬 Demo</a> • <a href="#-como-usar">🎮 Como Usar</a> • <a href="#-screenshots">📸 Screenshots</a> • <a href="#-faq">❓ FAQ</a></p>
</div>

> ⚠️ **Baseado no projeto original de x4fab:** [ac-custom-shaders-patch/app-paintshop](https://github.com/ac-custom-shaders-patch/app-paintshop). Este é um **fix comunitário não-oficial**, feito para quem usa o app todo dia e sofria com bugs e falta de recursos.

## 🔥 Por que usar este Fix?

| ❌ Original 1.1.4 | ✅ PaintShop Fix |
|---|---|
| Sem camadas (pintou, era!) | **Até 32 camadas** editáveis com opacidade e visibilidade |
| Perdeu tudo se fechou o jogo | **Rascunho automático + 10 autosaves** rotativos |
| Sem projeto editável | **Formato `.pspaint`** — salve e continue depois |
| Save perigoso (corrompia skin) | **Salvamento seguro** com temporário + backup |
| Interface em inglês | **100% em Português** 🇧🇷 |
| Sem Ctrl+S direito | **Ctrl+S inteligente** + exportação com AO |
| Câmera travada | **Zoom, pan, FOV ajustáveis** |

## ✨ O que este Fix resolve

### 🎭 1. Camadas de verdade (a mais pedida!)

```
+ Nova camada → Pinte → Ajuste opacidade → Reordene → Exporte
```

- Até **32 camadas** rasterizadas com nome, olho 👁️, opacidade e ordem
- **Importar imagem = nova camada** | **Abrir imagem = novo documento**
- Preview ao vivo = composição de todas as camadas visíveis
- Medidor de VRAM para não estourar em texturas 4K

### 💾 2. Nunca mais perca sua pintura

- Fechou a janela sem querer? **Rascunho `.pspaint` salvo sozinho**
- Reabriu o jogo na mesma textura? Ele pergunta: **“Continuar rascunho?”**
- **10 autosaves DDS** separados por carro / skin / textura + metadados JSON
- `.pspaint` = ZIP versionado com manifesto + DDS por camada — o seu **“PSD do Assetto”**

### 🛡️ 3. Salvamento à prova de pânico

- Salva em **arquivo temporário → valida → backup → substitui**
- Falhou? **Não marca como salvo**, sua arte continua intacta
- **Exportar como nova skin** copia a skin, exporta e atualiza o `ui_skin.json` sozinho

### 🇧🇷 4. Feito para BR + Qualidade de vida

- Interface e guia inicial **em português**
- **Ctrl+Shift+roda = zoom**, botão direito = pan, FOV e distância ajustáveis
- Busca de adesivos 🔍 + favoritos ⭐ + 16 recentes 🕒
- Simetria X/Y/Z corrigida, modo pista F7 corrigido, atalhos não brigam com digitação
- Preview limitada a FPS configurável (mais performance)

<a id="demo"></a>
## 🎬 Demonstração

<img src="assets/paint-cycle.svg" alt="Fluxo PaintShop Fix: nova camada, pinte, Ctrl+S, exportar" width="100%">

## 📸 Screenshots

| Pintando no jogo | Sistema de camadas | Exportando skin |
|:---:|:---:|:---:|
| <img src="docs/screenshots/pintando.png" width="100%"> | <img src="docs/screenshots/camadas.png" width="100%"> | <img src="docs/screenshots/export.png" width="100%"> |
| Shift+Click na lataria e saia pintando | Até 32 camadas com opacidade | Um clique e vira skin nova |

> 📌 Troque esses prints pelos seus: é só subir um PNG 1920x1080 com o mesmo nome em `docs/screenshots/` que a página atualiza sozinha!

<img src="assets/paint-divider.svg" alt="" width="100%">

## 📥 Instalação em 1 minuto

### Requisitos

- 🏎️ **Assetto Corsa** (Steam)
- 🧩 **Custom Shaders Patch** 0.2.x instalado e ativo
- 🪟 Windows + PowerShell

### Passo a passo

**1️⃣ Baixe**

```bash
Code → Download ZIP  (ou na página de Releases)
```

Extraia tudo para uma pasta qualquer (ex: `Downloads\PaintShop-Fix`).

**2️⃣ Feche o jogo**

> O Assetto Corsa precisa estar **fechado**.

**3️⃣ Instale (como Admin)**

Clique com botão direito no PowerShell → **Executar como administrador**, depois:

```powershell
.\Install-Paintshop.ps1
```

Pronto! O instalador confere hashes, faz **backup automático** e preserva seus pincéis/adesivos.

**↩️ Quer voltar ao original?**

```powershell
.\Restore-Paintshop.ps1
```

## 🎮 Como usar

```mermaid
flowchart LR
    A[F5 + Shift+Click] --> B[+ NOVA CAMADA]
    B --> C[PINTE]
    C --> D[CTRL+S]
    D --> E[EXPORTAR]
    E --> F[SKIN NOVA]
```

1. No jogo, abra o app **Paintshop**, aperte **F5** e dê **Shift + Clique** na carroceria
   - `Ctrl+Shift+Clique` = escolher mapa AO
2. Clique em **+ Nova** para criar camada. Olho 👁️ = visibilidade, arraste = ordem
3. Feche a janela? Relaxa, o **rascunho salva sozinho**. Voltou na mesma textura? Clique em **Continuar rascunho**
4. **Ctrl+S** = salva imagem (1 camada) ou projeto `.pspaint` (2+ camadas)
   - Botão direito no **Salvar** → escolher entre `Projeto .pspaint` e `Imagem achatada`
   - Botão direito no **Abrir** → abrir `.pspaint`, importar como camada, limpar camada, recuperar autosave
5. **Exportar** = gera textura final com AO. Botão direito no **Exportar** = cria **skin nova** automaticamente

> 💡 **Regra de ouro:** `.pspaint` é o mestre editável. PNG/DDS é a foto final. Para a pintura aparecer fora do app, sempre **Exporte**.

### ⌨️ Atalhos

| Atalho | Ação |
|---|---|
| `Shift + Click` | Começar a pintar na peça |
| `Ctrl+S` | Salvar rápido (inteligente) |
| `Ctrl+Shift+Roda` | Zoom |
| `Botão Direito + Arrastar` | Pan da câmera |
| `F7` | Modo pista (corrigido) |
| `Ctrl+Z` / `Ctrl+Y` | Desfazer / Refazer |

## 📁 O que vem no pacote

```
📦 PaintShop-Fix/
├── 🎨 Paintshop/              ← app completo (Lua + pincéis + adesivos + fontes)
│   ├── Paintshop.lua
│   ├── src/                   ← camadas, histórico, projeto, UI PT-BR
│   ├── brushes/ decals/ fonts/
│   └── icon.png + manifest.ini
├── ⚙️ Install-Paintshop.ps1   ← instala + backup automático
├── ↩️ Restore-Paintshop.ps1   ← volta ao original 1.1.4
├── 📦 Paintshop-original-1.1.4.zip
├── 📖 Resumo-Paintshop.md     ← changelog técnico completo
└── 📜 UPSTREAM-LICENSE-PAINTSHOP.txt
```

## ✅ Testado e validado

- ✔️ **103 asserções automatizadas** passando
- ✔️ Análise sintática **Lua 5.1** limpa
- ✔️ Hashes SHA-256 dos 6 arquivos conferidos
- ⚠️ Renderização in-game, pressão de caneta e VRAM em 4K ainda precisam do seu teste — **abre uma Issue contando seu carro/pista!**

## 🗺️ Roadmap

- [x] Camadas + `.pspaint`
- [x] Rascunho + autosaves
- [x] Interface PT-BR
- [ ] Autosave de `.pspaint` em 2º plano
- [ ] Blend modes (Multiply, Screen, Add)
- [ ] Máscaras por camada
- [ ] Splines/vetores para faixas
- [ ] Controle de compressão DDS/PBR

> 💬 Tem ideia? [Abre uma Issue](https://github.com/Silxyst/PaintShop-Fix/issues/new) ou manda PR!

## 🤝 Contribua

1. Dê ⭐ no repo (ajuda MUITO!)
2. Fork → crie sua branch → PR
3. Reporte bugs com: carro, skin, resolução da textura e log

<img src="assets/paint-divider.svg" alt="" width="100%">

## ❓ FAQ

<details>
<summary><b>O App Shelf vai apagar meu Fix?</b></summary>
<br>
Sim, pode substituir ao atualizar. Guarde este pacote e reinstale depois. Estamos vendo forma de proteger.
</details>

<details>
<summary><b>Funciona online / em servidor?</b></summary>
<br>
A pintura exportada é uma skin normal — funciona em qualquer lugar que skins funcionem.
</details>

<details>
<summary><b>Ficou pesado em 4K?</b></summary>
<br>
Olhe o medidor de VRAM no painel. Muitas camadas em 4096×4096 comem VRAM — mescle ou exporte parcial.
</details>

<details>
<summary><b>É oficial da Kunos / x4fab?</b></summary>
<br>
Não. Fix comunitário baseado no Unlicense do x4fab. Assetto Corsa e CSP são dos seus donos.
</details>

## 📜 Licença e créditos

- 🧑‍💻 Original: **x4fab** ([app-paintshop](https://github.com/ac-custom-shaders-patch/app-paintshop)) — Unlicense
- 🔧 Este Fix: licença MIT (ver `LICENSE`) + `UPSTREAM-LICENSE-PAINTSHOP.txt`
- 🙏 Valeu a quem testar e mandar print!

<div align="center">
<img src="assets/paint-divider.svg" alt="" width="100%">
<p><b>Gostou? Deixa uma ⭐ e compartilha com seu grupo de drift / liga!</b><br>
<a href="https://github.com/Silxyst/PaintShop-Fix/stargazers">⭐ Stargazers</a> •
<a href="https://github.com/Silxyst/PaintShop-Fix/issues">🐛 Issues</a> •
<a href="https://github.com/Silxyst/PaintShop-Fix/releases">📦 Releases</a></p>
<sub>Feito com ❤️ para a comunidade BR de Assetto Corsa · <a href="#demo">voltar ao topo ↑</a></sub>
</div>