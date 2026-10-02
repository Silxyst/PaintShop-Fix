--[[
  Whole code is a bit of a mess and definitely needs reworking: splitting in separate modules,
  reorganazing, etc. But at this stage it’s mostly just a small API test.
]]

local History = require('src/history')
local Files = require('src/files')
local Project = require('src/project')
local ui = require('src/portuguese_ui')(ui)
local runtime = {session = 0, dataRequest = 0, saving = false, cameraNavigating = false}
local sim = ac.getSim()
local uiState = ac.getUI()
local userCar = ac.getCar(0) or error()
local userCarDir = ac.getFolder(ac.FolderID.ContentCars)..'/'..ac.getCarID(userCar.index)
local userCarSkinDir = userCarDir..'/skins/'..ac.getCarSkinID(0)
local carNode = nil ---@type ac.SceneReference
local carMeshes = nil ---@type ac.SceneReference
local trackNode = nil ---@type ac.SceneReference
local trackMeshes = nil ---@type ac.SceneReference
local config = ac.storage{
  resolution = 2048,
  maxSteps = 100,
  trackMode = false,
  historyMB = 512,
  historySteps = 30,
  autosaveSeconds = 30,
  autosaveSlot = 1,
  cameraDistance = 8,
  cameraFOV = 24,
  showHelp = true,
  stickerCategory = '',
  favoriteDecals = '{}',
  recentDecals = '{}',
  mirrorOffset = 0,
  mirrorAxis = 1,
  previewFPS = 30
}
config.resolution = table.findFirst({1024, 2048, 4096, 6144, 8192}, function (v) return v == config.resolution end) or 2048
config.historyMB = math.clamp(config.historyMB, 64, 2048)
config.historySteps = math.clamp(math.floor(config.historySteps), 1, 100)
config.autosaveSeconds = math.clamp(config.autosaveSeconds, 10, 300)
config.cameraDistance = math.clamp(config.cameraDistance, 1, 20)
config.cameraFOV = math.clamp(config.cameraFOV, 10, 70)
config.mirrorAxis = math.clamp(math.floor(config.mirrorAxis), 1, 3)
config.mirrorOffset = math.clamp(config.mirrorOffset, -2, 2)
config.previewFPS = math.clamp(math.floor(config.previewFPS), 15, 60)
local history = History.new(config.historyMB * 1024 * 1024, config.historySteps)

local selectedMeshes ---@type ac.SceneReference
local trackMode = false
local carTexture
local aoTexture
local editingCanvas, aoCanvas, maskingCanvas ---@type ui.ExtraCanvas
local accessibleData ---@type ui.ExtraCanvasData
local otherSideShot ---@type ac.GeometryShot
local otherSidePhase, otherSideSide = -1, 0
local bakKsAmbient
local maskingDirty = true

function script.windowMainSettings(dt)
  if selectedMeshes then
    ui.pushFont(ui.Font.Small)
    ui.textWrapped('Finalize a edição atual antes de alterar estas configurações.')
    ui.popFont()
    return
  end
  ui.combo('##resolution', string.format('Resolução: %d×%d', config.resolution, config.resolution), function ()
    for _, resolution in ipairs({1024, 2048, 4096, 6144, 8192}) do
      if ui.selectable(string.format('%d×%d', resolution, resolution), config.resolution == resolution) then
        config.resolution = resolution
      end
    end
  end)
  ui.textWrapped(string.format('Uma cópia RGBA: ~%.0f MB. AO, máscara e histórico consomem memória adicional.', config.resolution ^ 2 * 4 / (1024 * 1024)))
  config.historyMB = math.floor(ui.slider('##historyMB', config.historyMB, 64, 2048, 'Histórico: %.0f MB'))
  config.historySteps = math.floor(ui.slider('##historySteps', config.historySteps, 1, 100, 'Estados: %.0f'))
  history.maxBytes, history.maxEntries = config.historyMB * 1024 * 1024, config.historySteps
  history:trim()
  config.autosaveSeconds = math.floor(ui.slider('##autosaveSeconds', config.autosaveSeconds, 10, 300, 'Autosave: %.0f s'))
  config.previewFPS = math.floor(ui.slider('##previewFPS', config.previewFPS, 15, 60, 'Preview: %.0f FPS'))
  if ui.checkbox('Mostrar guia rápido', config.showHelp) then config.showHelp = not config.showHelp end
  config.maxSteps = ui.slider('##maxSteps', config.maxSteps, 1, 100, 'Max steps: %.0f')
  if ui.itemHovered() then
    ui.setTooltip('Increased number of steps helps to turn a brush line from a bunch of spots to the actual line at the cost of performance. Reduce if experiencing FPS drops when drawing.')
  end
  if ui.checkbox('Pintar na pista (experimental)', config.trackMode) then
    config.trackMode = not config.trackMode
  end
end

-- Calling it once at the start to initialize RealTimeStylus API and get Assetto Corsa to work
-- nicely with pens and styluses (check `ac.getPenPressure()` description for more information).
ac.getPenPressure()

local shortcuts = {
  undo = ui.shortcut({ key = ui.KeyIndex.Z, ctrl = true }, ui.KeyIndex.XButton1),
  redo = ui.shortcut({ key = ui.KeyIndex.Y, ctrl = true }, ui.KeyIndex.XButton2),
  save = ui.shortcut{ key = ui.KeyIndex.S, ctrl = true },
  export = ui.shortcut{ key = ui.KeyIndex.S, ctrl = true, shift = true, alt = true },
  load = ui.shortcut{ key = ui.KeyIndex.O, ctrl = true },
  swapColors = ui.shortcut(ui.KeyIndex.X),
  flipSticker = ui.shortcut(ui.KeyIndex.Z),
  toggleSymmetry = ui.shortcut(ui.KeyIndex.Y),
  toggleDrawThrough = ui.shortcut(ui.KeyIndex.R),
  toolBrush = ui.shortcut(ui.KeyIndex.B),
  toolEraser = ui.shortcut(ui.KeyIndex.E),
  toolStamp = ui.shortcut(ui.KeyIndex.S),
  toolMirroringStamp = ui.shortcut(ui.KeyIndex.K),
  toolBlurTool = ui.shortcut({ key = ui.KeyIndex.B, alt = true }),
  toolEyeDropper = ui.shortcut(ui.KeyIndex.I),
  toolMasking = ui.shortcut(ui.KeyIndex.M),
  toolText = ui.shortcut(ui.KeyIndex.T),
  toggleMasking = ui.shortcut({ key = ui.KeyIndex.M, ctrl = true }),
  toggleOrbitCamera = ui.shortcut({ key = ui.KeyIndex.Space, ctrl = true }),
  toggleProjectOtherSide = ui.shortcut({ key = ui.KeyIndex.E, ctrl = true }),
  arrowLeft = ui.shortcut(ui.KeyIndex.Left),
  arrowRight = ui.shortcut(ui.KeyIndex.Right),
  arrowUp = ui.shortcut(ui.KeyIndex.Up),
  arrowDown = ui.shortcut(ui.KeyIndex.Down),
  opacity = table.range(9, 0, function (index)
    return ui.shortcut(ui.KeyIndex.D0 + index), index
  end)
}

local function guardedShortcut(shortcut)
  return setmetatable({down = function ()
    return not uiState.wantCaptureKeyboard and not runtime.dialog and shortcut:down()
  end}, {__call = function (_, ...)
    return not uiState.wantCaptureKeyboard and not runtime.dialog and shortcut(...)
  end})
end
for name, shortcut in pairs(shortcuts) do
  if name == 'opacity' then
    for index, item in pairs(shortcut) do shortcut[index] = guardedShortcut(item) end
  else shortcuts[name] = guardedShortcut(shortcut) end
end

local icons = ui.atlasIcons('res/icons.png', 4, 4, {
  Brush = {1, 1},
  Eraser = {1, 2},
  Undo = {1, 3},
  Redo = {1, 4},
  EyeDropper = {2, 1},
  Camera = {2, 2},
  Save = {2, 3},
  Open = {2, 4},
  Stamp = {3, 1},
  Masking = {3, 2},
  Stencil = {3, 3},
  Export = {3, 4},
  Text = {4, 1},
  MirroringStamp = {4, 2},
  BlurTool = {4, 3},
  MirroringHelper = {4, 4},
})

local taaFix = { On = 1, Off = 0 }

ac.onRelease(function ()
  if saveRecoveryDraft and editingCanvas and history:isDirty() then saveRecoveryDraft() end
  if carTexture and selectedMeshes then
    selectedMeshes:setMaterialTexture('txDiffuse', carTexture):setMotionStencil(taaFix.Off)
  end
  if runtime.cleanup then runtime.cleanup() end
end)

local carPreviewMeshes ---@type ac.SceneReference
local hoveredMaterial
local camera ---@type ac.GrabbedCamera?
local appVisible = false
local cameraPan = vec2()

local function disposeResource(resource)
  if resource then resource:dispose() end
end

local function clearPreview()
  disposeResource(carPreviewMeshes)
  carPreviewMeshes = nil
  hoveredMaterial = nil
end

---@param target ac.SceneReference
---@param hit ac.SceneReference
local function filterMeshSelection(target, hit)
  if target == trackMeshes then
    -- local candidates = target:filterMeshes('{ material:'..hit:materialName()..' }')
    -- local ret = ac.emptySceneReference()
    -- local bsCenter = vec3()
    -- local bsTarget = hit:boundingSphere()
    -- if not bsTarget then
    --   return hit:clone()
    -- end
    -- for i = 1, #candidates do
    --   candidates:boundingSphere(i, bsCenter)
    --   if bsTarget:closerToThan(bsCenter, 40) then
    --     ret:append(candidates:at(i))
    --   end
    -- end
    return hit:clone()
  end
  return target:filterMeshes('{ material:'..hit:materialName()..' }')
end

local function MeshSelection()
  if config.showHelp then
    ui.textWrapped('1. Use uma skin branca ou forneça um mapa AO.\n2. F5, depois Shift + clique na carroceria.\n3. Organize a arte em camadas e salve o projeto .pspaint.\n4. Exporte a textura final com AO para usar no jogo.')
    if ui.button('Ocultar guia', vec2(210, 0)) then config.showHelp = false end
  end
  ui.offsetCursorY(20)
  if (sim.cameraMode ~= ac.CameraMode.OnBoardFree and sim.closelyFocusedCar ~= 0)
    and (not config.trackMode or sim.cameraMode ~= ac.CameraMode.Free) then
    clearPreview()
    ui.pushFont(ui.Font.Small)
    if config.trackMode then
      ui.textWrapped('Focus on your car and use orbit (F5) camera, or use free (F7) camera…')
    else
      ui.textWrapped('Focus on your car and use orbit (F5) camera…')
    end
    ui.popFont()
    ui.offsetCursorY(8)
    if ui.button('Focus on player car', vec2(ui.availableSpaceX())) then
      ac.setCurrentCamera(ac.CameraMode.OnBoardFree)
      ac.focusCar(0)
    end
    if config.trackMode then
      if ui.button('Enable free camera', vec2(ui.availableSpaceX())) then
        ac.setCurrentCamera(ac.CameraMode.Free)
      end
    end
    return
  end

  local carMode = not (config.trackMode and sim.cameraMode == ac.CameraMode.Free)
  local targetMeshes ---@type ac.SceneReference
  if carMode then
    if not carMeshes then
      carNode = ac.findNodes('carRoot:0')
      carMeshes = carNode:findMeshes('{ ! material:DAMAGE_GLASS & lod:A }')
    end
    targetMeshes = carMeshes
  else
    if not trackMeshes then
      trackNode = ac.findNodes('trackRoot:yes')
      trackMeshes = trackNode:findMeshes('{ lodIn:0 }')
    end
    targetMeshes = trackMeshes
  end

  ui.pushFont(ui.Font.Small)
  local ray = render.createMouseRay()
  local ref = ac.emptySceneReference()
  if sim.isWindowForeground and targetMeshes:raycast(ray, ref) ~= -1 and not uiState.wantCaptureMouse then
    ui.text('Texture: '..(tostring(ref:getTextureSlotFilename('txDiffuse')):regmatch('[^/\\:]+$') or '?'))
    ui.text('Material: '..tostring(ref:materialName()))
    ui.text('Mesh: '..tostring(ref:name()))
    ui.offsetCursorY(12)

    if hoveredMaterial ~= ref:materialName() then
      hoveredMaterial = ref:materialName()
      if carPreviewMeshes then carPreviewMeshes:dispose() end
      carPreviewMeshes = filterMeshSelection(targetMeshes, ref)
      carPreviewMeshes:setOutline(rgbm(2, 2, 0, 1))
    end

    local size = ui.imageSize(ref:getTextureSlotFilename('txDiffuse'))
    if size.x > 0 and size.y > 0 then
  
      ui.textWrapped('• Hold Shift and click to start drawing.\n• Hold Ctrl+Shift and click to start drawing using custom AO map.')
  
      ui.offsetCursorY(12)
      ui.textWrapped('For best results, either use a custom AO map or make sure this texture is an AO map (grayscale colors with nothing but shadows):')
      ui.offsetCursorY(8)

      ui.setShadingOffset(1, 0, 1, 1)
      ui.image(ref:getTextureSlotFilename('txDiffuse'), vec2(210, 210 * size.y / size.x))
      ui.resetShadingOffset()

      if uiState.shiftDown and not uiState.altDown and uiState.isMouseLeftKeyClicked and not uiState.wantCaptureMouse then
        if uiState.ctrlDown then
          local _selectedMeshes = filterMeshSelection(targetMeshes, ref)
          local _carTexture = ref:getTextureSlotFilename('txDiffuse')
          os.openFileDialog({
            title = 'Open Base AO Map',
            folder = userCarDir,
            fileTypes = { { name = 'Images', mask = '*.png;*.jpg;*.jpeg;*.dds' } },
            addAllFilesFileType = true,
            flags = bit.bor(os.DialogFlags.PathMustExist, os.DialogFlags.FileMustExist)
          }, function (err, filename)
            if not err and filename then
              if selectedMeshes or not appVisible then _selectedMeshes:dispose(); return end
              clearPreview()
              runtime.session = runtime.session + 1
              selectedMeshes = _selectedMeshes
              trackMode = targetMeshes == trackMeshes
              carTexture = _carTexture
              aoTexture = filename
              if not trackMode then
                camera = ac.grabCamera('Paintshop')
                if camera then camera.ownShare = 0 end
              end
            else
              _selectedMeshes:dispose()
              if err then ui.toast(ui.Icons.Warning, tostring(err)) end
            end
          end)
        else
          selectedMeshes = filterMeshSelection(targetMeshes, ref)
          trackMode = targetMeshes == trackMeshes
          clearPreview()
          runtime.session = runtime.session + 1
          carTexture = ref:getTextureSlotFilename('txDiffuse')
          aoTexture = nil
          if not trackMode then
            camera = ac.grabCamera('Paintshop')
            if camera then camera.ownShare = 0 end
          end
        end
      end
    else
      ui.textWrapped('Este material não tem uma textura txDiffuse válida. Selecione outra parte do carro ou forneça uma textura compatível.')
    end
  else
    clearPreview()
    ui.textWrapped(not sim.isWindowForeground and 'Clique na janela do jogo para dar foco.'
      or uiState.wantCaptureMouse and 'Mova o mouse para a carroceria, fora dos painéis.'
      or 'Passe o mouse sobre a carroceria e use Shift + clique.')
  end
  ui.popFont()
