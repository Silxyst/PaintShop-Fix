# Paintshop — edição local 1.1.4-local.4

Implementação baseada na instalação de x4fab 1.1.4, analisada em 30/09/2026. Esta é uma edição local personalizada, não uma atualização oficial do autor.

## O que é o app

O Paintshop é um app Lua do Custom Shaders Patch para pintar diretamente nas malhas do carro dentro do Assetto Corsa. O fluxo original separa a arte sem sombras da exportação final: a textura escolhida pode servir como mapa AO, aplicado somente na exportação. O projeto oficial oferece pincel, borracha, adesivos, texto, desfoque/esfumaçado, simetria, pressão de caneta e atalhos inspirados no Photoshop.

Fontes consultadas:

- Projeto oficial: https://github.com/ac-custom-shaders-patch/app-paintshop
- SDK Lua oficial do CSP: https://github.com/ac-custom-shaders-patch/acc-lua-sdk
- Documentação instalada com o CSP: `extension/internal/lua-sdk`

O próprio repositório oficial lista camadas, efeitos de camada, máscaras e splines como evoluções desejadas. Esta edição implementa a primeira delas e um formato de projeto para preservá-la.

## Melhorias implementadas

### Camadas e projeto editável

- Até 32 camadas rasterizadas, com nome, seleção, visibilidade e opacidade.
- Criação, duplicação, exclusão e mudança de ordem. A pintura é aplicada somente à camada ativa e a preview usa a composição de todas as camadas visíveis.
- Importar uma imagem agora a adiciona como nova camada; Abrir imagem substitui o documento por uma camada.
- Ocultar a janela grava um rascunho `.pspaint` automaticamente, preservando as camadas; ao selecionar novamente a mesma textura, o Paintshop oferece continuar de onde parou.
- O botão de finalizar pede confirmação para guardar o rascunho antes de restaurar a textura original do carro.
- Ao fechar a janela durante uma edição, a prévia fica ativa em memória enquanto o app está oculto; o rascunho em camadas também é salvo para recuperação após reiniciar o jogo.
- Novo formato `.pspaint`: ZIP versionado com manifesto JSON, metadados de carro/skin/textura e cada camada codificada em DDS. Visibilidade, opacidade, ordem e camada ativa são preservadas.
- Salvamento do projeto em arquivo temporário, montagem assíncrona do ZIP, backup do destino anterior e substituição somente depois da validação.
- Ao salvar um projeto, o rascunho automático correspondente é arquivado com nome datado; isso evita que uma versão antiga seja oferecida como recuperação depois de o projeto já ter sido salvo.
- Ctrl+S salva `.pspaint` quando há mais de uma camada ou um projeto já está aberto. O menu do botão Salvar oferece separadamente projeto editável e imagem achatada.
- A exportação para o jogo continua achatando a composição e aplicando AO, antialiasing e mipmaps.
- Medidor de memória das camadas e da composição.

### Confiabilidade e fluxo de trabalho

- Histórico por identificadores de revisão: desfazer/refazer e ramificar depois de salvar mantêm corretamente o estado de alterações não salvas.
- Limites configuráveis de memória e quantidade de estados do histórico. Padrão: 512 MB e 30 estados.
- Liberação de canvases, camadas, readbacks, câmera, snapshots e capturas das ferramentas ao finalizar.
- Callbacks de dados e diálogos associados à sessão que os iniciou; respostas antigas não substituem uma nova edição.
- Save de imagem em PNG por padrão, sempre por arquivo temporário, com verificação e backup antes de substituir o destino.
- Falhas de Save não marcam o documento como salvo.
- Dez autosaves DDS rotativos separados por carro, skin e textura, com metadados JSON de origem, resolução, quantidade de camadas e projeto associado.
- Recuperação de autosave com validação de origem.
- Exportar como nova skin copia a skin atual, exporta a textura, salva a arte achatada e atualiza `ui_skin.json`. Pastas existentes não são substituídas.

### Interface, câmera e ferramentas

