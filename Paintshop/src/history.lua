-- Revision IDs survive branching and eviction, unlike a count of changes.
local History = {}
History.__index = History

function History.new(maxBytes, maxEntries)
  return setmetatable({undo = {}, redo = {}, revision = 0, savedRevision = 0,
    nextRevision = 0, maxBytes = maxBytes, maxEntries = maxEntries or 30}, History)
end

local function dispose(entry)
  entry.restore('dispose')
end

local function clear(stack)
  for _, entry in ipairs(stack) do dispose(entry) end
  for i = #stack, 1, -1 do stack[i] = nil end
end

function History:memoryFootprint()
  local bytes = 0
  for _, stack in ipairs({self.undo, self.redo}) do
    for _, entry in ipairs(stack) do bytes = bytes + (entry.restore('memoryFootprint') or 0) end
  end
  return bytes
end

function History:trim(reserve)
  while #self.undo > 0 and (#self.undo > self.maxEntries
      or self:memoryFootprint() + (reserve or 0) > self.maxBytes) do
    dispose(table.remove(self.undo, 1))
  end
  while #self.redo > 0 and self:memoryFootprint() + (reserve or 0) > self.maxBytes do
    dispose(table.remove(self.redo, 1))
  end
end

-- Reserve room before cloning the GPU canvas. A huge operation still changes
-- the revision, but cannot allocate an undo texture beyond the user's budget.
function History:prepare(bytes)
  clear(self.redo)
  self:trim(bytes)
  return bytes <= self.maxBytes
end

function History:push(restore)
  clear(self.redo)
  self.nextRevision = self.nextRevision + 1
  if restore then
    table.insert(self.undo, {restore = restore, before = self.revision, after = self.nextRevision})
  else
    clear(self.undo)
  end
  self.revision = self.nextRevision
  self:trim()
end

function History:stepUndo()
  local entry = self.undo[#self.undo]
  if not entry then return false end
  local reverse = entry.restore('update')
  entry.restore()
  table.remove(self.undo)
  table.insert(self.redo, {restore = reverse, before = entry.before, after = entry.after})
  self.revision = entry.before
  dispose(entry)
  self:trim()
  return true
end

function History:stepRedo()
  local entry = self.redo[#self.redo]
  if not entry then return false end
  local reverse = entry.restore('update')
  entry.restore()
  table.remove(self.redo)
  table.insert(self.undo, {restore = reverse, before = entry.before, after = entry.after})
  self.revision = entry.after
  dispose(entry)
  self:trim()
  return true
end

function History:markSaved(revision)
  self.savedRevision = revision or self.revision
end

function History:isDirty()
  return self.revision ~= self.savedRevision
end

function History:reset()
  clear(self.undo)
  clear(self.redo)
  self.revision, self.savedRevision, self.nextRevision = 0, 0, 0
end

return History