end

local editingCanvasPhase = 0
local lastRay ---@type ray

local stored = ac.storage{
  color = rgbm(0, 0.2, 1, 0.5),
  bgColor = rgbm(1, 1, 1, 1),
  orbitCamera = true,
  projectOtherSide = false,
  eyeDropperRange = 1,
  selectedStickerSet = 2,
  alignSticker = 3,
  activeToolIndex = 1,
  selectedFont = '',
  fontBold = false,
  fontItalic = false,
  hasPen = false
}

local function brushSizeMult(brush)
  local p = ac.getPenPressure()
  if p ~= 1 and not stored.hasPen then stored.hasPen = true end
  return math.lerp(brush.penMinRadiusMult, 1, p)
end

local function brushParams(key, defaultSize, defaultAlpha, extraFields)
  local t = {
    brushTex = '',
    brushSize = defaultSize or 0.05,
    brushAspectMult = 1,
    brushStepSize = 0.005,
    brushAngle = 0,
    brushRandomizedAngle = false,
    brushAlpha = defaultAlpha or 0.5,
    brushMirror = false,
    penMinRadiusMult = 0.05,
    withMirror = false,
    paintThrough = false,
    smoothing = 0
  }
  if extraFields then 
    for k, v in pairs(extraFields) do t[k] = v end
  end
  return ac.storage(t, key)
end

local ignoreMousePress = true
local drawing = false
local brushesDir = __dirname..'/brushes'
local decalsDir = __dirname..'/decals'
local brushes
local stickers
local selectedStickerSet
local selectedBrushOutline ---@type ui.ExtraCanvas
local selectedBrushOutlineDirty = true
local brushDistance = 1
local cameraAngle = vec2(-2.6, 0.1)
local maskingDragging = 0
local saveFilename
local projectFilename
local layers, activeLayerIndex, nextLayerID = {}, 1, 0
-- local maskingCarStored = {} ---@type ac.GeometryShot
local undoStack, redoStack = history.undo, history.redo
local updateAccessibleData
local composeLayers
local projectMetadata
local saveRecoveryDraft
local offerRecoveryDraft
local recoveryPromptedPath

local maskingActive = false
local maskingPos = vec3(0, 0.3, 0)
local maskingDir = vec3(0, 1, 0)
local maskingCreatingFrom, maskingCreatingTo
local maskingPoints = {
  vec3(0, 0.3, -1),
  vec3(0, 0.3, 1),
  vec3(-1, 0.3, 0),
  vec3(1, 0.3, 0),
}

local function drawWithAO(baseCanvas, aoTexture)
  -- Draw base editing canvas and apply AO to it. One way of doing it is to use shading offset:
  -- ui.drawImage(aoTexture, 0, ui.windowSize())
  -- ui.setShadingOffset(0, 0, 0, -1)
  -- ui.drawImage(aoTexture, 0, ui.windowSize(), rgbm.colors.black)
  -- ui.resetShadingOffset()

  -- But now there is another way, to use a custom shader:
  ui.renderShader({
    p1 = vec2(),
    p2 = ui.windowSize(),
    blendMode = render.BlendMode.Opaque,
    textures = {
      txBase = baseCanvas,
      txAO = aoTexture
    },
    shader = [[float4 main(PS_IN pin) {
      float4 diffuseColor = txAO.SampleLevel(samLinear, pin.Tex, 0);
      float4 canvasColor = txBase.SampleLevel(samLinear, pin.Tex, 0);
      canvasColor.rgb *= max(diffuseColor.r, max(diffuseColor.g, diffuseColor.b)); // use maximum value of AO RGB color
      canvasColor.a = 1; // return fully opaque texture so that txDetail would not bleed and CMAA2 would be happy
      return canvasColor;
    }]]
  })
end

local function activeLayer()
  return layers[activeLayerIndex]
end

local function disposeLayers(list)
  for _, layer in ipairs(list or layers) do disposeResource(layer.canvas) end
  if not list then layers, activeLayerIndex = {}, 1 end
end

local function uniqueLayerName(base)
  base = tostring(base or 'Camada'):gsub('^%s+', ''):gsub('%s+$', '')
  if #base == 0 then base = 'Camada' end
  local candidate, suffix = base:sub(1, 80), 2
  while table.findFirst(layers, function (layer) return layer.name == candidate end) do
    candidate = (base:sub(1, 70)..' '..suffix):sub(1, 80)
    suffix = suffix + 1
  end
  return candidate
end

local function createLayer(name, canvas, fill)
  nextLayerID = nextLayerID + 1
  canvas = canvas or ui.ExtraCanvas(vec2(config.resolution, config.resolution)):clear(fill or rgbm(0, 0, 0, 0))
  return {id = nextLayerID, name = uniqueLayerName(name), canvas = canvas, visible = true, opacity = 1}
end

composeLayers = function (refreshData)
  if not editingCanvas then return end
  editingCanvas:clear(rgbm(0, 0, 0, 0))
  editingCanvas:update(function ()
    for _, layer in ipairs(layers) do
      if layer.visible and layer.opacity > 0 then
        ui.drawImage(layer.canvas, 0, ui.windowSize(), rgbm(1, 1, 1, layer.opacity))
      end
    end
  end)
  if refreshData and updateAccessibleData then updateAccessibleData() end
end

local function resetToBaseLayer()
  disposeLayers()
  layers[1] = createLayer('Base', nil, rgbm.new(stored.bgColor.rgb, 1))
  activeLayerIndex = 1
  composeLayers(false)
end

local function markLayerStructureChanged()
  history:push(nil)
  composeLayers(true)
  ac.refreshCarColor(0)
end

