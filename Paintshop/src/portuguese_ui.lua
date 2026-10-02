-- A per-app UI facade: the shared CSP ui library is never modified.
return function (original)
  local labels = {
    ['Tools:'] = 'Ferramentas:', ['Color:'] = 'Cor:', ['Brush:'] = 'Pincel:',
    ['Background color:'] = 'Cor de fundo:', ['Eraser:'] = 'Borracha:', ['Stamp:'] = 'Adesivos:',
    ['Mirroring stamp:'] = 'Carimbo espelhado:', ['Blur tool:'] = 'Desfoque:',
    ['Sharpness boost:'] = 'Aumento de nitidez:', ['Active'] = 'Ativo', ['Text:'] = 'Texto:',
    ['Text'] = 'Texto', ['Bold'] = 'Negrito', ['Italic'] = 'Itálico',
    ['Align sticker:'] = 'Alinhar adesivo:', ['Align text:'] = 'Alinhar texto:',
    ['No'] = 'Não', ['Align to surface'] = 'Alinhar à superfície', ['Fully align'] = 'Alinhar completamente',
    ['Flip sticker'] = 'Inverter adesivo', ['With symmetry'] = 'Com simetria', ['Paint through'] = 'Atravessar modelo',
    ['Masking is active'] = 'Máscara ativa', ['Eyedropper:'] = 'Conta-gotas:', ['Sample size:'] = 'Área da amostra:',
    ['Point sample'] = 'Um pixel', ['3 by 3 average'] = 'Média 3×3', ['5 by 5 average'] = 'Média 5×5',
    ['7 by 7 average'] = 'Média 7×7', ['9 by 9 average'] = 'Média 9×9', ['Reset'] = 'Resetar',
    ['Open in Explorer'] = 'Abrir no Explorador', ['Refresh'] = 'Atualizar lista',
    ['Focus on player car'] = 'Focar no carro do jogador', ['Enable free camera'] = 'Ativar câmera livre',
    ['Focus on your car and use orbit (F5) camera…'] = 'Foque no seu carro e use a câmera orbital (F5).',
    ['Focus on your car and use orbit (F5) camera, or use free (F7) camera…'] = 'Use F5 para o carro ou F7 para pintar na pista.',
    ['• Hold Shift and click to start drawing.\n• Hold Ctrl+Shift and click to start drawing using custom AO map.'] =
      '• Shift + clique: iniciar edição.\n• Ctrl+Shift + clique: escolher um mapa AO próprio.',
    ['For best results, either use a custom AO map or make sure this texture is an AO map (grayscale colors with nothing but shadows):'] =
      'Use um mapa AO próprio ou uma textura branca/cinza que contenha apenas as sombras da carroceria:',
    ['Size: %.1f cm'] = 'Tamanho: %.1f cm', ['Minimum size: %.1f%%'] = 'Tamanho mínimo: %.1f%%',
    ['Stretch: %.0f%%'] = 'Proporção: %.0f%%', ['Step size: %.1f cm'] = 'Espaçamento: %.1f cm',
    ['Opacity: %.1f%%'] = 'Opacidade: %.1f%%', ['Angle: %.0f°'] = 'Ângulo: %.0f°',
    ['Smoothing: %.1f%%'] = 'Suavização: %.1f%%', ['Blur: %.0f%%'] = 'Desfoque: %.0f%%',
    ['Smudge: %.0f%%'] = 'Esfumar: %.0f%%', ['Intensity: %.0f%%'] = 'Intensidade: %.0f%%',
    ['Max steps: %.0f'] = 'Passos por quadro: %.0f',
    ['Brush (B)'] = 'Pincel (B)', ['Eraser (E)'] = 'Borracha (E)', ['Stamp (S)'] = 'Adesivos (S)',
    ['Mirroring stamp (K)'] = 'Carimbo espelhado (K)', ['Blur/Smudge (Alt+B)'] = 'Desfoque/Esfumar (Alt+B)',
    ['Text (T)'] = 'Texto (T)', ['Masking (M)'] = 'Máscara (M)', ['Eyedropper (I)'] = 'Conta-gotas (I)',
    ['Use digit buttons to quickly change opacity'] = 'Use as teclas numéricas para ajustar a opacidade.',
    ['Use mouse wheel and hold Ctrl to quickly change size'] = 'Ctrl + roda: ajustar a proporção do adesivo.',
    ['Use mouse wheel and hold Alt to quickly change angle'] = 'Alt + roda: ajustar o ângulo.',
    ['Size of a brush with minimum pen pressure'] = 'Tamanho do pincel com a menor pressão da caneta.',
    ['Randomize angle when drawing'] = 'Variar o ângulo a cada aplicação do pincel.',
    ['Flip sticker (Z)'] = 'Inverter adesivo (Z)',
    ['Use arrow keys to quickly switch between items'] = 'Use as setas para trocar de adesivo.',
    ['Smoothing makes brush move smoother and slower'] = 'Suavização reduz tremores e deixa o movimento mais lento.',
    ['Paint with symmetry (Y)\nMirrors things from one side of a car to another'] = 'Simetria (Y)\nReplica a pintura no outro lado do eixo configurado.',
    ['Paint through model (R)\nIf enabled, drawings would go through model and leave traces on the opposite side as well'] =
      'Atravessar modelo (R)\nProjeta também nas superfícies atrás da primeira peça.',
    ['Toggle masking (Ctrl+M)'] = 'Ativar/desativar máscara (Ctrl+M)',
    ['Project other side (Ctrl+E)\nProject other side on current side to make making things symmetrical easier'] =
      'Mostrar o outro lado (Ctrl+E)\nSobrepõe uma referência para facilitar o alinhamento.',
    ['Sharpness boost is some sort of an inverse to blur. Might help to increase local sharpness a bit or, with less well tuned settings, achieve some other strange effects.'] =
      'Aumenta a nitidez local. Intensidades altas podem gerar halos e efeitos inesperados.',
    ['Increased number of steps helps to turn a brush line from a bunch of spots to the actual line at the cost of performance. Reduce if experiencing FPS drops when drawing.'] =
      'Mais passos tornam o traço contínuo, mas aumentam o custo de renderização. Reduza se o FPS cair ao pintar.',
    ['Masking tool is a plane separating model in two halves. When you draw a thing, it would only get drawn on the side of a plane with camera. Might help in masking things quickly.\n\nClick model and drag mouse to quickly create a new plane.\n\nPro tip: when using brush, hold M for more than 0.2 seconds: tool will switch to masking temporary, so you can quickly put a mask and go back to brush by releasing M.'] =
      'A máscara divide o modelo por um plano: a pintura fica do lado da câmera.\n\nClique e arraste na carroceria para posicionar o plano. Segure M por mais de 0,2 s para usar a máscara temporariamente; solte para voltar ao pincel.'
  }
  local prefixes = {['Brush: '] = 'Pincel: ', ['Font: '] = 'Fonte: ', ['Texture: '] = 'Textura: ',
    ['Material: '] = 'Material: ', ['Mesh: '] = 'Malha: ', ['New decal added: '] = 'Adesivo adicionado: ',
    ['Couldn’t create a new category: '] = 'Falha ao criar categoria: '}
  local function translate(value)
    if type(value) ~= 'string' then return value end
    if labels[value] then return labels[value] end
    local text, id = value:match('^(.-)(##.*)$')
    if text and labels[text] then return labels[text]..id end
    for prefix, replacement in pairs(prefixes) do
      if value:sub(1, #prefix) == prefix then return replacement..value:sub(#prefix + 1) end
    end
    return value
  end
  local facade = {}
  for _, name in ipairs({'text', 'textWrapped', 'header', 'button', 'checkbox', 'selectable', 'inputText', 'setTooltip'}) do
    local originalFunction = original[name]
    facade[name] = function (label, ...) return originalFunction(translate(label), ...) end
  end
  facade.slider = function (label, value, minimum, maximum, format, ...)
    return original.slider(translate(label), value, minimum, maximum, translate(format), ...)
  end
  facade.combo = function (label, preview, flags, content)
    if type(content) == 'table' then
      local translated = {}
      for i, value in ipairs(content) do translated[i] = translate(value) end
      content = translated
    end
    if content == nil then return original.combo(label, translate(preview), flags) end
    return original.combo(label, translate(preview), flags, content)
  end
  facade.toast = function (icon, text, ...) return original.toast(icon, translate(text), ...) end
  return setmetatable(facade, {__index = original})
end
