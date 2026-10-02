local Project = {VERSION = 1, MAX_LAYERS = 32}

local function fail(message)
  error(message, 0)
end

local function validResolution(value)
  return value == 1024 or value == 2048 or value == 4096 or value == 6144 or value == 8192
end

local function cleanName(value, fallback)
  value = type(value) == 'string' and value:gsub('^%s+', ''):gsub('%s+$', '') or ''
  value = value:gsub('[%c]', ' '):sub(1, 80)
  return #value > 0 and value or fallback
end

local function validateManifest(manifest)
  if type(manifest) ~= 'table' or manifest.format ~= 'paintshop-project'
      or manifest.version ~= Project.VERSION then
    fail('Este arquivo não é um projeto Paintshop compatível.')
  end
  if not validResolution(manifest.resolution) then fail('Resolução inválida no projeto.') end
  if type(manifest.layers) ~= 'table' or #manifest.layers < 1 or #manifest.layers > Project.MAX_LAYERS then
    fail('Quantidade de camadas inválida no projeto.')
  end
  for index, layer in ipairs(manifest.layers) do
    if type(layer) ~= 'table' or layer.file ~= string.format('layers/%03d.dds', index) then
      fail('Estrutura de camadas inválida no projeto.')
    end
    layer.name = cleanName(layer.name, 'Camada '..index)
    layer.visible = layer.visible ~= false
    layer.opacity = math.max(0, math.min(1, tonumber(layer.opacity) or 1))
  end
  manifest.activeLayer = math.max(1, math.min(#manifest.layers, math.floor(tonumber(manifest.activeLayer) or #manifest.layers)))
  return manifest
end

function Project.buildEntries(layers, resolution, activeLayer, metadata)
  if not validResolution(resolution) then return nil, 'Resolução de projeto inválida.' end
  if type(layers) ~= 'table' or #layers < 1 or #layers > Project.MAX_LAYERS then
    return nil, 'O projeto deve ter de 1 a '..Project.MAX_LAYERS..' camadas.'
  end
  local manifest = {
    format = 'paintshop-project', version = Project.VERSION, resolution = resolution,
    activeLayer = math.max(1, math.min(#layers, math.floor(activeLayer or #layers))),
    createdWith = 'Paintshop 1.1.4-local.4', metadata = metadata or {}, layers = {}
  }
  local entries = {}
  local ok, err = pcall(function ()
    for index, layer in ipairs(layers) do
      if not layer.canvas or type(layer.canvas.encode) ~= 'function' then fail('Camada sem canvas: '..index) end
      local data = layer.canvas:encode()
      if not data or #data == 0 then fail('Falha ao codificar a camada '..index..'.') end
      local entry = string.format('layers/%03d.dds', index)
      entries[entry] = data
      manifest.layers[index] = {name = cleanName(layer.name, 'Camada '..index),
        visible = layer.visible ~= false, opacity = math.max(0, math.min(1, tonumber(layer.opacity) or 1)), file = entry}
    end
    entries['project.json'] = JSON.stringify(manifest)
    if not entries['project.json'] or #entries['project.json'] == 0 then fail('Falha ao criar o manifesto do projeto.') end
  end)
  if not ok then return nil, tostring(err) end
  return entries
end

function Project.inspect(filename)
  local raw = io.loadFromZip(filename, 'project.json')
  if not raw then return nil, 'Manifesto project.json ausente ou ilegível.' end
  local ok, manifest = pcall(JSON.parse, raw)
  if not ok then return nil, 'Manifesto do projeto inválido: '..tostring(manifest) end
  ok, manifest = pcall(validateManifest, manifest)
  if not ok then return nil, tostring(manifest) end
  return manifest
end

-- Canvas creation is injected so loading can be validated without a GPU.
function Project.load(filename, createCanvas)
  local manifest, err = Project.inspect(filename)
  if not manifest then return nil, err end
  local loaded, decoded = {}, nil
  local ok, failure = pcall(function ()
    for index, info in ipairs(manifest.layers) do
      local data = io.loadFromZip(filename, info.file)
      if not data or #data == 0 then fail('Dados ausentes para a camada '..index..'.') end
      decoded = ui.decodeImage(data)
      if not decoded then fail('Não foi possível decodificar a camada '..index..'.') end
      local canvas = createCanvas(manifest.resolution)
      if not canvas then fail('Não foi possível criar o canvas da camada '..index..'.') end
      loaded[index] = {name = info.name, visible = info.visible, opacity = info.opacity, canvas = canvas}
      canvas:update(function () ui.drawImage(decoded, 0, canvas:size()) end)
      ui.unloadImage(decoded)
      decoded = nil
    end
  end)
  if decoded then ui.unloadImage(decoded) end
  if not ok then
    for _, layer in ipairs(loaded) do if layer.canvas then layer.canvas:dispose() end end
    return nil, tostring(failure)
  end
  return {resolution = manifest.resolution, activeLayer = manifest.activeLayer,
    metadata = manifest.metadata or {}, layers = loaded}
end

return Project