- Zoom com Ctrl+Shift+roda, distância e FOV ajustáveis, pan com botão direito e reset da câmera.
- Interface e instruções principais em português sem alterar a biblioteca global de UI do CSP.
- Guia inicial, diagnósticos de foco/textura e resolução exibida corretamente, incluindo 4096×4096.
- Preview limitada a FPS configurável quando não há traço em andamento.
- Busca de adesivos entre categorias, favoritos persistentes e 16 itens recentes.
- Tratamento de categorias vazias, diretórios inválidos e pasta de pincéis vazia.
- Atalhos suspensos durante digitação e diálogos.
- Simetria em X/Y/Z com deslocamento do plano e correção da largura espelhada em traços interpolados.
- Modo de pista em F7 corrigido.
- Histórico, arquivos, projetos e tradução separados em módulos.

## Como usar a nova versão

1. No Assetto Corsa, abra o Paintshop, use F5 e faça Shift + clique na carroceria. Ctrl+Shift + clique permite escolher um mapa AO.
2. Use **+ Nova** para criar uma camada. Selecione uma linha para torná-la ativa; o olho controla visibilidade. Renomeie, ajuste opacidade, duplique, exclua ou mova para cima/baixo.
3. Fechar a janela do Paintshop oculta o app e grava o rascunho; abrir o app novamente na mesma sessão mantém a prévia. Ao selecionar a mesma textura depois de reiniciar o jogo, aceite **Continuar rascunho?** para recuperar as camadas.
4. Ctrl+S salva a imagem quando existe somente uma camada nova. Com duas ou mais camadas, abre o salvamento do projeto `.pspaint`.
5. Botão direito em Salvar permite sempre escolher entre **Salvar projeto como…** e **Salvar imagem achatada como…**.
6. Botão direito em Abrir oferece **Abrir projeto .pspaint…**, importar imagem como camada, limpar camada ativa e recuperar autosave.
7. Use Exportar para gerar a textura final com AO. Botão direito em Exportar cria uma nova skin.

Observações:

- O `.pspaint` é o arquivo mestre editável. PNG/DDS exportado é uma imagem achatada.
- O rascunho automático em `recovery.pspaint` guarda as camadas. Autosaves rotativos DDS continuam disponíveis como recuperação achatada rápida.
- Para a pintura continuar visível no carro fora do Paintshop ou em outras sessões, use Exportar. A prévia de edição não substitui a textura da skin até exportá-la.
- Uma alteração estrutural de camada limpa o histórico de pixels, porque os snapshots atuais armazenam o canvas da camada ativa. O app avisa antes de excluir.
- Resoluções altas e muitas camadas consomem bastante VRAM. O painel mostra uma estimativa dos canvases ativos.

## Validação

- A versão local.4 passou 103 asserções simuladas e análise de sintaxe Lua 5.1; a revisão ampliou os testes para confirmar o arquivamento de rascunhos antigos após salvar o projeto. Os seis arquivos de código instalados foram conferidos por SHA-256 e correspondem ao pacote local.4.
- O jogo estava fechado durante a implementação. A restauração real do rascunho, renderização, shaders, pressão de caneta, uso de VRAM e compatibilidade por modelo ainda precisam de validação dentro do Assetto Corsa.

## Sugestões para a próxima etapa

1. Autosave nativo de `.pspaint`, em segundo plano, com retenção por projeto.
2. Modos de mesclagem por camada (Multiply, Screen, Add) e efeitos não destrutivos.
3. Máscaras rasterizadas por camada e seleções reutilizáveis.
4. Splines/vetores para faixas e formas editáveis.
5. Controle de compressão DDS/PBR e suporte a outros slots além de `txDiffuse`.
6. Remapeamento de atalhos e geração automática de preview da skin.

## Backup e restauração

`Paintshop-original-1.1.4.zip` contém a instalação original. `Restore-Paintshop.ps1` restaura `Paintshop.lua` e `manifest.ini`, preservando adesivos e dados do usuário. `Install-Paintshop.ps1` instala somente os arquivos de código alterados; os recursos do app são preservados.

Uma atualização do Paintshop pelo App Shelf pode substituir esta edição local. Preserve o pacote modificado e compare a nova versão oficial antes de reinstalar a personalização.
