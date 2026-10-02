local Files = {}
local serial = 0

local function nextSuffix()
  serial = serial + 1
  return tostring(os.time())..'-'..serial
end

function Files.validName(value)
  if type(value) ~= 'string' or #value == 0 or #value > 100
      or value:match('[%c<>:"/\\|?*]') or value:match('^[ .]') or value:match('[ .]$') then
    return false
  end
  local base = (value:match('^[^.]+') or value):upper()
  return base ~= 'CON' and base ~= 'PRN' and base ~= 'AUX' and base ~= 'NUL'
      and not base:match('^COM[1-9]$') and not base:match('^LPT[1-9]$')
end

function Files.pathKey(value)
  local key = tostring(value or 'unknown'):gsub('[%c<>:"/\\|?*]', '_'):gsub('[ .]+$', '')
  if not Files.validName(key) then key = 'item_'..key:gsub('^[ .]+', '') end
  return key:sub(1, 80)
end

function Files.extension(filename)
  return type(filename) == 'string' and filename:lower():match('%.([a-z0-9]+)$') or nil
end

function Files.ensureExtension(filename, fallback)
  if not Files.extension(filename) then return filename..'.'..fallback end
  return filename
end

function Files.ensureSpecificExtension(filename, extension)
  return Files.extension(filename) == extension:lower() and filename or filename..'.'..extension
end

function Files.format(filename)
  local ext = Files.extension(filename)
  if ext == 'png' then return ac.ImageFormat.PNG end
  if ext == 'jpg' or ext == 'jpeg' then return ac.ImageFormat.JPG end
  if ext == 'dds' then return ac.ImageFormat.DDS end
  return nil
end

function Files.temporarySibling(filename, extension)
  return filename..'.paintshop-'..nextSuffix()..'.'..(extension or 'tmp')
end

-- Commit a fully written sibling. Preserve the old file before replacing it,
-- and keep the temporary file if the final move fails so it can be recovered.
function Files.commitTemporary(temporary, filename, backupDir, keepBackup)
  local ok, err = pcall(function ()
    if not io.fileExists(temporary) or io.fileSize(temporary) <= 0 then
      error('O arquivo temporário não foi gravado corretamente.')
    end
    if io.fileExists(filename) then
      if keepBackup then
        if not io.dirExists(backupDir) then io.createDir(backupDir) end
        local extension = Files.extension(filename) or 'bak'
        local backup = backupDir..'/'..Files.pathKey(io.getFileName(filename))..'-'..nextSuffix()..'.'..extension
        if not io.copyFile(filename, backup, true) then error('Falha ao preservar o arquivo anterior.') end
      end
      if not io.replaceFile(filename, temporary) then error('Falha ao substituir o arquivo. Cópia recuperável: '..temporary) end
    elseif not io.move(temporary, filename, false) then
      error('Falha ao finalizar o salvamento. Cópia recuperável: '..temporary)
    end
  end)
  if ok then return true end
  return false, tostring(err)
end

-- Save to a unique sibling first and only then commit it to the requested name.
function Files.saveCanvas(canvas, filename, backupDir, keepBackup)
  local format = Files.format(filename)
  if not format then return false, 'Formato inválido. Use PNG, JPEG ou DDS.' end
  local temporary = Files.temporarySibling(filename, Files.extension(filename))
  local ok, err = pcall(function ()
    canvas:save(temporary, format)
  end)
  if not ok then return false, tostring(err) end
  return Files.commitTemporary(temporary, filename, backupDir, keepBackup)
end

function Files.copySkin(source, destination)
  local copied = 0
  local function copyDirectory(from, to, depth)
    if depth > 12 then error('A skin contém uma estrutura de pastas muito profunda.') end
    if not io.dirExists(to) and not io.createDir(to) then error('Falha ao criar pasta: '..to) end
    for _, name in ipairs(io.scanDir(from, '*')) do
      if name == '.' or name == '..' or name:find('[/\\]') then error('Caminho inválido na skin.') end
      local src, dst = from..'/'..name, to..'/'..name
      if io.dirExists(src) then copyDirectory(src, dst, depth + 1)
      elseif io.fileExists(src) then
        copied = copied + 1
        if copied > 2000 then error('A skin excede o limite de 2000 arquivos.') end
        if not io.copyFile(src, dst, true) then error('Falha ao copiar: '..name) end
      end
    end
  end
  if io.exists(destination) then return false, 'Já existe uma skin com este nome.' end
  local ok, err = pcall(copyDirectory, source, destination, 0)
  if ok then return true end
  return false, tostring(err)..'\nPasta parcial preservada: '..destination
end

return Files