local function addBlankLayer(name)
  if #layers >= Project.MAX_LAYERS then
    ui.toast(ui.Icons.Warning, 'Limite de '..Project.MAX_LAYERS..' camadas atingido.')
    return
  end
  layers[#layers + 1] = createLayer(name or 'Camada '..(#layers + 1))
  activeLayerIndex = #layers
  markLayerStructureChanged()
end

local function duplicateActiveLayer()
  local source = activeLayer()
  if not source or #layers >= Project.MAX_LAYERS then
    if #layers >= Project.MAX_LAYERS then ui.toast(ui.Icons.Warning, 'Limite de camadas atingido.') end
    return
  end
  local canvas = ui.ExtraCanvas(vec2(config.resolution, config.resolution)):clear(rgbm(0, 0, 0, 0))
  canvas:update(function () ui.drawImage(source.canvas, 0, ui.windowSize()) end)
  local copy = createLayer(source.name..' cópia', canvas)
  copy.visible, copy.opacity = source.visible, source.opacity
  table.insert(layers, activeLayerIndex + 1, copy)
  activeLayerIndex = activeLayerIndex + 1
  markLayerStructureChanged()
end

local function deleteActiveLayer()
  if #layers <= 1 then ui.toast(ui.Icons.Warning, 'O projeto precisa manter ao menos uma camada.'); return end
  local removed = table.remove(layers, activeLayerIndex)
  disposeResource(removed.canvas)
  activeLayerIndex = math.min(activeLayerIndex, #layers)
  markLayerStructureChanged()
end

local function moveActiveLayer(direction)
  local destination = activeLayerIndex + direction
  if destination < 1 or destination > #layers then return end
  layers[activeLayerIndex], layers[destination] = layers[destination], layers[activeLayerIndex]
  activeLayerIndex = destination
  markLayerStructureChanged()
end

local function layerMemoryFootprint()
  local bytes = editingCanvas and editingCanvas:memoryFootprint() or 0
  for _, layer in ipairs(layers) do bytes = bytes + layer.canvas:memoryFootprint() end
  return bytes
end

runtime.cleanup = function ()
  runtime.session = runtime.session + 1
  runtime.dataRequest = runtime.dataRequest + 1
  history:reset()
  disposeResource(accessibleData)
  disposeResource(editingCanvas)
  disposeLayers()
  disposeResource(aoCanvas)
  disposeResource(maskingCanvas)
  disposeResource(otherSideShot)
  disposeResource(selectedBrushOutline)
  if runtime.disposeTools then runtime.disposeTools() end
  if runtime.resetToolState then runtime.resetToolState() end
  if runtime.resetProjection then runtime.resetProjection() end
  disposeResource(selectedMeshes)
  disposeResource(camera)
  clearPreview()
  accessibleData, editingCanvas, aoCanvas, maskingCanvas, otherSideShot = nil, nil, nil, nil, nil
  camera, selectedBrushOutline = nil, nil
  selectedBrushOutlineDirty, maskingDirty = true, true
  otherSidePhase, otherSideSide, bakKsAmbient = -1, 0, nil
  selectedMeshes = nil
  carTexture, aoTexture = nil, nil
  saveFilename, projectFilename = nil, nil
  drawing, ignoreMousePress, maskingActive, maskingDragging = false, true, false, 0
  lastRay, maskingCreatingFrom, maskingCreatingTo = nil, nil, nil
  cameraPan:set(0, 0)
  runtime.saving, runtime.cameraNavigating, runtime.dialog = false, false, false
  runtime.lastPreviewTime = nil
  recoveryPromptedPath = nil
  editingCanvasPhase = editingCanvasPhase + 1
end

local function finishEditing()
  if selectedMeshes and carTexture then
    selectedMeshes:setMaterialTexture('txDiffuse', carTexture):setMotionStencil(taaFix.Off)
  end
  runtime.cleanup()
  ac.setWindowTitle('paintshop', nil)
  ac.refreshCarColor(0)
  collectgarbage()
end

local function rescanBrushes()
  brushes = table.map(io.scanDir(brushesDir, '*.png'), function (x) return { string.sub(x, 1, #x - 4), brushesDir..'/'..x } end)
  table.sort(brushes, function (a, b) return a[1]:lower() < b[1]:lower() end)
  if #brushes == 0 then brushes = {{'Pincel padrão', 'color::#ffffff'}} end
end

local function rescanStickers()
  local previous = selectedStickerSet and selectedStickerSet.name or config.stickerCategory
  stickers = {}
  for _, x in ipairs(io.scanDir(decalsDir, '*')) do
    if io.dirExists(decalsDir..'/'..x) then
      local items = table.map(io.scanDir(decalsDir..'/'..x, '*.png'), function (y)
        return { string.sub(y, 1, #y - 4), decalsDir..'/'..x..'/'..y }
      end)
      table.sort(items, function (a, b) return a[1]:lower() < b[1]:lower() end)
      table.insert(stickers, {name = x, items = items})
    end
  end
  table.sort(stickers, function (a, b) return a.name:lower() < b.name:lower() end)
  selectedStickerSet = table.findFirst(stickers, function (item) return item.name == previous end)
      or stickers[stored.selectedStickerSet] or stickers[1] or {name = 'Sem categorias', items = {}}
  config.stickerCategory = selectedStickerSet.name
end

local function maskingBackup()
  local b = stringify({ maskingPos, maskingDir, maskingPoints }, true)
  return function (action)
    if action == 'memoryFootprint' then return 0 end
    if action == 'update' then return maskingBackup() end
    if action == 'dispose' then return end
    maskingPos, maskingDir, maskingPoints = table.unpack(stringify.parse(b))
    maskingActive = true
  end
end

local function addUndo(undo)
  history:push(undo)
end

local function canvasBackup()
  local layer = activeLayer()
  if not layer then return nil end
  local bytes = layer.canvas:memoryFootprint()
  if not history:prepare(bytes) then
    ui.toast(ui.Icons.Warning, 'A operação excede o limite de memória do histórico; não poderá ser desfeita.')
    return nil
  end
  return layer.canvas:backup()
end

local function stepUndo()
  if history:stepUndo() then composeLayers(true); ac.refreshCarColor(0) end
end

local function stepRedo()
  if history:stepRedo() then composeLayers(true); ac.refreshCarColor(0) end
end

local function undoMemoryFootpring()
  return history:memoryFootprint()
end

updateAccessibleData = function ()
  if not editingCanvas then return end
  editingCanvasPhase = editingCanvasPhase + 1
  runtime.dataRequest = runtime.dataRequest + 1
  local canvas, session, request = editingCanvas, runtime.session, runtime.dataRequest
  disposeResource(accessibleData)
  accessibleData = nil
  canvas:accessData(function (err, data)
    if session ~= runtime.session or request ~= runtime.dataRequest or canvas ~= editingCanvas then
      disposeResource(data)
      return
    end
    if data then accessibleData = data
    elseif err then ac.warn('Failed to access canvas: '..tostring(err)) end
  end)
end

local autosaveRoot = ac.getFolder(ac.FolderID.Cfg)..'/apps/paintshop/autosave'
local backupsDir = ac.getFolder(ac.FolderID.Cfg)..'/apps/paintshop/backups'
local autosaveDir = autosaveRoot
local autosavePhase, autosaveTime = -1, -1e9

setInterval(function ()
  if not editingCanvas or runtime.saving or autosavePhase == editingCanvasPhase or drawing
      or uiState.isMouseLeftKeyDown or ui.time() - autosaveTime < config.autosaveSeconds then return end
  autosaveTime = ui.time()
  if not io.dirExists(autosaveDir) then io.createDir(autosaveDir) end
  local index = math.clamp(math.floor(config.autosaveSlot), 1, 10)
  local filename = string.format('%s/autosave-%02d.dds', autosaveDir, index)
  local ok, err = Files.saveCanvas(editingCanvas, filename, backupsDir, false)
  if ok then
    autosavePhase = editingCanvasPhase
    config.autosaveSlot = index % 10 + 1
    io.save(filename..'.json', JSON.stringify({car = ac.getCarID(0), skin = ac.getCarSkinID(0),
      texture = carTexture, ao = aoTexture, resolution = config.resolution, time = os.time(),
      layers = #layers, project = projectFilename}), true)
  else
    ac.warn('Paintshop autosave: '..tostring(err))
    ui.toast(ui.Icons.Warning, 'Falha no autosave: '..tostring(err))
  end
end, 5)

local function IconButton(icon, tooltip, active, enabled)
  local r = ui.button('##'..icon, vec2(32, 32), enabled == false and ui.ButtonFlags.Disabled or active and ui.ButtonFlags.Active or ui.ButtonFlags.None)
  ui.addIcon(icon, 24, 0.5, nil, 0)
  if tooltip and ui.itemHovered() then ui.setTooltip(tooltip) end
  return r
end

local function refreshCanvasLater()
  local session, canvas = runtime.session, editingCanvas
  setTimeout(function ()
    if session == runtime.session and canvas == editingCanvas then composeLayers(true) end
  end)
end

local function chooseFile(save, params, callback)
  if runtime.dialog or runtime.saving or drawing then return end
  local session, canvas = runtime.session, editingCanvas
  runtime.dialog = true
  local dialog = save and os.saveFileDialog or os.openFileDialog
  dialog(params, function (err, filename)
    if session ~= runtime.session or canvas ~= editingCanvas then return end
    runtime.dialog = false
    if err then ui.toast(ui.Icons.Warning, tostring(err)); return end
    if filename then callback(filename) end
  end)
end

local function loadArtwork(filename, imported, recovered)
  local session, canvas = runtime.session, editingCanvas
  local function apply()
    if session ~= runtime.session or canvas ~= editingCanvas or drawing then return end
    if imported and #layers >= Project.MAX_LAYERS then
      ui.toast(ui.Icons.Warning, 'Limite de '..Project.MAX_LAYERS..' camadas atingido.')
      return
    end
    ui.setAsynchronousImagesLoading(false)
    ui.unloadImage(filename)
    local size = ui.imageSize(filename)
    if size.x <= 0 or size.y <= 0 then
      ui.toast(ui.Icons.Warning, 'Não foi possível abrir esta imagem.')
      return
    end
    local layerCanvas = ui.ExtraCanvas(vec2(config.resolution, config.resolution))
      :clear(imported and rgbm(0, 0, 0, 0) or rgbm.new(stored.bgColor.rgb, 1))
    layerCanvas:update(function () ui.drawImage(filename, 0, ui.windowSize()) end)
    if imported then
      layers[#layers + 1] = createLayer(io.getFileName(filename, true), layerCanvas)
      activeLayerIndex = #layers
      history:push(nil)
    else
      history:reset()
      disposeLayers()
      layers[1] = createLayer(io.getFileName(filename, true), layerCanvas)
      activeLayerIndex = 1
      projectFilename = nil
      saveFilename = not recovered and Files.extension(filename) ~= 'dds' and filename or nil
      if recovered then history:push(nil) else history:markSaved() end
    end
    composeLayers(true)
    ui.toast(ui.Icons.Confirm, recovered and 'Autosave recuperado. Salve a arte para preservar esta versão.' or 'Imagem carregada.')
  end
  if not imported and history:isDirty() then
    ui.modalPopup('Substituir pintura?', 'Há alterações não salvas. Substituir a imagem atual?', function (ok)
      if ok then apply() end
    end)
  else apply() end
end

local function saveArtwork(asNew)
  local function save(filename)
    filename = Files.ensureExtension(filename, 'png')
    local revision = history.revision
    runtime.saving = true
    local ok, err = Files.saveCanvas(editingCanvas, filename, backupsDir, true)
    runtime.saving = false
    if ok then
      saveFilename = filename
      if #layers == 1 and not projectFilename then history:markSaved(revision) end
      ui.toast(ui.Icons.Confirm, 'Imagem achatada salva: '..io.getFileName(filename)
        ..(#layers > 1 and '\nSalve também o projeto .pspaint para preservar as camadas.' or ''))
    else ui.toast(ui.Icons.Warning, 'Falha ao salvar: '..tostring(err)) end
  end
  if saveFilename and not asNew then save(saveFilename); return end
  chooseFile(true, {
    title = 'Salvar arte sem AO', folder = userCarSkinDir,
    fileTypes = {{name = 'PNG (recomendado)', mask = '*.png'}, {name = 'JPEG', mask = '*.jpg;*.jpeg'}},
    fileName = io.getFileName(carTexture, true)..'-arte.png', defaultExtension = 'png'
  }, save)
end

projectMetadata = function ()
  return {car = ac.getCarID(0), skin = ac.getCarSkinID(0), texture = carTexture,
    ao = aoTexture, trackMode = trackMode, savedAt = os.time()}
end

local function archiveSavedRecoveryDraft(metadata)
  local filename = autosaveDir..'/recovery.pspaint'
  if not io.fileExists(filename) then return true end
  local manifest = Project.inspect(filename)
  local draft = manifest and manifest.metadata or nil
  if not draft or draft.car ~= metadata.car or draft.skin ~= metadata.skin
      or draft.texture ~= metadata.texture then return true end
  local index = 1
  local archived
  repeat
    archived = string.format('%s/recovery-saved-%d-%02d.pspaint', autosaveDir, os.time(), index)
    index = index + 1
  until not io.fileExists(archived)
  return io.move(filename, archived)
end

local function saveProject(asNew)
  local function save(filename)
    filename = Files.ensureSpecificExtension(filename, 'pspaint')
    local metadata = projectMetadata()
    local entries, buildError = Project.buildEntries(layers, config.resolution, activeLayerIndex, metadata)
    if not entries then ui.toast(ui.Icons.Warning, 'Falha ao preparar projeto: '..tostring(buildError)); return end
    local temporary = Files.temporarySibling(filename, 'pspaint')
    local session, revision = runtime.session, history.revision
    runtime.saving = true
    local started, startError = pcall(function ()
      io.createZipAsync(temporary, entries, function (err)
        local ok, failure = false, err
        if not err then ok, failure = Files.commitTemporary(temporary, filename, backupsDir, true) end
        if session == runtime.session then
          runtime.saving = false
          if ok then
            projectFilename = filename
            history:markSaved(revision)
            if not archiveSavedRecoveryDraft(metadata) then
              ui.toast(ui.Icons.Warning, 'Projeto salvo, mas o rascunho antigo continua na pasta de recuperação.')
            end
            ui.toast(ui.Icons.Confirm, 'Projeto com '..#layers..' camada(s) salvo: '..io.getFileName(filename))
          else ui.toast(ui.Icons.Warning, 'Falha ao salvar projeto: '..tostring(failure)) end
        end
      end)
    end)
    if not started and session == runtime.session then
      runtime.saving = false
      ui.toast(ui.Icons.Warning, 'Falha ao iniciar o salvamento: '..tostring(startError))
    end
  end
  if projectFilename and not asNew then save(projectFilename); return end
  chooseFile(true, {
    title = 'Salvar projeto editável', folder = userCarSkinDir,
    fileTypes = {{name = 'Projeto Paintshop', mask = '*.pspaint'}},
    fileName = io.getFileName(carTexture, true)..'.pspaint', defaultExtension = 'pspaint'
  }, save)
end

local function adoptProject(filename, project)
  history:reset()
  disposeResource(accessibleData); accessibleData = nil
  disposeResource(editingCanvas)
  disposeLayers()
  disposeResource(aoCanvas)
  disposeResource(maskingCanvas); maskingCanvas = nil
  disposeResource(otherSideShot); otherSideShot = nil
  runtime.dataRequest = runtime.dataRequest + 1
  config.resolution = project.resolution
  editingCanvas = ui.ExtraCanvas(vec2(config.resolution, config.resolution)):clear(rgbm(0, 0, 0, 0))
  aoCanvas = ui.ExtraCanvas(vec2(config.resolution, config.resolution), 4, render.AntialiasingMode.CMAA)
  selectedMeshes:setMaterialTexture('txDiffuse', aoCanvas)
  for _, layer in ipairs(project.layers) do
    nextLayerID = nextLayerID + 1
    layer.id = nextLayerID
    layers[#layers + 1] = layer
  end
  activeLayerIndex = math.clamp(project.activeLayer, 1, #layers)
  projectFilename, saveFilename = filename, nil
  maskingDirty, otherSidePhase, otherSideSide = true, -1, 0
  composeLayers(true)
  history:markSaved()
  local metadata = project.metadata or {}
  if metadata.car and (metadata.car ~= ac.getCarID(0) or metadata.texture ~= carTexture) then
    ui.toast(ui.Icons.Warning, 'Projeto aberto, mas foi criado para outro carro ou textura. Confira o alinhamento antes de exportar.')
  else ui.toast(ui.Icons.Confirm, 'Projeto aberto: '..#layers..' camada(s).') end
end

local function openProject()
  local function load(filename)
    local project, err = Project.load(filename, function (resolution)
      return ui.ExtraCanvas(vec2(resolution, resolution)):clear(rgbm(0, 0, 0, 0))
    end)
    if not project then ui.toast(ui.Icons.Warning, 'Falha ao abrir projeto: '..tostring(err)); return end
    adoptProject(filename, project)
  end
  local function choose()
    chooseFile(false, {title = 'Abrir projeto editável', folder = userCarSkinDir,
      fileTypes = {{name = 'Projeto Paintshop', mask = '*.pspaint'}}}, load)
  end
  if history:isDirty() then
    ui.modalPopup('Substituir projeto?', 'Há alterações não salvas. Abrir outro projeto?', function (ok)
      if ok then choose() end
    end)
  else choose() end
end

saveRecoveryDraft = function (callback)
  if not editingCanvas or #layers == 0 or not history:isDirty() then
    if callback then callback(true) end
    return
  end
  if runtime.recoverySaving then
    if callback then setTimeout(function () saveRecoveryDraft(callback) end) end
    return
  end
  if not io.dirExists(autosaveDir) and not io.createDir(autosaveDir) then
    if callback then callback(false, 'Não foi possível criar a pasta de recuperação.') end
    return
  end
  local entries, err = Project.buildEntries(layers, config.resolution, activeLayerIndex, projectMetadata())
  if not entries then
    if callback then callback(false, err) end
    return
  end
  local filename = autosaveDir..'/recovery.pspaint'
  local temporary = Files.temporarySibling(filename, 'pspaint')
  local revision = history.revision
  runtime.recoverySaving = true
  local started, startError = pcall(function ()
    io.createZipAsync(temporary, entries, function (zipError)
      local ok, failure = false, zipError
      if not zipError then ok, failure = Files.commitTemporary(temporary, filename, backupsDir, false) end
      runtime.recoverySaving = false
      if ok then
        runtime.recoveryRevision = revision
      elseif appVisible then
        ui.toast(ui.Icons.Warning, 'Falha ao gravar recuperação: '..tostring(failure))
      end
      if callback then callback(ok, failure) end
    end)
  end)
  if not started then
    runtime.recoverySaving = false
    if callback then callback(false, startError) end
  end
end

offerRecoveryDraft = function ()
  local filename = autosaveDir..'/recovery.pspaint'
  if recoveryPromptedPath == filename then return end
  recoveryPromptedPath = filename
  if not io.fileExists(filename) then return end
  local session = runtime.session
  setTimeout(function ()
    if session ~= runtime.session or not appVisible or not selectedMeshes or not editingCanvas then return end
    ui.modalPopup('Continuar rascunho?', 'Foi encontrado um rascunho com camadas para esta textura. Deseja restaurar a última edição?', function (ok)
      if not ok or session ~= runtime.session or not editingCanvas then return end
      local project, loadError = Project.load(filename, function (resolution)
        return ui.ExtraCanvas(vec2(resolution, resolution)):clear(rgbm(0, 0, 0, 0))
      end)
      if not project then ui.toast(ui.Icons.Warning, 'Não foi possível restaurar o rascunho: '..tostring(loadError)); return end
      local metadata = project.metadata or {}
      if metadata.car ~= ac.getCarID(0) or metadata.skin ~= ac.getCarSkinID(0) or metadata.texture ~= carTexture then
        disposeLayers(project.layers)
        ui.toast(ui.Icons.Warning, 'O rascunho pertence a outro carro, skin ou textura.')
        return
      end
      adoptProject(filename, project)
      projectFilename = nil
      history:markSaved()
      ui.toast(ui.Icons.Confirm, 'Rascunho recuperado; salve como .pspaint para manter seu projeto.')
    end)
  end)
end

local function recoverAutosave()
  chooseFile(false, {
    title = 'Recuperar autosave (arte sem AO)', folder = autosaveDir,
    fileTypes = {{name = 'Autosaves DDS', mask = '*.dds'}, {name = 'PNG', mask = '*.png'}}
  }, function (filename)
    local metadata = io.load(filename..'.json')
    if metadata then
      local ok, data = pcall(JSON.parse, metadata)
      if ok and type(data) == 'table' then
        if data.car ~= ac.getCarID(0) or data.skin ~= ac.getCarSkinID(0) or data.texture ~= carTexture then
          ui.toast(ui.Icons.Warning, 'Este autosave pertence a outro carro, skin ou textura. Use Importar se deseja adaptá-lo.')
          return
        end
      end
    end
    loadArtwork(filename, false, true)
  end)
end

local function exportTexture(filename)
  filename = Files.ensureExtension(filename, 'dds')
  runtime.saving = true
  local output
  local ok, err = pcall(function ()
    output = ui.ExtraCanvas(editingCanvas:size(), 4, render.AntialiasingMode.CMAA)
    output:update(function () drawWithAO(editingCanvas, aoTexture or carTexture) end)
    output:applyAntialiasing():mipsUpdate()
    local saved, failure = Files.saveCanvas(output, filename, backupsDir, true)
    if not saved then error(failure) end
  end)
  disposeResource(output)
  runtime.saving = false
  if ok then return true end
  return false, tostring(err)
end

local function exportNewSkin()
  if trackMode then return end
  local session = runtime.session
  ui.modalPrompt('Exportar nova skin', 'Nome da pasta (sem barras):', '', function (name)
    if session ~= runtime.session or not editingCanvas or drawing then return end
    if not Files.validName(name) then
      if name then ui.toast(ui.Icons.Warning, 'Nome inválido para a skin.') end
      return
    end
    local destination = userCarDir..'/skins/'..name
    local ok, err = Files.copySkin(userCarSkinDir, destination)
    if not ok then ui.toast(ui.Icons.Warning, tostring(err)); return end
    local baseName = io.getFileName(carTexture)
    ok, err = exportTexture(destination..'/'..baseName)
    if not ok then ui.toast(ui.Icons.Warning, tostring(err)..'\nSkin parcial: '..destination); return end
    local artFilename = destination..'/'..io.getFileName(carTexture, true)..'-arte.png'
    ok, err = Files.saveCanvas(editingCanvas, artFilename, backupsDir, true)
    if not ok then ui.toast(ui.Icons.Warning, 'Textura exportada, mas a arte não foi salva: '..tostring(err)); return end
    local metadata = {}
    local raw = io.load(destination..'/ui_skin.json')
    if raw then
      local parsed, value = pcall(JSON.parse, raw)
      if parsed and type(value) == 'table' then metadata = value end
    end
    metadata.skinname = name
    if not io.save(destination..'/ui_skin.json', JSON.stringify(metadata), true) then
      ui.toast(ui.Icons.Warning, 'Arte e textura salvas, mas ui_skin.json falhou: '..destination)
      return
    end
    saveFilename = artFilename
    if #layers == 1 and not projectFilename then history:markSaved() end
    ui.toast(ui.Icons.Confirm, 'Nova skin criada: '..name..'. Selecione-a na próxima sessão e atualize a preview no Content Manager.'
      ..(#layers > 1 and '\nO projeto em camadas continua com alterações pendentes.' or ''))
  end)
end

local function DrawControl()
  local busy = drawing or runtime.dialog or runtime.saving or runtime.recoverySaving
  local titleSource = projectFilename or saveFilename or carTexture..' (novo)'
  ac.setWindowTitle('paintshop', string.gsub(titleSource, '.+[/\\:]', '')..(history:isDirty() and '*' or ''))

  if IconButton(icons.Undo, nil, false, not busy and #undoStack > 0) or not busy and #undoStack > 0 and shortcuts.undo() then
    stepUndo()
  end
  if ui.itemHovered() then    
    ui.setTooltip(string.format('Desfazer (Ctrl+Z)\n%d estados; %.0f / %d MB de histórico', #undoStack, undoMemoryFootpring() / (1024 * 1024), config.historyMB))
  end
  ui.sameLine(0, 4)
  if IconButton(icons.Redo, string.format('Refazer (Ctrl+Y)\n%d estados', #redoStack), false, not busy and #redoStack > 0) or not busy and #redoStack > 0 and shortcuts.redo() then
    stepRedo()
  end
  ui.sameLine(0, 4)  
  if IconButton(icons.Open, 'Abrir imagem achatada (Ctrl+O)\nBotão direito: projeto, importar, limpar e autosave.', false, not busy) or not busy and shortcuts.load() then
    chooseFile(false, {title = 'Abrir arte sem AO', folder = userCarSkinDir,
      fileTypes = {{name = 'Imagens', mask = '*.png;*.jpg;*.jpeg;*.dds'}}},
      function (filename) loadArtwork(filename, false, false) end)
  end
  ui.itemPopup('openMenu', function ()
    if busy then ui.text('Aguarde o fim da operação.'); return end
    if ui.selectable('Abrir projeto .pspaint…') then openProject() end
    if ui.selectable('Limpar camada ativa') then
      local session = runtime.session
      ui.modalPopup('Limpar camada?', 'Apagar o conteúdo da camada ativa?', function (ok)
        if not ok or session ~= runtime.session or not editingCanvas or drawing then return end
        addUndo(canvasBackup())
        local layer = activeLayer()
        if layer then
          layer.canvas:clear(activeLayerIndex == 1 and rgbm.new(stored.bgColor.rgb, 1) or rgbm(0, 0, 0, 0))
          composeLayers(true)
        end
      end)
    end
    if ui.itemHovered() then
      ui.setTooltip('A camada Base usa a cor de fundo; as demais ficam transparentes.')
    end
    if ui.selectable('Importar sobre a pintura…') then
      chooseFile(false, {title = 'Importar', folder = userCarSkinDir,
        fileTypes = {{name = 'Imagens', mask = '*.png;*.jpg;*.jpeg;*.dds'}}},
        function (filename) loadArtwork(filename, true, false) end)
    end
    if ui.selectable('Recuperar autosave…') then recoverAutosave() end
    if autosaveDir and ui.selectable('Abrir pasta dos autosaves') then
      io.createDir(autosaveDir)
      os.openInExplorer(autosaveDir)
    end
  end)
  ui.sameLine(0, 4)
  if IconButton(icons.Save, 'Salvar (Ctrl+S)\nCom camadas, salva projeto .pspaint.\nBotão direito: projeto e imagem achatada.', false, not busy) or not busy and shortcuts.save() then
    if projectFilename or #layers > 1 then saveProject(false) else saveArtwork(false) end
  end
  ui.itemPopup('saveMenu', function ()
    if busy then ui.text('Aguarde o fim da operação.'); return end
    if ui.selectable('Salvar projeto como…') then saveProject(true) end
    if ui.selectable('Salvar imagem achatada como…') then saveArtwork(true) end
    if ui.selectable('Recuperar autosave…') then recoverAutosave() end
    if ui.selectable('Abrir backups dos arquivos substituídos') then
      io.createDir(backupsDir)
      os.openInExplorer(backupsDir)
    end
    if autosaveDir and ui.selectable('Abrir pasta dos autosaves') then
      io.createDir(autosaveDir)
      os.openInExplorer(autosaveDir)
    end
  end)
  ui.sameLine(0, 4)  
  if IconButton(icons.Export, 'Exportar textura com AO (Ctrl+Shift+Alt+S)\nSalve também o projeto .pspaint para continuar editando depois.', false, not busy) or not busy and shortcuts.export() then
    chooseFile(true, {
      title = 'Exportar textura final com AO',
      folder = userCarSkinDir,
      fileTypes = { { name = 'PNG', mask = '*.png' }, { name = 'JPEG', mask = '*.jpg;*.jpeg' }, { name = 'DDS', mask = '*.dds' } },
      fileName = carTexture and string.gsub(carTexture, '.+[/\\:]', ''),
      fileTypeIndex = 3,
      defaultExtension = 'dds',
    }, function (filename)
      local ok, err = exportTexture(filename)
      ui.toast(ok and ui.Icons.Confirm or ui.Icons.Warning,
        ok and 'Textura exportada com AO. Preserve também a arte em PNG.' or 'Falha ao exportar: '..tostring(err))
    end)
  end
  ui.itemPopup('exportMenu', function ()
    if busy then ui.text('Aguarde o fim da operação.'); return end
    if not trackMode and ui.selectable('Exportar como nova skin…') then exportNewSkin() end
  end)
  ui.sameLine(0, 4)
  if IconButton(ui.Icons.Leave, history:isDirty() and 'Sair: existem alterações não salvas' or 'Finalizar edição', false, not busy) then
    if history:isDirty() then
      local session = runtime.session
      ui.modalPopup('Salvar rascunho e sair?', 'O Paintshop vai guardar uma cópia recuperável com as camadas antes de encerrar esta prévia. A textura do carro só fica permanente depois de exportar.', function (okPressed)
        if okPressed and session == runtime.session then
          saveRecoveryDraft(function (ok, err)
            if session ~= runtime.session then return end
            if not ok then ui.toast(ui.Icons.Warning, 'Falha ao salvar rascunho: '..tostring(err)); return end
            finishEditing()
          end)
        end
      end)
    else
      finishEditing()
    end
  end
end

local palette = {
  builtin = { 
    rgbm(1, 1, 1, 1),
    rgbm(0.8, 0.8, 0.8, 1),
    rgbm(0.6, 0.6, 0.6, 1),
    rgbm(1, 0, 0, 1),
    rgbm(1, 0.5, 0, 1),
    rgbm(1, 1, 0, 1),
    rgbm(0.5, 1, 0, 1),
    rgbm(0, 1, 0, 1),
    rgbm(0, 1, 0.5, 1),
    rgbm(0, 1, 1, 1),
    rgbm(0, 0.5, 1, 1),
    rgbm(0, 0, 1, 1),
    rgbm(0.5, 0, 1, 1),
    rgbm(1, 0, 1, 1),
    rgbm(1, 0, 0.5, 1),
    rgbm(0, 0, 0, 1),
    rgbm(0.2, 0.2, 0.2, 1),
    rgbm(0.4, 0.4, 0.4, 1),
    rgbm(1, 0, 0, 1):scale(0.5),
    rgbm(1, 0.5, 0, 1):scale(0.5),
    rgbm(1, 1, 0, 1):scale(0.5),
    rgbm(0.5, 1, 0, 1):scale(0.5),
    rgbm(0, 1, 0, 1):scale(0.5),
    rgbm(0, 1, 0.5, 1):scale(0.5),
    rgbm(0, 1, 1, 1):scale(0.5),
    rgbm(0, 0.5, 1, 1):scale(0.5),
    rgbm(0, 0, 1, 1):scale(0.5),
    rgbm(0.5, 0, 1, 1):scale(0.5),
    rgbm(1, 0, 1, 1):scale(0.5),
    rgbm(1, 0, 0.5, 1):scale(0.5),
  },
  user = stringify.tryParse(ac.storage.palette) or table.range(15, function (index, callbackData)
    return rgbm(math.random(), math.random(), math.random(), 1)
  end)
}

function palette.addToUserPalette(color)
  local _, i = table.findFirst(palette.user, function (item) return item == color end)
  if i ~= nil then
    table.remove(palette.user, i)
  else
    table.remove(palette.user, 1)
  end
  table.insert(palette.user, color:clone())
  ac.storage.palette = stringify(palette.user, true)
end

local function ColorTooltip(color)
  ui.tooltip(0, function ()
    ui.dummy(20)
    ui.drawRectFilled(0, 20, color)
    ui.drawRect(0, 20, rgbm.colors.black)
  end)
end

local editing = false
local colorFlags = bit.bor(ui.ColorPickerFlags.NoAlpha, ui.ColorPickerFlags.NoSidePreview, ui.ColorPickerFlags.PickerHueWheel, ui.ColorPickerFlags.DisplayHex)

local function ColorBlock(key)
  key = key or 'color'
  local col = stored[key]:clone()
  ui.colorPicker('##color', col, colorFlags)
  if ui.itemEdited() then
    stored[key] = col
    editing = true
  elseif editing and not ui.itemActive() then
    editing = false
    palette.addToUserPalette(col)
  end
  for i = 1, #palette.builtin do
    ui.drawRectFilled(ui.getCursor(), ui.getCursor() + 14, palette.builtin[i])
    if ui.invisibleButton(i, 14) then
      stored[key] = palette.builtin[i]:clone()
      palette.addToUserPalette(stored[key])
    end
    if ui.itemHovered() then      
      ColorTooltip(palette.builtin[i])
    end
    ui.sameLine(0, 0)
    if i % 15 == 0 then
      ui.newLine(0)
    end
  end
  for i = 1, #palette.user do
    ui.drawRectFilled(ui.getCursor(), ui.getCursor() + 14, palette.user[i])
    if ui.invisibleButton(100 + i, 14) then
      stored[key] = palette.user[i]:clone()
      palette.addToUserPalette(stored[key])
    end
    if ui.itemHovered() then      
      ColorTooltip(palette.user[i])
    end
    ui.sameLine(0, 0)
  end
  ui.newLine()
  if shortcuts.swapColors() then
    stored[key] = stored[key] == palette.user[#palette.user] and palette.user[#palette.user - 1] or palette.user[#palette.user]
    palette.addToUserPalette(stored[key])
  end
end

local function BrushBaseBlock(brush, maxSize, stickerMode, noStepSize, noSymmetry)
  if not ui.mouseBusy() and not runtime.dialog then
    local w = ui.mouseWheel()
    if uiState.ctrlDown and uiState.shiftDown then w = 0 end
    if not uiState.wantCaptureKeyboard then
      if ui.keyboardButtonPressed(ui.KeyIndex.SquareOpenBracket, true) then w = w - 1 end
      if ui.keyboardButtonPressed(ui.KeyIndex.SquareCloseBracket, true) then w = w + 1 end
    end
    if w ~= 0 then -- changing brush size with mouse wheel
      if uiState.shiftDown then w = w / 10 end
      if uiState.altDown then
        brush.brushAngle = brush.brushAngle + w * 30
      elseif not uiState.ctrlDown then
        brush.brushSize = math.clamp(brush.brushSize * (1 + w * 0.15), 0.001, maxSize)        
      elseif stickerMode then
        brush.brushAspectMult = math.clamp(brush.brushAspectMult * (1 + w * 0.25), 0.04, 25)
      end
      selectedBrushOutlineDirty = true
    end
    for i = 0, 9 do -- changing opacity photoshop style
      if shortcuts.opacity[i]() then brush.brushAlpha = i == 0 and 1 or i / 10 end
    end
  end

  if stickerMode then
    if ui.checkbox('Flip sticker', brush.brushMirror) or shortcuts.flipSticker() then brush.brushMirror = not brush.brushMirror end
    if ui.itemHovered() then ui.setTooltip('Flip sticker (Z)') end
  end

  brush.brushSize = ui.slider('##brushSize', brush.brushSize * 100, 0.1, maxSize * 100, 'Size: %.1f cm', 2) / 100
  if ui.itemHovered() then ui.setTooltip('Roda: tamanho do pincel. Ctrl+Shift+roda: zoom da câmera.') end
  if ui.itemEdited() then selectedBrushOutlineDirty = true end

  if stored.hasPen then
    brush.penMinRadiusMult = ui.slider('##penMinRadiusMult', brush.penMinRadiusMult * 100, 0, 100, 'Minimum size: %.1f%%') / 100
    if ui.itemHovered() then ui.setTooltip('Size of a brush with minimum pen pressure') end
  end

  if stickerMode then
    ui.setNextItemWidth(ui.availableSpaceX() - 60)
    brush.brushAspectMult = ui.slider('##brushAspectMult', brush.brushAspectMult * 100, 4, 2500, 'Stretch: %.0f%%', 4) / 100
    if ui.itemHovered() then ui.setTooltip('Use mouse wheel and hold Ctrl to quickly change size') end
    if ui.itemEdited() then selectedBrushOutlineDirty = true end
    ui.sameLine(0, 4)
    if ui.button('Reset', vec2(56, 0)) then
      brush.brushAspectMult = 1
      selectedBrushOutlineDirty = true
    end
  end

  if not stickerMode and not noStepSize then
    brush.brushStepSize = ui.slider('##brushStepSize', brush.brushStepSize * 100, 0.1, 50, 'Step size: %.1f cm', 2) / 100
  end

  brush.brushAlpha = ui.slider('##alpha', brush.brushAlpha * 100, 0, 100, 'Opacity: %.1f%%') / 100
    if ui.itemHovered() then ui.setTooltip('Use digit buttons to quickly change opacity') end

  if ui.checkbox('##randomAngle', brush.brushRandomizedAngle) then brush.brushRandomizedAngle = not brush.brushRandomizedAngle end
  if ui.itemHovered() then ui.setTooltip('Randomize angle when drawing') end
  ui.sameLine(0, 4)
  ui.setNextItemWidth(210 - 22 - 4 - 60)
  brush.brushAngle = (brush.brushAngle % 360 + 360) % 360
  brush.brushAngle = ui.slider('##brushAngle', brush.brushAngle, 0, 360, 'Angle: %.0f°')
  if ui.itemHovered() then ui.setTooltip('Use mouse wheel and hold Alt to quickly change angle') end
  ui.sameLine(0, 4)
  if ui.button('Reset##angle', vec2(56, 0)) then
    brush.brushAngle = 0
  end

  if not stickerMode and not noStepSize then
    brush.smoothing = ui.slider('##smoothing', brush.smoothing * 100, 0, 100, 'Smoothing: %.1f%%') / 100
      if ui.itemHovered() then ui.setTooltip('Smoothing makes brush move smoother and slower') end
  end

  if not noSymmetry and not trackMode then
    if ui.checkbox('With symmetry', brush.withMirror) or shortcuts.toggleSymmetry() then brush.withMirror = not brush.withMirror end
    if ui.itemHovered() then ui.setTooltip('Paint with symmetry (Y)\nMirrors things from one side of a car to another') end
  end

  if ui.checkbox('Paint through', brush.paintThrough) or shortcuts.toggleDrawThrough() then brush.paintThrough = not brush.paintThrough end
  if ui.itemHovered() then ui.setTooltip('Paint through model (R)\nIf enabled, drawings would go through model and leave traces on the opposite side as well') end
end

local function BrushBlock(brush)
  if brush.brushTex == '' then brush.brushTex = brushes[1][2] end
  local anySelected = false
  ui.childWindow('brushesList', vec2(210, 60), false, bit.bor(ui.WindowFlags.HorizontalScrollbar, ui.WindowFlags.AlwaysHorizontalScrollbar, ui.WindowFlags.NoBackground), function ()
    ui.pushStyleColor(ui.StyleColor.Button, rgbm.colors.transparent)
    for i = 1, #brushes do
      local selected = brushes[i][2] == brush.brushTex
      if ui.button('##'..i, 48, selected and ui.ButtonFlags.Active or ui.ButtonFlags.None) then 
        brush.brushTex = brushes[i][2]
        selectedBrushOutlineDirty = true
      end
      if selected then
        anySelected = true
      end
      ui.addIcon(brushes[i][2], 36, 0.5, nil, 0)
      if ui.itemHovered() then ui.setTooltip('Brush: '..brushes[i][1]) end
      ui.sameLine(0, 4)
    end
    ui.popStyleColor()
    ui.newLine()
  end)
  if not anySelected then
    brush.brushTex = brushes[1][2]
  end
  ui.itemPopup(function ()
    if ui.selectable('Open in Explorer') then
      os.openInExplorer(brushesDir)
    end
    if ui.selectable('Refresh') then
      rescanBrushes()
    end
  end)
end

local function fitMaskingPoints(fitFirst)
  if fitFirst then
    maskingDir = math.cross(maskingPoints[1] - maskingPoints[2], maskingPoints[4] - maskingPoints[3]):normalize()
    maskingPos = (maskingPoints[1] + maskingPoints[2]) / 2
    local ort1 = math.cross(maskingDir, vec3(1, 0, 0)):normalize()
    local ort2 = math.cross(maskingDir, vec3(0, 0, 1)):normalize()
    maskingPoints[3] = vec3(maskingPoints[3].x, maskingPos.y - maskingPos.z * ort1.y / ort1.z + ort2.y * maskingPoints[3].x / ort2.x, 0)
    maskingPoints[4] = vec3(maskingPoints[4].x, maskingPos.y - maskingPos.z * ort1.y / ort1.z + ort2.y * maskingPoints[4].x / ort2.x, 0)
  else
    maskingDir = math.cross(maskingPoints[1] - maskingPoints[2], maskingPoints[4] - maskingPoints[3]):normalize()
    maskingPos = (maskingPoints[3] + maskingPoints[4]) / 2
    local ort2 = math.cross(maskingDir, vec3(0, 0, 1)):normalize()
    local ort1 = math.cross(maskingDir, vec3(1, 0, 0)):normalize()
    maskingPoints[1] = vec3(0, maskingPos.y - maskingPos.x * ort2.y / ort2.x + ort1.y * maskingPoints[1].z / ort1.z, maskingPoints[1].z)
    maskingPoints[2] = vec3(0, maskingPos.y - maskingPos.x * ort2.y / ort2.x + ort1.y * maskingPoints[2].z / ort1.z, maskingPoints[2].z)
  end
end

local function applyQuickMasking(from, to)
  if math.abs(from.x - to.x) < math.abs(from.z - to.z) then
    maskingPoints[1] = vec3(0, from.y, from.z)
    maskingPoints[2] = vec3(0, to.y, to.z)
    maskingPoints[3] = vec3(-1, 0, 0)
    maskingPoints[4] = vec3(1, 0, 0)
    fitMaskingPoints(true)
  else
    maskingPoints[1] = vec3(0, 0, -1)
    maskingPoints[2] = vec3(0, 0, 1)
    maskingPoints[3] = vec3(from.x, from.y, 0)
    maskingPoints[4] = vec3(to.x, to.y, 0)
    fitMaskingPoints(false)
  end
end

local function getBrushUp(dir, tool)
  local brush = tool.brush
  return mat4x4.rotation(math.rad(brush.brushRandomizedAngle and tool.__brushRandomAngle or brush.brushAngle), dir):transformVector(trackMode and vec3(0, 1, 0) or userCar.up)
end

local function reflectBrush(pos, dir, up)
  local axis = ({'x', 'y', 'z'})[config.mirrorAxis]
  pos[axis], dir[axis], up[axis] = 2 * config.mirrorOffset - pos[axis], -dir[axis], -up[axis]
end

local fonts
local fontsDir = __dirname..'/fonts'
local function rescanFonts()
  fonts = {
    { name = 'Arial', source = 'Arial:@System' },
    { name = 'Bahnschrift', source = 'Bahnschrift:@System' },
    { name = 'Calibri', source = 'Calibri:@System' },
    { name = 'Comic Sans MS', source = 'Comic Sans MS:@System' },
    { name = 'Consolas', source = 'Consolas' },
    { name = 'Courier New', source = 'Courier New:@System' },
    { name = 'Impact', source = 'Impact:@System' },
    { name = 'Orbitron', source = 'Orbitron' },
    { name = 'Segoe UI', source = 'Segoe UI' },
    { name = 'Times New Roman', source = 'Times New Roman:@System' },
    { name = 'VCR OSD Mono', source = 'VCR OSD Mono' },
    { name = 'Webdings', source = 'Webdings:@System' },
  }
  for _, v in ipairs(io.scanDir(fontsDir, '*.ttf')) do
    table.insert(fonts, { name = v:sub(1, #v - 4), source = v:sub(1, #v - 4)..':'..__dirname..'/fonts' })
  end
  table.sort(fonts, function (a, b) return a.name < b.name end)
end

runtime.favoriteDecals = stringify.tryParse(config.favoriteDecals) or {}
runtime.recentDecals = stringify.tryParse(config.recentDecals) or {}
runtime.stickerSearch, runtime.favoritesOnly, runtime.recentOnly = '', false, false

local function selectDecal(tool, filename)
  tool.brush.brushTex = filename
  selectedBrushOutlineDirty = true
  for i = #runtime.recentDecals, 1, -1 do
    if runtime.recentDecals[i] == filename then table.remove(runtime.recentDecals, i) end
  end
  table.insert(runtime.recentDecals, 1, filename)
  while #runtime.recentDecals > 16 do table.remove(runtime.recentDecals) end
  config.recentDecals = stringify(runtime.recentDecals, true)
end

local tools = {
  {
    name = 'Brush (B)',
    key = shortcuts.toolBrush,
    icon = icons.Brush,
    ui = function (s)
      ui.header('Color:')
      ColorBlock()
      ui.offsetCursorY(20)
      ui.header('Brush:')
      BrushBlock(s.brush)
      BrushBaseBlock(s.brush, 0.5)
    end,
    brush = brushParams('brush'),
    brushColor = function(s) return rgbm.new(stored.color.rgb, s.brush.brushAlpha) end,
    brushSize = function (s) return vec2(s.brush.brushSize, s.brush.brushSize) end,
    -- blendMode = render.BlendMode.BlendAccurate,
  },
  {
    name = 'Eraser (E)',
    key = shortcuts.toolEraser,
    icon = icons.Eraser,
    ui = function (s)
      ui.header('Background color:')
      ColorBlock('bgColor')
      ui.offsetCursorY(20)
      ui.header('Eraser:')
      BrushBlock(s.brush)
      BrushBaseBlock(s.brush, 0.5)
    end,
    brush = brushParams('eraser'),
    brushColor = function(s) return stored.bgColor end,
    brushSize = function (s) return vec2(s.brush.brushSize, s.brush.brushSize) end,
  },
  {
    name = 'Stamp (S)',
    key = shortcuts.toolStamp,
    icon = icons.Stamp,
    ui = function (s)
      ui.header('Color:')
      ColorBlock()
      ui.offsetCursorY(20)

      ui.header('Stamp:')
      ui.combo('##set', string.format('Categoria: %s', selectedStickerSet.name), ui.ComboFlags.None, function ()
        for i = 1, #stickers do
          if ui.selectable(stickers[i].name, stickers[i] == selectedStickerSet) then
            selectedStickerSet = stickers[i]
            stored.selectedStickerSet = i
            config.stickerCategory = selectedStickerSet.name
            if #selectedStickerSet.items > 0 then selectDecal(s, selectedStickerSet.items[1][2])
            else s.brush.brushTex = '' end
          end
        end
        if ui.selectable('Nova categoria…') then
          ui.modalPrompt('Criar categoria', 'Nome da categoria:', '', function (value)
            if not Files.validName(value) then
              if value then ui.toast(ui.Icons.Warning, 'Nome inválido. Não use barras, pontos finais ou nomes reservados do Windows.') end
              return
            end
            if io.dirExists(decalsDir..'/'..value) or io.createDir(decalsDir..'/'..value) then
              ui.toast(ui.Icons.Confirm, 'Categoria pronta: '..value)
              rescanStickers()
              selectedStickerSet = table.findFirst(stickers, function (item) return item.name == value end)
              config.stickerCategory = value
              s.brush.brushTex = ''
            else
              ui.toast(ui.Icons.Warning, 'Couldn’t create a new category: '..tostring(value))
            end
          end)
        end
      end)

      runtime.stickerSearch = ui.inputText('Buscar adesivo', runtime.stickerSearch, ui.InputTextFlags.Placeholder)
      if ui.checkbox('Só favoritos', runtime.favoritesOnly) then runtime.favoritesOnly = not runtime.favoritesOnly end
      if ui.checkbox('Só recentes', runtime.recentOnly) then runtime.recentOnly = not runtime.recentOnly end
      local query, items = runtime.stickerSearch:lower(), {}
      local categories = (#query > 0 or runtime.favoritesOnly or runtime.recentOnly) and stickers or {selectedStickerSet}
      for _, category in ipairs(categories) do
        for _, item in ipairs(category.items) do
          if (#query == 0 or item[1]:lower():find(query, 1, true))
              and (not runtime.favoritesOnly or runtime.favoriteDecals[item[2]])
              and (not runtime.recentOnly or table.findFirst(runtime.recentDecals, function (v) return v == item[2] end)) then
            table.insert(items, item)
          end
        end
      end
      if s.brush.brushTex ~= '' and not io.fileExists(s.brush.brushTex) then s.brush.brushTex = '' end
      if s.brush.brushTex == '' and #items > 0 then selectDecal(s, items[1][2]) end
      if #items == 0 then ui.textWrapped('Nenhum adesivo encontrado. Importe um PNG pelo menu abaixo ou altere os filtros.') end
      ui.childWindow('stickersList', vec2(210, 210), false, ui.WindowFlags.AlwaysVerticalScrollbar, function ()
        ui.pushStyleColor(ui.StyleColor.Button, rgbm.colors.transparent)
        local itemSize = vec2(100, 60)
        for i = 1, #items do
          if ui.areaVisible(itemSize) then
            local size = ui.imageSize(items[i][2])
            if ui.button('##'..i, vec2(100, 60), s.brush.brushTex == items[i][2] and ui.ButtonFlags.Active or ui.ButtonFlags.None) then 
              selectDecal(s, items[i][2])
            end
            local s = vec2(90, size.x > 0 and 90 * size.y / size.x or 54)
            if s.y > 54 then s:scale(54 / s.y) end
            ui.addIcon(items[i][2], s, 0.5, nil, 0)
            if ui.itemHovered() then ui.setTooltip('Brush: '..items[i][1]) end
          else
            ui.dummy(itemSize)
          end
          if i % 2 == 1 then ui.sameLine(0, 0) end
        end
        ui.popStyleColor()
        ui.newLine()
      end)

      local _, i = table.findFirst(items, function (item, _, tex)
        return item[2] == tex
      end, s.brush.brushTex)
      i = i or 0

      if #items > 0 and shortcuts.arrowRight() then
        selectDecal(s, items[i % #items + 1][2])
      end

      if #items > 0 and shortcuts.arrowDown() then
        selectDecal(s, items[(i + 1) % #items + 1][2])
      end

      if #items > 0 and shortcuts.arrowLeft() then
        selectDecal(s, items[(i - 2 + #items) % #items + 1][2])
      end

      if #items > 0 and shortcuts.arrowUp() then
        selectDecal(s, items[(i - 3 + #items) % #items + 1][2])
      end

      if ui.itemHovered() then
        ui.setTooltip('Use arrow keys to quickly switch between items')
      end

      ui.itemPopup(function ()
        if ui.selectable('Adicionar adesivo PNG…') then
          if not io.dirExists(decalsDir..'/'..selectedStickerSet.name) then
            ui.toast(ui.Icons.Warning, 'Crie uma categoria antes de importar adesivos.')
            return
          end
          local category = selectedStickerSet.name
          chooseFile(false, {
            title = 'Adicionar adesivo PNG',
            folder = ac.getFolder(ac.FolderID.Root),
            fileTypes = { { name = 'Images', mask = '*.png' } },
            addAllFilesFileType = true,
            flags = bit.bor(os.DialogFlags.PathMustExist, os.DialogFlags.FileMustExist)
          }, function (filename)
            if Files.extension(filename) == 'png' and io.dirExists(decalsDir..'/'..category) then
              local fileName = filename:gsub('.+[/\\\\]', '')
              if io.copyFile(filename, decalsDir..'/'..category..'/'..fileName, true) then
                rescanStickers()
                selectedStickerSet = table.findFirst(stickers, function (item) return item.name == category end) or selectedStickerSet
                selectDecal(s, decalsDir..'/'..category..'/'..fileName)
                ui.toast(ui.Icons.Confirm, 'New decal added: '..fileName:sub(1, #fileName - 4))
                return
              end
            end
            ui.toast(ui.Icons.Warning, 'Não foi possível adicionar o PNG. Verifique o formato e se já existe um arquivo com este nome.')
          end)
        end
        if ui.selectable('Open in Explorer') then
          os.openInExplorer(decalsDir)
        end
        if ui.selectable('Refresh') then
          rescanStickers()
        end
      end)

      if s.brush.brushTex ~= '' then
        local favorite = runtime.favoriteDecals[s.brush.brushTex] == true
        if ui.checkbox('Favorito selecionado', favorite) then
          runtime.favoriteDecals[s.brush.brushTex] = not favorite or nil
          config.favoriteDecals = stringify(runtime.favoriteDecals, true)
        end
      end

      ui.alignTextToFramePadding()
      ui.text('Align sticker:')
      ui.sameLine()
      ui.setNextItemWidth(ui.availableSpaceX())
      stored.alignSticker = ui.combo('##alignSticker', stored.alignSticker, ui.ComboFlags.None, {
        'No',
        'Align to surface',
        'Fully align'
      })

      local brush = s.brush
      BrushBaseBlock(brush, 4, true)
    end,
    brush = brushParams('stamp', 0.2, 1),
    brushColor = function(s) return rgbm.new(stored.color.rgb, s.brush.brushAlpha) end,
    brushSize = function (s) 
      local size = ui.imageSize(s.brush.brushTex)
      return vec2(s.brush.brushSize, size.x > 0 and s.brush.brushSize * size.y / size.x or s.brush.brushSize)
    end,
    stickerMode = true,
    stickerContinious = false,
  },
  {
    name = 'Mirroring stamp (K)',
    key = shortcuts.toolMirroringStamp,
    icon = icons.MirroringStamp,
    carOnly = true,
    ui = function (s)
      ui.header('Mirroring stamp:')
      BrushBlock(s.brush)
      BrushBaseBlock(s.brush, 0.5, false, true, true)
    end,
    brush = brushParams('mirroringStamp'),
    procBrushTex = function (s, ray, previewMode)
      if not s._shot then
        s._shot = ac.GeometryShot(selectedMeshes, 256):setShadersType(render.ShadersType.SampleColor)
        s._ksAmbient = selectedMeshes:getMaterialPropertyValue('ksAmbient')
      end
      local up = getBrushUp(ray.dir, s)
      selectedMeshes:setMaterialTexture('txDiffuse', editingCanvas)
      selectedMeshes:setMaterialProperty('ksAmbient', 1)
      s._shot:clear(table.random(rgbm.colors))
      local lpos, ldir, lup = userCar.worldToLocal:transformPoint(ray.pos), userCar.worldToLocal:transformVector(ray.dir), userCar.worldToLocal:transformVector(up)
      reflectBrush(lpos, ldir, lup)
      local ipos, idir, iup = userCar.bodyTransform:transformPoint(lpos), userCar.bodyTransform:transformVector(ldir), userCar.bodyTransform:transformVector(lup)
      local brushSize = previewMode and s.brush.brushSize or s.brush.brushSize * brushSizeMult(s.brush)
      s._shot:setOrthogonalParams(vec2(brushSize, brushSize), 100):update(ipos, idir, iup, 0)
      selectedMeshes:setMaterialTexture('txDiffuse', aoCanvas)
      selectedMeshes:setMaterialProperty('ksAmbient', s._ksAmbient)
      -- DebugTex = s._shot
      return s._shot
    end,
    procProjParams = function (s, pr)
      pr.mask2 = s.brush.brushTex
      pr.mask2Flags = render.TextureMaskFlags.UseAlpha
    end,
    brushColor = function(s) return rgbm(1, 1, 1, s.brush.brushAlpha) end,
    brushSize = function (s) return vec2(-s.brush.brushSize, s.brush.brushSize) end,
    stickerMode = true,
    stickerNoAlignment = true,
    stickerContinious = true
  },
  {
    name = 'Blur/Smudge (Alt+B)',
    key = shortcuts.toolBlurTool,
    icon = icons.BlurTool,
    ui = function (s)
      ui.header('Blur tool:')
      BrushBlock(s.brush)
      BrushBaseBlock(s.brush, 0.5, false, true, true)
      
      s.brush.blur = ui.slider('##blur', s.brush.blur * 1000, 0, 100, 'Blur: %.0f%%') / 1000
      s.brush.smudge = ui.slider('##smudge', s.brush.smudge * 100, 0, 100, 'Smudge: %.0f%%', 0.5) / 100

      ui.offsetCursorY(20)
      ui.header('Sharpness boost:')
      if ui.checkbox('Active', s.brush.sharpnessMode) then
        s.brush.sharpnessMode = not s.brush.sharpnessMode
      end
      s.brush.sharpness = ui.slider('##sharpness', s.brush.sharpness * 100, 0, 500, 'Intensity: %.0f%%', 2) / 100
      ui.textWrapped('Sharpness boost is some sort of an inverse to blur. Might help to increase local sharpness a bit or, with less well tuned settings, achieve some other strange effects.')
    end,
    brush = brushParams('blurTool', nil, nil, { blur = 0.01, smudge = 0, sharpnessMode = false, sharpness = 1.5 }),
    procBrushTex = function (s, ray, previewMode)
      if not s._shot then
        s._shot = ac.GeometryShot(selectedMeshes, 256):setShadersType(render.ShadersType.SampleColor)
        s._shotBlurred = ui.ExtraCanvas(vec2(128, 128))
        s._shotSharpened = ui.ExtraCanvas(vec2(128, 128))
        s._ksAmbient = selectedMeshes:getMaterialPropertyValue('ksAmbient')
      end
      if previewMode or not s._rayPos then
        s._rayPos = ray.pos:clone()
        s._rayDir = ray.dir:clone()
        if previewMode then return end
      else
        s._rayPos = math.applyLag(s._rayPos, ray.pos, s.brush.smudge, ac.getDeltaT())
        s._rayDir = math.applyLag(s._rayDir, ray.dir, s.brush.smudge, ac.getDeltaT()):normalize()
      end
      local up = getBrushUp(s._rayDir, s)
      selectedMeshes:setMaterialTexture('txDiffuse', editingCanvas)
      selectedMeshes:setMaterialProperty('ksAmbient', 1)
      s._shot:clear(table.random(rgbm.colors))
      local brushSize = s.brush.brushSize * brushSizeMult(s.brush)
      s._shot:setOrthogonalParams(vec2(brushSize, brushSize), 100):update(s._rayPos, s._rayDir, up, 0)
      selectedMeshes:setMaterialTexture('txDiffuse', aoCanvas)
      selectedMeshes:setMaterialProperty('ksAmbient', s._ksAmbient)
      if s.brush.blur <= 0.0001 then
        return s._shot
      end
      s._shotBlurred:clear(rgbm.colors.transparent):update(function (dt)
        ui.beginBlurring()
        ui.drawImage(s._shot, 0, 128)
        ui.endBlurring(s.brush.blur)
      end)
      if s.brush.sharpnessMode then
        s._shotSharpened:update(function (dt)
          ui.renderShader({
            p1 = vec2(0, 0),
            p2 = vec2(128, 128),
            blendMode = render.BlendMode.Opaque,
            textures = {
              txBlurred = s._shotBlurred,
              txBase = s._shot
            },
            values = {
              gIntensity = tonumber(s.brush.sharpness)
            },
            shader = [[float4 main(PS_IN pin) {
              float4 r = lerp(txBlurred.Sample(samLinear, pin.Tex), txBase.Sample(samLinear, pin.Tex), gIntensity);
              r.a = 1;
              return r;
            }]]
          })
        end)
        return s._shotSharpened
      end
      return s._shotBlurred
    end,
    procProjParams = function (s, pr)
      pr.mask2 = s.brush.brushTex
      pr.mask2Flags = render.TextureMaskFlags.UseAlpha
    end,
    brushColor = function(s) return rgbm(1, 1, 1, s.brush.brushAlpha) end,
    brushSize = function (s) return vec2(s.brush.brushSize, s.brush.brushSize) end,
    stickerMode = true,
    stickerNoAlignment = true,
    stickerContinious = true
  },
  {
    name = 'Text (T)',
    key = shortcuts.toolText,
    icon = icons.Text,
    ui = function (s)
      if fonts == nil then
        rescanFonts()
      end

      local selectedFont = table.findFirst(fonts, function (item, _, sf) return item.source == sf end, stored.selectedFont)
      if selectedFont == nil then
        selectedFont = fonts[1]
        stored.selectedFont = selectedFont.source
      end

      ui.header('Color:')
      ColorBlock()
      ui.offsetCursorY(20)

      ui.beginGroup()
      ui.header('Text:')
      s._labelText = ui.inputText('Text', s._labelText, ui.InputTextFlags.Placeholder)
      if ui.itemEdited() then s._labelDirty = true end

      ui.combo('##fonts', 'Font: '..tostring(selectedFont.name), ui.ComboFlags.None, function ()
        for i = 1, #fonts do
          if ui.selectable(fonts[i].name, fonts[i] == selectedFont) then
            selectedFont = fonts[i]
            stored.selectedFont, s._labelDirty = selectedFont.source, true
          end

          if ui.itemHovered() then
            ui.tooltip(function ()
              if s._previewCanvas ~= nil then
                s._previewCanvas:dispose()
              end
              
              local font = fonts[i].source
              if stored.fontBold then font = font..';Weight=Bold' end
              if stored.fontItalic then font = font..';Style=Italic' end
              ui.pushDWriteFont(font)
              local canvasSize = ui.measureDWriteText(s._labelText, 24)
              canvasSize.x, canvasSize.y = math.max(canvasSize.x, 24), canvasSize.y + 8
              s._previewCanvas = ui.ExtraCanvas(canvasSize):clear(rgbm.colors.transparent):update(function (dt)
                ui.dwriteTextAligned(s._labelText, 24, ui.Alignment.Center, ui.Alignment.Center, ui.availableSpace(), false, rgbm.colors.white)
              end)
              ui.popDWriteFont()
              ui.image(s._previewCanvas, canvasSize)
            end)
          end
        end
      end)
      ui.itemPopup(function ()
        if ui.selectable('Open in Explorer') then
          os.openInExplorer(fontsDir)
        end
        if ui.selectable('Refresh') then
          rescanFonts()
        end
      end)
      
      if ui.checkbox('Bold', stored.fontBold) then stored.fontBold, s._labelDirty = not stored.fontBold, true end
      if ui.checkbox('Italic', stored.fontItalic) then stored.fontItalic, s._labelDirty = not stored.fontItalic, true end
      ui.endGroup()

      if ui.itemHovered() and not s._labelDirty then
        ui.tooltip(function ()
          ui.image(s.brush.brushTex, ui.imageSize(s.brush.brushTex):scale(0.5))
        end)
      end

      -- local size = ui.imageSize(s.brush.brushTex)
      -- ui.drawImage(s.brush.brushTex, ui.getCursor(), ui.getCursor() + vec2(210, 210 * size.y / size.x))
      -- ui.offsetCursorY(math.ceil(210 * size.y / size.x / 20 + 0.5) * 20)

      ui.alignTextToFramePadding()
      ui.text('Align text:')
      ui.sameLine()
      ui.setNextItemWidth(ui.availableSpaceX())
      stored.alignSticker = ui.combo('##alignSticker', stored.alignSticker, ui.ComboFlags.None, {
        'No',
        'Align to surface',
        'Fully align'
      })

      local brush = s.brush
      BrushBaseBlock(brush, 4, true)
      
      if s._labelDirty then
        if s.brush.brushTex and type(s.brush.brushTex) ~= 'string' then
          s.brush.brushTex:dispose()
        end
        local font = selectedFont.source
        if stored.fontBold then font = font..';Weight=Bold' end
        if stored.fontItalic then font = font..';Style=Italic' end
        ui.pushDWriteFont(font)
        local canvasSize = ui.measureDWriteText(s._labelText, 48)
        canvasSize.x, canvasSize.y = math.max(canvasSize.x, 48), canvasSize.y + 16
        s.brush.brushTex = ui.ExtraCanvas(canvasSize):clear(rgbm.colors.transparent):update(function (dt)
          ui.dwriteTextAligned(s._labelText, 48, ui.Alignment.Center, ui.Alignment.Center, ui.availableSpace(), false, rgbm.colors.white)
        end)
        ui.popDWriteFont()
        s._labelDirty = false
      end
    end,
    brush = brushParams('text', 0.2, 1),
    brushColor = function(s) return rgbm.new(stored.color.rgb, s.brush.brushAlpha) end,
    brushSize = function (s) 
      local size = ui.imageSize(s.brush.brushTex)
      return vec2(s.brush.brushSize, size.x > 0 and s.brush.brushSize * size.y / size.x or s.brush.brushSize)
    end,
    stickerMode = true,
    stickerContinious = false,
    blendMode = render.BlendMode.BlendPremultiplied,
    _labelText = ac.getDriverName(0),
    _labelDirty = true
  },
  {
    name = 'Masking (M)',
    key = shortcuts.toolMasking,
    icon = icons.Masking,
    carOnly = true,
    ui = function (s)
      -- if not maskingCarView then
      --   maskingCarView = ac.GeometryShot(selectedMeshes, vec2(210, 130)):setClippingPlanes(100, 1e5)
      --   selectedMeshes:setMaterialTexture('txDiffuse', maskingCanvas)
      --   maskingCarView:update(car.position + car.side * 1000, -car.side, car.up, 0.15)
      --   selectedMeshes:setMaterialTexture('txDiffuse', aoCanvas)
      -- end
      -- ui.drawImage(maskingCarView, ui.getCursor(), ui.getCursor() + vec2(210, 130))

      if ui.checkbox('Masking is active', maskingActive) then
        maskingActive = not maskingActive
      end
      if ui.itemHovered() then
        ui.setTooltip('Toggle masking (Ctrl+M)')
      end

      -- ui.textWrapped('Masking tool is a plane separating model in two halves. When you draw a thing, it would only get drawn on the side of a plane with camera. Might help in masking things quickly. For something more complex, use stencils.\n\nClick model and drag mouse to quickly create a new plane.')
      ui.textWrapped('Masking tool is a plane separating model in two halves. When you draw a thing, it would only get drawn on the side of a plane with camera. Might help in masking things quickly.\n\nClick model and drag mouse to quickly create a new plane.\n\nPro tip: when using brush, hold M for more than 0.2 seconds: tool will switch to masking temporary, so you can quickly put a mask and go back to brush by releasing M.')
    end,
    action = function (s)
      local ray = render.createMouseRay()
      local d = selectedMeshes:raycast(ray)
      if d ~= -1 then s._d = d end
      if d ~= -1 and uiState.isMouseLeftKeyClicked then
        maskingCreatingFrom = userCar.worldToLocal:transformPoint(ray.pos + ray.dir * d)
        s._moving = false
      elseif maskingCreatingFrom then
        if not uiState.isMouseLeftKeyDown then
          if s._moving then
            local endingPos = userCar.worldToLocal:transformPoint(ray.pos + ray.dir * d)
            applyQuickMasking(maskingCreatingFrom, endingPos)
            s._moving = false
          end
          maskingCreatingFrom, maskingCreatingTo = nil, nil
        end
        if not s._moving and #ui.mouseDragDelta() > 0 then
          addUndo(maskingBackup())
          s._moving = true
          maskingActive = true
        end
        if s._moving then
          maskingCreatingTo = userCar.worldToLocal:transformPoint(ray.pos + ray.dir * s._d)
        end
      end
    end,
  },
  {
    name = 'Eyedropper (I)',
    key = shortcuts.toolEyeDropper,
    icon = icons.EyeDropper,
    ui = function (s)
      ui.header('Color:')
      ColorBlock()
      ui.offsetCursorY(20)

      ui.header('Eyedropper:')
      ui.alignTextToFramePadding()
      ui.text('Sample size:')
      ui.sameLine()
      ui.setNextItemWidth(ui.availableSpaceX())
      stored.eyeDropperRange = ui.combo('##sampleSize', stored.eyeDropperRange, ui.ComboFlags.None, {
        'Point sample',
        '3 by 3 average',
        '5 by 5 average',
        '7 by 7 average',
        '9 by 9 average',
      })
      if s._color and not ui.mouseBusy() then
        ColorTooltip(s._color)
        if uiState.isMouseLeftKeyDown then
          stored.color = s._color
          s._changing = true
        elseif s._changing then
          s._changing = false
          palette.addToUserPalette(s._color)
        end
      end
    end,
    action = function (s)
      if accessibleData ~= nil then
        local ray = render.createMouseRay()
        local uv = vec2()
        if selectedMeshes:raycast(ray, false, nil, nil, uv) ~= -1 then
          uv.x = uv.x - math.floor(uv.x)
          uv.y = uv.y - math.floor(uv.y)
          local c = uv * accessibleData:size()
          local range = 1 + (stored.eyeDropperRange - 1) * 2
          local offset = -math.ceil(range / 2)
          local cx, cy = math.floor(c.x) + offset, math.floor(c.y) + offset
          local colorPick = rgbm()
          s._color:set(colorPick)
          for x = 1, range do
            for y = 1, range do
              s._color:add(accessibleData:colorTo(colorPick, cx + x, cy + y))
            end
          end
          s._color:scale(1 / (range * range))
        end
      end
    end,
    _color = rgbm(1, 1, 1, 1),
    _changing = false
  }
}

runtime.disposeTools = function ()
  for _, tool in ipairs(tools) do
    for _, key in ipairs({'_shot', '_shotBlurred', '_shotSharpened', '_previewCanvas'}) do
      disposeResource(tool[key])
      tool[key] = nil
    end
    tool._ksAmbient, tool._rayPos, tool._rayDir, tool.__brushRandomAngle = nil, nil, nil, nil
    tool._moving, tool._changing = false, false
    if tool._labelText then
      if type(tool.brush.brushTex) ~= 'string' then disposeResource(tool.brush.brushTex) end
      tool.brush.brushTex, tool._labelDirty = '', true
    end
  end
end

stored.activeToolIndex = math.clamp(math.floor(stored.activeToolIndex), 1, #tools)
local activeTool = tools[stored.activeToolIndex]
local previousToolIndex = stored.activeToolIndex
local toolSwitched = 0
runtime.resetToolState = function ()
  toolSwitched = 0
  previousToolIndex = stored.activeToolIndex
  activeTool = tools[stored.activeToolIndex]
end

local function LayersControl()
  local busy = drawing or runtime.dialog or runtime.saving or runtime.recoverySaving
  ui.header('Camadas:')
  if ui.button('+ Nova', vec2(66, 0), busy and ui.ButtonFlags.Disabled or ui.ButtonFlags.None) then addBlankLayer() end
  ui.sameLine(0, 4)
  if ui.button('Duplicar', vec2(68, 0), busy and ui.ButtonFlags.Disabled or ui.ButtonFlags.None) then duplicateActiveLayer() end
  ui.sameLine(0, 4)
  if ui.button('Excluir', vec2(64, 0), (busy or #layers <= 1) and ui.ButtonFlags.Disabled or ui.ButtonFlags.None) then
    local session, layerID = runtime.session, activeLayer() and activeLayer().id
    ui.modalPopup('Excluir camada?', 'Esta operação remove a camada ativa e limpa o histórico de pixels.', function (ok)
      if ok and session == runtime.session and activeLayer() and activeLayer().id == layerID then deleteActiveLayer() end
    end)
  end

  ui.childWindow('layersList', vec2(210, math.min(142, math.max(48, #layers * 25))), false, ui.WindowFlags.None, function ()
    for index = #layers, 1, -1 do
      local layer = layers[index]
      ui.pushID('layer'..layer.id)
      if ui.checkbox('##visible', layer.visible) and not busy then
        layer.visible = not layer.visible
        markLayerStructureChanged()
      end
      if ui.itemHovered() then ui.setTooltip(layer.visible and 'Ocultar camada' or 'Mostrar camada') end
      ui.sameLine(0, 4)
      if ui.selectable(layer.name..'##select', activeLayerIndex == index) and not busy then activeLayerIndex = index end
      ui.popID()
    end
  end)

  local layer = activeLayer()
  if not layer then return end
  local newName = ui.inputText('##layerName', layer.name, ui.InputTextFlags.None)
  newName = tostring(newName or ''):gsub('^%s+', ''):gsub('%s+$', ''):gsub('[%c]', ' '):sub(1, 80)
  if not busy and #newName > 0 and newName ~= layer.name then
    layer.name = newName
    history:push(nil)
  end
  local opacity = ui.slider('##layerOpacity', layer.opacity * 100, 0, 100, 'Opacidade: %.0f%%') / 100
  if not busy and math.abs(opacity - layer.opacity) > 0.0001 then
    layer.opacity = opacity
    markLayerStructureChanged()
  end
  if ui.button('Baixo', vec2(66, 0), (busy or activeLayerIndex == 1) and ui.ButtonFlags.Disabled or ui.ButtonFlags.None) then moveActiveLayer(-1) end
  ui.sameLine(0, 4)
  if ui.button('Cima', vec2(66, 0), (busy or activeLayerIndex == #layers) and ui.ButtonFlags.Disabled or ui.ButtonFlags.None) then moveActiveLayer(1) end
  ui.sameLine(0, 4)
  ui.text(string.format('%d/%d', activeLayerIndex, #layers))
  if not layer.visible then ui.textWrapped('A camada ativa está oculta; torne-a visível para acompanhar a pintura.') end
end

local function SkinEditor()
  DrawControl()
  if selectedMeshes == nil then return end
  if trackMode and activeTool.carOnly then activeTool = tools[1]; stored.activeToolIndex = 1 end
  ui.text(string.format('%d×%d | Undo %d | Redo %d', config.resolution, config.resolution, #undoStack, #redoStack))
  ui.text(string.format('Histórico: %.0f / %d MB', history:memoryFootprint() / (1024 * 1024), config.historyMB))
  ui.text(string.format('Camadas + composição: %.0f MB', layerMemoryFootprint() / (1024 * 1024)))
  LayersControl()
  ui.offsetCursorY(20)

  ui.header('Tools:')
  for i = 1, #tools do
    local v = tools[i]
    if not v.carOnly or not trackMode then
      local s = activeTool == v and toolSwitched ~= 0 and ui.time() > toolSwitched + 0.2
      local bg = s and rgbm(0.5, 0.5, 0, 1) or activeTool == v and uiState.accentColor * rgbm(1, 1, 1, 0.5)
      if bg then ui.pushStyleColor(ui.StyleColor.Button, bg) end
      if IconButton(v.icon, v.name, activeTool == v, not drawing and not runtime.dialog) or not drawing and v.key and v.key(false) then
        activeTool = v
        toolSwitched = v.key and tonumber(ui.time()) or 0
        previousToolIndex = stored.activeToolIndex
        stored.activeToolIndex = i
        selectedBrushOutlineDirty = true
      end
      if bg then ui.popStyleColor() end
      ui.sameLine(0, 4)
      if ui.availableSpaceX() < 12 then ui.newLine(4) end
    end
  end
  if not trackMode then
    if IconButton(icons.Camera, 'Câmera orbital (Ctrl+Space)\nEspaço ou botão central: girar. Botão direito: pan.\nCtrl+Shift+roda: zoom.', stored.orbitCamera) or shortcuts.toggleOrbitCamera() then
      stored.orbitCamera = not stored.orbitCamera
    end
    ui.sameLine(0, 4)
    if ui.availableSpaceX() < 32 then ui.newLine(4) end
    if IconButton(icons.MirroringHelper, 'Project other side (Ctrl+E)\nProject other side on current side to make making things symmetrical easier', stored.projectOtherSide) or shortcuts.toggleProjectOtherSide() then
      stored.projectOtherSide = not stored.projectOtherSide
    end
    if stored.orbitCamera then
      if sim.isWindowForeground and not ui.mouseBusy() and not runtime.dialog and uiState.ctrlDown and uiState.shiftDown then
        config.cameraDistance = math.clamp(config.cameraDistance * math.exp(-ui.mouseWheel() * 0.12), 1, 20)
      end
      config.cameraDistance = ui.slider('##cameraDistance', config.cameraDistance, 1, 20, 'Distância: %.1f m', 2)
      config.cameraFOV = ui.slider('##cameraFOV', config.cameraFOV, 10, 70, 'FOV: %.0f°')
      if ui.button('Resetar câmera', vec2(210, 0)) then
        cameraAngle:set(-2.6, 0.1)
        cameraPan:set(0, 0)
        config.cameraDistance, config.cameraFOV = 8, 24
      end
    end
    config.mirrorAxis = ui.combo('##mirrorAxis', config.mirrorAxis, ui.ComboFlags.None, {'Simetria X (lados)', 'Simetria Y (altura)', 'Simetria Z (frente/trás)'})
    config.mirrorOffset = ui.slider('##mirrorOffset', config.mirrorOffset, -2, 2, 'Eixo da simetria: %.2f m')
  end

  ui.offsetCursorY(20)

  if toolSwitched ~= 0 and not activeTool.key:down() then
    if ui.time() > toolSwitched + 0.2 then
      activeTool = tools[previousToolIndex]
      toolSwitched = 0
      stored.activeToolIndex = previousToolIndex
      selectedBrushOutlineDirty = true
    else
      toolSwitched = 0
    end
  end

  if not trackMode and shortcuts.toggleMasking() then
    maskingActive = not maskingActive
  end

  ui.pushID(activeTool.name)
  ui.pushFont(ui.Font.Small)
  activeTool:ui()
  ui.popFont()
  ui.popID()
end

local pdistance, pnormal, pdir = 1, vec3(), vec3(1, 0, 0)
runtime.resetProjection = function ()
  pdistance = 1
  pnormal:set(0, 0, 0)
  pdir:set(1, 0, 0)
end

local function projectBrushTexture(tex, pos, dir, color, distance, previewMode, doNotUseToolProjParams)
  local brush = activeTool.brush
  if not brush or brush.brushTex == '' then return end

  if activeTool.stickerMode and not activeTool.stickerNoAlignment and stored.alignSticker > 1 then
    if type(pos) == 'table' then return end
    local d, m = selectedMeshes:raycast(render.createRay(pos, dir), true, nil, pnormal)
    if d ~= -1 then
      pdir = m:getWorldTransformationRaw():transformVector(pnormal):scale(-1)
      pdistance = d
    else
      d = pdistance
    end
    pos = pos + dir * d
    dir = pdir:clone()
    if stored.alignSticker == 3 then
      dir = dir - userCar.up * dir:dot(userCar.up)
    end
    distance = 0.2
  end

  local size = activeTool:brushSize()
  if not previewMode and (not activeTool.stickerMode or activeTool.stickerContinious) then size = size * brushSizeMult(brush) end
  if brush.brushAspectMult > 1 then size.x = size.x * brush.brushAspectMult
  else size.y = size.y / brush.brushAspectMult end
  if brush.brushMirror then
    size.x = -size.x
  end
  if not brush.brushRandomizedAngle or previewMode then
    activeTool.__brushRandomAngle = activeTool.brush.brushAngle
  else
    activeTool.__brushRandomAngle = math.random() * 360
  end
  local pr = {
    filename = tex,
    color = color,
    size = size,
    depth =  brush.paintThrough and 1e9 or distance,
    doubleSided = brush.paintThrough,
    mask1 = maskingCanvas,
    mask1Flags = bit.bor(render.TextureMaskFlags.AltUV, render.TextureMaskFlags.Default),
    blendMode = not previewMode and activeTool.blendMode or nil
  }
  local originalWidth = size.x
  if activeTool.procProjParams and not doNotUseToolProjParams then activeTool:procProjParams(pr) end
  if type(pos) == 'table' then
    for i = 1, #pos do
      pr.size.x = originalWidth
      pr.pos = pos[i][1]
      pr.look = pos[i][2]
      if not brush.paintThrough then
        pr.depth = pos[i][3]
      end
      pr.up = getBrushUp(pos[i][2], activeTool)
      selectedMeshes:projectTexture(pr)
      if brush.withMirror and not trackMode then
        local lpos, ldir, lup = userCar.worldToLocal:transformPoint(pr.pos), userCar.worldToLocal:transformVector(pr.look), userCar.worldToLocal:transformVector(pr.up)
        reflectBrush(lpos, ldir, lup)
        pr.pos, pr.look, pr.up = userCar.bodyTransform:transformPoint(lpos), userCar.bodyTransform:transformVector(ldir), userCar.bodyTransform:transformVector(lup)
        pr.size.x = -originalWidth
        selectedMeshes:projectTexture(pr)
      end
    end
  else
    pr.pos = pos
    pr.look = dir
    pr.up = getBrushUp(dir, activeTool)
    selectedMeshes:projectTexture(pr)
    if brush.withMirror and not trackMode then
      local lpos, ldir, lup = userCar.worldToLocal:transformPoint(pr.pos), userCar.worldToLocal:transformVector(pr.look), userCar.worldToLocal:transformVector(pr.up)
      reflectBrush(lpos, ldir, lup)
      pr.pos, pr.look, pr.up = userCar.bodyTransform:transformPoint(lpos), userCar.bodyTransform:transformVector(ldir), userCar.bodyTransform:transformVector(lup)
      pr.size.x = -pr.size.x
      selectedMeshes:projectTexture(pr)
    end
  end
  ac.refreshCarColor(0)
end

local function updateBrushOutline(stickerMode)
  if not selectedBrushOutline then
    selectedBrushOutline = ui.ExtraCanvas(vec2(128, 128), 4)
  end
  selectedBrushOutlineDirty = false
  if not activeTool.brush or stickerMode then
    selectedBrushOutline:clear(rgbm.colors.transparent)
    return
  end
  -- prepare brush outline in two stages: first, boost alpha and draw brush in white and draw it
  -- again in black and smaller to get a black and white mask, and then draw that mask with different
  -- shading params to turn black and white mask into transparency
  selectedBrushOutline:clear(rgbm.colors.black)
  selectedBrushOutline:update(function (dt)
    ui.renderShader({
      p1 = vec2(0, 0),
      p2 = vec2(128, 128),
      blendMode = render.BlendMode.Opaque,
      textures = {
        txBrush = activeTool.brush.brushTex
      },
      values = {
        gMargin = (0.5/128) / activeTool.brush.brushSize
      },
      shader = [[float4 main(PS_IN pin) {
        float tx = txBrush.Sample(samLinearBorder0, pin.Tex + float2(gMargin, gMargin)).w
          + txBrush.Sample(samLinearBorder0, pin.Tex + float2(gMargin, -gMargin)).w
          + txBrush.Sample(samLinearBorder0, pin.Tex + float2(-gMargin, gMargin)).w
          + txBrush.Sample(samLinearBorder0, pin.Tex + float2(-gMargin, -gMargin)).w;
        tx = saturate(tx * 20 - 1);
        tx *= 1 - saturate(txBrush.Sample(samLinear, pin.Tex).w * 20 - 1);
        return float4(1, 1, 1, tx);
      }]]
    })
  end)
end

local function updateAOCanvas()
  if aoCanvas == nil then return end
  if not drawing and runtime.lastPreviewTime and ui.time() - runtime.lastPreviewTime < 1 / config.previewFPS then return end
  runtime.lastPreviewTime = ui.time()

  local projectDir
  if stored.projectOtherSide and not trackMode then
    if not otherSideShot then
      bakKsAmbient = selectedMeshes:getMaterialPropertyValue('ksAmbient')
      otherSideShot = ac.GeometryShot(selectedMeshes, config.resolution):setOrthogonalParams(vec2(6, 4), 10):setClippingPlanes(-10, 0):setShadersType(render.ShadersType.SampleColor)
    end

    projectDir = userCar.side
    local s = math.sign(projectDir:dot(ac.getCameraForward()))
    if s > 0 then projectDir = -projectDir end
    if s ~= otherSideSide then otherSidePhase, otherSideSide = -1, s end

    if otherSidePhase ~= editingCanvasPhase then
      otherSidePhase = editingCanvasPhase
      selectedMeshes:setMaterialTexture('txDiffuse', editingCanvas)
      selectedMeshes:setMaterialProperty('ksAmbient', 1)
      otherSideShot:update(userCar.position, projectDir, userCar.up, 0)
      selectedMeshes:setMaterialTexture('txDiffuse', aoCanvas)
      selectedMeshes:setMaterialProperty('ksAmbient', bakKsAmbient)
    end
  end

  local ray, tex
  ray = render.createMouseRay()
  if activeTool.stickerMode then
    if activeTool.procBrushTex then tex = activeTool:procBrushTex(ray, true)
    else tex = activeTool.brush.brushTex end
  end

  if selectedBrushOutlineDirty then
    updateBrushOutline(activeTool.stickerMode and tex ~= nil)
  end
  
  aoCanvas:update(function (dt)
    drawWithAO(editingCanvas, aoTexture or carTexture)

    if stored.projectOtherSide and not trackMode then
      selectedMeshes:projectTexture({
        filename = otherSideShot,
        pos = userCar.position,
        look = -projectDir,
        up = userCar.up,
        color = rgbm(1, 1, 1, 0.1),
        size = vec2(-6, 4),
        depth = 1e9,
        doubleSided = false
      })
    end

    if tex then
      projectBrushTexture(tex, ray.pos, ray.dir, activeTool:brushColor() * rgbm(1, 1, 1, 0.3), nil, true)
    else
      projectBrushTexture(selectedBrushOutline, ray.pos, ray.dir, rgbm.colors.gray, nil, true, activeTool.stickerMode)
    end
  end)
end

local function updateMaskingCanvas()
  if not maskingActive or trackMode then
    if maskingCanvas and maskingDirty then
      maskingDirty = false
      maskingCanvas:clear(rgbm.colors.white)
    end
    return
  end

  if not maskingCanvas then
    maskingCanvas = ui.ExtraCanvas(vec2(config.resolution, config.resolution))
  end

  maskingDirty = true
  maskingCanvas:clear(rgbm.colors.black)
  maskingCanvas:update(function (dt)
    local mdir = maskingDir
    if mdir:dot(userCar.worldToLocal:transformPoint(ac.getCameraPosition()) - maskingPos) < 0 then mdir = mdir:clone():scale(-1) end
    local pos = maskingPos + mdir * 5
    local dir = math.cross(mdir, vec3(0, 0, 1))
    selectedMeshes:projectTexture({
      filename = 'color::#ffffff',
      pos = userCar.bodyTransform:transformPoint(pos),
      look = userCar.bodyTransform:transformVector(dir),
      up = userCar.bodyTransform:transformVector(mdir),
      color = rgbm.colors.white,
      size = vec2(10, 10),
      depth = 1e9,
      doubleSided = true
    })
  end)
end

local function cameraUpdate()
  if editingCanvas == nil then
    editingCanvas = ui.ExtraCanvas(vec2(config.resolution, config.resolution)):clear(rgbm(0, 0, 0, 0))
    resetToBaseLayer()
    aoCanvas = ui.ExtraCanvas(vec2(config.resolution, config.resolution), 4, render.AntialiasingMode.CMAA)
    selectedMeshes:setMaterialTexture('txDiffuse', aoCanvas)
    local object = trackMode and 'track' or ac.getCarID(0)
    local skin = trackMode and (ac.getTrackID()..'-'..ac.getTrackLayout()) or ac.getCarSkinID(0)
    autosaveDir = autosaveRoot..'/'..Files.pathKey(object)..'/'..Files.pathKey(skin)..'/'..Files.pathKey(io.getFileName(carTexture))
    autosavePhase, autosaveTime = -1, ui.time()
    updateAccessibleData()
    offerRecoveryDraft()
  end

  runtime.cameraNavigating = false
  if trackMode then return end

  if camera then
    local mat = mat4x4.rotation(cameraAngle.y, vec3(1, 0, 0)):mul(mat4x4.rotation(cameraAngle.x, vec3(0, 1, 0))):mul(userCar.bodyTransform)
    camera.transform.position = mat:transformPoint(vec3(cameraPan.x, cameraPan.y + userCar.aabbCenter.y * math.smoothstep(math.lerpInvSat(cameraAngle.y, 0.5, 0)), -config.cameraDistance))
    camera.transform.look = mat:transformVector(vec3(0, 0, 1))
    camera.transform.up = mat:transformVector(vec3(0, 1, 0))
    camera.fov = config.cameraFOV

    camera.ownShare = math.applyLag(camera.ownShare, stored.orbitCamera and 1 or 0, 0.85, ac.getDeltaT())
    if stored.orbitCamera and sim.isWindowForeground and not uiState.wantCaptureMouse and not runtime.dialog then
      local rotating = (not uiState.wantCaptureKeyboard and ui.keyboardButtonDown(ui.KeyIndex.Space)) or uiState.isMouseMiddleKeyDown
      local panning = uiState.isMouseRightKeyDown
      runtime.cameraNavigating = rotating or panning
      if rotating then
        cameraAngle:add(uiState.mouseDelta * vec2(-0.003, 0.003))
        cameraAngle.y = math.clamp(cameraAngle.y, -1.45, 1.45)
      elseif panning then
        cameraPan:add(uiState.mouseDelta * vec2(-0.0015, 0.0015) * config.cameraDistance)
        cameraPan.x, cameraPan.y = math.clamp(cameraPan.x, -5, 5), math.clamp(cameraPan.y, -5, 5)
      end
    end
    if not stored.orbitCamera and camera.ownShare < 0.001 then
      camera:dispose()
      camera = nil
    end
  elseif stored.orbitCamera then
    camera = ac.grabCamera('Paintshop')
    if camera then camera.ownShare = 0 end
  end
end

local smoothRayDir

local function paintUpdate()
  if not editingCanvas or not selectedMeshes then return end
  local paintLayer = activeLayer()
  if not paintLayer then return end
  if not sim.isWindowForeground or runtime.cameraNavigating or runtime.dialog or runtime.saving then
    if drawing then
      updateAccessibleData()
      selectedMeshes:setMotionStencil(taaFix.Off)
      drawing = false
    end
    ignoreMousePress = true
    return
  end
  if activeTool.brush then
    if activeTool.brush.brushTex == '' then updateAOCanvas(); return end
    if uiState.isMouseLeftKeyDown then
      if drawing then
        local ray = render.createMouseRay()
        local brush = activeTool.brush
        local tex = activeTool.procBrushTex and activeTool:procBrushTex(ray, false) or brush.brushTex
        paintLayer.canvas:update(function ()
          local lastBrushDistance = brushDistance
          local hitDistance = selectedMeshes:raycast(ray)
          if hitDistance ~= -1 then brushDistance = hitDistance end
          if activeTool.stickerMode then
            projectBrushTexture(tex, ray.pos, ray.dir, activeTool:brushColor(), brushDistance)
            if not activeTool.stickerContinious then
              refreshCanvasLater() -- projection happens a bit later
              drawing = false
              selectedMeshes:setMotionStencil(taaFix.Off)
              ignoreMousePress = true
            end
            return
          elseif lastRay then
            local color = activeTool:brushColor()

            if brush.smoothing > 0 then
              smoothRayDir = math.applyLag(smoothRayDir, ray.dir, brush.smoothing ^ 0.3 * 0.9, 0.02)
              ray.dir:set(smoothRayDir)
            end

            local distance = ray.pos:clone():addScaled(ray.dir, brushDistance):distance(lastRay.pos:clone():addScaled(lastRay.dir, lastBrushDistance))
            if distance > brush.brushStepSize then
              local steps = math.min(config.maxSteps, math.floor(0.5 + distance / brush.brushStepSize))
              local list = {}
              for i = 1, steps do
                list[i] = {math.lerp(lastRay.pos, ray.pos, i / steps), math.lerp(lastRay.dir, ray.dir, i / steps), math.lerp(lastBrushDistance, brushDistance, i / steps)}
              end
              projectBrushTexture(tex, list, nil, color, nil)
              lastRay = ray
            end
          else
            projectBrushTexture(tex, ray.pos, ray.dir, activeTool:brushColor(), brushDistance)
            lastRay = ray
          end
          smoothRayDir = ray.dir:clone()
        end)
        composeLayers(false)
      elseif not ignoreMousePress then
        ignoreMousePress = ui.mouseBusy()
        if not ignoreMousePress then
          drawing = true
          selectedMeshes:setMotionStencil(taaFix.On)
          if not uiState.shiftDown then
            lastRay = nil
          end
          local session = runtime.session
          setTimeout(function ()
            -- adding undo in the next frame, so that dragging mask could cancel drawing operation
            if drawing and session == runtime.session and editingCanvas and activeLayer() then
              addUndo(canvasBackup())
            end
          end)
        end
      end
    else
      if drawing then
        updateAccessibleData()
        selectedMeshes:setMotionStencil(taaFix.Off)
        drawing = false
      end
      ignoreMousePress = false
    end
  elseif activeTool.action then
    activeTool:action()
  end
  
  updateMaskingCanvas()
  updateAOCanvas()
end

function script.update(dt)
  if not appVisible then
    if camera then
      camera:dispose()
      camera = nil
    end
    return
  end
  if selectedMeshes ~= nil then
    cameraUpdate()
  end
end

function script.onWorldUpdate(dt)
  if appVisible and selectedMeshes ~= nil then
    ui.setAsynchronousImagesLoading(false)  -- when painting, easier to not wait for async images to load
    paintUpdate()
  end
end

local function rayPlane(ray, opposite)
  local s = opposite and userCar.look or userCar.side
  return ray:plane(userCar.position, s)
end

local maskingStartMousePos

---@param ray ray
local function draggingPoint(index, point, ray)
  local pos = userCar.bodyTransform:transformPoint(point)
  local hovered = ray:sphere(pos, 0.04) ~= -1
  render.circle(pos, -ac.getCameraForward(), 0.04,
    rgbm(hovered and sim.whiteReferencePoint or 0, sim.whiteReferencePoint, sim.whiteReferencePoint, 0.3), 
    rgbm(0, sim.whiteReferencePoint, sim.whiteReferencePoint, 1))
  if maskingDragging == 0 and uiState.isMouseLeftKeyClicked and hovered then
    maskingStartMousePos = ui.projectPoint(pos)
    maskingDragging = index
    ignoreMousePress = true
    drawing = false
    maskingCreatingFrom = nil
    addUndo(maskingBackup())
  elseif maskingDragging == index then
    maskingStartMousePos:add(uiState.mouseDelta)
    local r = render.createPointRay(maskingStartMousePos)
    local d = rayPlane(r, index > 2)
    if d ~= -1 then
      point:set(userCar.worldToLocal:transformPoint(r.pos + r.dir * d))
    end
  end
end

function script.draw3D()
  if appVisible and selectedMeshes ~= nil and maskingActive and not trackMode then
    if maskingCreatingFrom ~= nil and maskingCreatingTo ~= nil then
      applyQuickMasking(maskingCreatingFrom, maskingCreatingTo)
      render.circle(userCar.bodyTransform:transformPoint(maskingPos), userCar.bodyTransform:transformVector(maskingDir), 3,
        rgbm(sim.whiteReferencePoint, 0, 0, 0.1))
      return
    end

    render.circle(userCar.bodyTransform:transformPoint(maskingPos), userCar.bodyTransform:transformVector(maskingDir), 3,
      rgbm(sim.whiteReferencePoint, 0, 0, 0.3))

    local ray = render.createMouseRay()
    if not ui.mouseDown() then maskingDragging = 0 end
    render.setDepthMode(render.DepthMode.Off)
    draggingPoint(1, maskingPoints[1], ray)
    draggingPoint(2, maskingPoints[2], ray)
    draggingPoint(3, maskingPoints[3], ray)
    draggingPoint(4, maskingPoints[4], ray)

    if maskingDragging == 1 or maskingDragging == 2 then
      fitMaskingPoints(true)
    elseif maskingDragging == 3 or maskingDragging == 4 then
      fitMaskingPoints(false)
    end
  end
end

function script.windowMain(dt)
  if brushes == nil then
    rescanBrushes()
    rescanStickers()
  end
  
  ui.pushItemWidth(210)
  ui.setAsynchronousImagesLoading(true)
  if selectedMeshes == nil then
    MeshSelection()
  else
    SkinEditor()
  end
  ui.popItemWidth()

  if DebugTex then
    ui.setShadingOffset(1, 0, 1, 1)
    ui.image(DebugTex, 210, rgbm.colors.white, rgbm.colors.red)
    ui.resetShadingOffset()
  end
end
 
DebugTex = nil

function script.onShowWindowMain()
  appVisible = true 
end

function script.onHideWindowMain()
  appVisible = false
  if selectedMeshes == nil then
    setTimeout(ac.unloadApp, 1)
  elseif editingCanvas and history:isDirty() then
    saveRecoveryDraft()
  end
end
