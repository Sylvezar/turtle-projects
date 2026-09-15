--[[--------------------------------------------------------------------------
  mock.lua -- a fake ComputerCraft world, just enough of it to run `wall`
  offline and check what the turtle actually did.

  The point of the crafting mock is that it matches recipes by SHAPE, derived
  independently of how craft.lua stages them. So if the staging code puts a
  stray stack in a grid slot, or anchors a shape wrongly, the mock refuses the
  recipe exactly as a real turtle would.

  turtle.dig() is deliberately absent. Any attempt to break a block is an
  immediate error rather than a silent success.
----------------------------------------------------------------------------]]

local mock = {}

local MAXSTACK = 64

--[[-- world -----------------------------------------------------------------]]

local world = {}          -- "x,y,z" -> block name
local function key(x, y, z) return x .. "," .. y .. "," .. z end

function mock.setBlock(x, y, z, name) world[key(x, y, z)] = name end
function mock.getBlock(x, y, z) return world[key(x, y, z)] end
function mock.solid(x, y, z) return world[key(x, y, z)] ~= nil end

--[[-- turtle state ----------------------------------------------------------]]

local T = {
  x = 0, y = 0, z = 0, h = 0,
  slots = {},               -- [1..16] = {name=, count=}
  selected = 1,
  fuel = 100000,
  moves = 0,
  placed = 0,
}

mock.T = T

local DX = { [0] = 0, [1] = 1, [2] = 0, [3] = -1 }
local DZ = { [0] = 1, [1] = 0, [2] = -1, [3] = 0 }

function mock.setTurtle(x, y, z, h) T.x, T.y, T.z, T.h = x, y, z, h end

--[[-- chests ----------------------------------------------------------------]]

-- A list of { side, at = {x,y,z}, heading, stacks = {...}, infinite = name }.
-- Keyed by position rather than by side alone, because the supply and fuel
-- chests are both reached with side "front" -- from different places.
local chests = {}

function mock.setChest(spec) chests[#chests + 1] = spec end
function mock.chests() return chests end

--- A chest is only reachable when the turtle is actually standing where the
--- spec says and facing the right way, so the tests really do check that it
--- went home to restock rather than conjuring items wherever it happened to
--- be -- and that the fuel chest is only reached from one block up.
local function chestAt(side)
  for _, ch in ipairs(chests) do
    if ch.side == side
    and T.x == ch.at[1] and T.y == ch.at[2] and T.z == ch.at[3]
    and (ch.heading == nil or ch.heading == T.h) then
      return ch
    end
  end
  return nil
end

--[[-- recipes for the mock crafter ------------------------------------------]]

-- Written out again here on purpose: the mock must not share a table with the
-- code under test, or a wrong recipe would agree with itself.
local RECIPES = {}

local function recipe(result, count, ingredient, rows)
  RECIPES[#RECIPES + 1] = {
    result = "minecraft:" .. result,
    count = count,
    item = "minecraft:" .. ingredient,
    rows = rows,
  }
end

recipe("polished_deepslate", 4, "cobbled_deepslate",      { "AA", "AA" })
recipe("deepslate_bricks",   4, "polished_deepslate",     { "AA", "AA" })
recipe("deepslate_tiles",    4, "deepslate_bricks",       { "AA", "AA" })
recipe("cobbled_deepslate_slab", 6, "cobbled_deepslate",  { "AAA" })
recipe("chiseled_deepslate", 1, "cobbled_deepslate_slab", { "A", "A" })
recipe("polished_deepslate_slab", 6, "polished_deepslate", { "AAA" })
recipe("deepslate_brick_slab",    6, "deepslate_bricks",   { "AAA" })
recipe("deepslate_tile_slab",     6, "deepslate_tiles",    { "AAA" })
recipe("cobbled_deepslate_wall",  6, "cobbled_deepslate",  { "AAA", "AAA" })
recipe("polished_deepslate_wall", 6, "polished_deepslate", { "AAA", "AAA" })
recipe("deepslate_brick_wall",    6, "deepslate_bricks",   { "AAA", "AAA" })
recipe("deepslate_tile_wall",     6, "deepslate_tiles",    { "AAA", "AAA" })
recipe("cobbled_deepslate_stairs",  4, "cobbled_deepslate",  { "A  ", "AA ", "AAA" })
recipe("polished_deepslate_stairs", 4, "polished_deepslate", { "A  ", "AA ", "AAA" })
recipe("deepslate_brick_stairs",    4, "deepslate_bricks",   { "A  ", "AA ", "AAA" })
recipe("deepslate_tile_stairs",     4, "deepslate_tiles",    { "A  ", "AA ", "AAA" })

-- Grid slot for (row, col) of the crafting 3x3.
local function gslot(r, c) return (r - 1) * 4 + c end

--- The turtle grid as a 3x3 of item names, then trimmed to its bounding box,
--- which is how Minecraft matches a shaped recipe placed anywhere in the grid.
local function readGrid()
  local g = {}
  for r = 1, 3 do
    g[r] = {}
    for c = 1, 3 do
      local s = T.slots[gslot(r, c)]
      g[r][c] = s and s.name or nil
    end
  end

  local r0, r1, c0, c1 = 4, 0, 4, 0
  for r = 1, 3 do
    for c = 1, 3 do
      if g[r][c] then
        if r < r0 then r0 = r end
        if r > r1 then r1 = r end
        if c < c0 then c0 = c end
        if c > c1 then c1 = c end
      end
    end
  end
  if r1 == 0 then return nil end

  -- Indices are assigned explicitly rather than appended: a sparse recipe like
  -- stairs has nil cells, and `row[#row + 1] = nil` would quietly shuffle the
  -- remaining cells left and turn every shape into a dense one.
  local out = { height = r1 - r0 + 1, width = c1 - c0 + 1 }
  for r = r0, r1 do
    local row = {}
    for c = c0, c1 do row[c - c0 + 1] = g[r][c] end
    out[r - r0 + 1] = row
  end
  return out
end

local function matches(shape, r)
  if shape.height ~= #r.rows then return false end
  for i = 1, shape.height do
    local pat = r.rows[i]
    if shape.width ~= #pat then return false end
    for j = 1, shape.width do
      local want = nil
      if pat:sub(j, j) == "A" then want = r.item end
      if shape[i][j] ~= want then return false end
    end
  end
  return true
end

--[[-- inventory helpers -----------------------------------------------------]]

local function addToSlot(slot, name, n)
  local s = T.slots[slot]
  if not s then
    T.slots[slot] = { name = name, count = math.min(n, MAXSTACK) }
    return math.min(n, MAXSTACK)
  end
  if s.name ~= name then return 0 end
  local room = MAXSTACK - s.count
  local moved = math.min(room, n)
  s.count = s.count + moved
  return moved
end

local function giveItems(name, n)
  local left = n
  for slot = 1, 16 do
    if left <= 0 then break end
    local s = T.slots[slot]
    if s and s.name == name then left = left - addToSlot(slot, name, left) end
  end
  for slot = 1, 16 do
    if left <= 0 then break end
    if not T.slots[slot] then left = left - addToSlot(slot, name, left) end
  end
  return n - left
end

local function takeFromSlot(slot, n)
  local s = T.slots[slot]
  if not s then return 0 end
  local taken = math.min(n, s.count)
  s.count = s.count - taken
  if s.count <= 0 then T.slots[slot] = nil end
  return taken
end

--[[-- the turtle API --------------------------------------------------------]]

local turtle = {}

local function target(dir)
  if dir == "up"   then return T.x, T.y + 1, T.z end
  if dir == "down" then return T.x, T.y - 1, T.z end
  return T.x + DX[T.h], T.y, T.z + DZ[T.h]
end

local function move(dir)
  if T.fuel <= 0 then return false, "Out of fuel" end
  local nx, ny, nz = target(dir)
  if dir == "back" then nx, ny, nz = T.x - DX[T.h], T.y, T.z - DZ[T.h] end
  if mock.solid(nx, ny, nz) then return false, "Movement obstructed" end
  T.x, T.y, T.z = nx, ny, nz
  T.fuel = T.fuel - 1
  T.moves = T.moves + 1
  return true
end

function turtle.forward() return move("forward") end
function turtle.back()    return move("back") end
function turtle.up()      return move("up") end
function turtle.down()    return move("down") end

function turtle.turnLeft()  T.h = (T.h + 3) % 4 return true end
function turtle.turnRight() T.h = (T.h + 1) % 4 return true end

function turtle.detect()     return mock.solid(target("forward")) end
function turtle.detectUp()   return mock.solid(target("up")) end
function turtle.detectDown() return mock.solid(target("down")) end

local function inspect(dir)
  local name = mock.getBlock(target(dir))
  if not name then return false, "No block to inspect" end
  return true, { name = name, state = {}, tags = {} }
end

function turtle.inspect()     return inspect("forward") end
function turtle.inspectUp()   return inspect("up") end
function turtle.inspectDown() return inspect("down") end

local function place(dir)
  local s = T.slots[T.selected]
  if not s then return false, "No items to place" end
  local x, y, z = target(dir)
  if mock.solid(x, y, z) then return false, "Cannot place block here" end
  mock.setBlock(x, y, z, s.name)
  takeFromSlot(T.selected, 1)
  T.placed = T.placed + 1
  return true
end

function turtle.place()     return place("forward") end
function turtle.placeUp()   return place("up") end
function turtle.placeDown() return place("down") end

function turtle.select(n) T.selected = n return true end
function turtle.getSelectedSlot() return T.selected end

function turtle.getItemCount(n)
  local s = T.slots[n or T.selected]
  return s and s.count or 0
end

function turtle.getItemSpace(n)
  local s = T.slots[n or T.selected]
  return s and (MAXSTACK - s.count) or MAXSTACK
end

function turtle.getItemDetail(n)
  local s = T.slots[n or T.selected]
  if not s then return nil end
  return { name = s.name, count = s.count }
end

--- Note the return value: the real turtle reports FAILURE when it could not
--- move everything asked for, even though it moved what it could. Code that
--- treats that as "nothing happened" gets the inventory wrong, so the mock
--- behaves the same way and the tests can catch it.
function turtle.transferTo(dst, n)
  local src = T.selected
  if src == dst then return true end
  local s = T.slots[src]
  if not s then return false end

  local want = math.min(n or s.count, s.count)
  local d = T.slots[dst]
  if d and d.name ~= s.name then return false end

  local moved = addToSlot(dst, s.name, want)
  takeFromSlot(src, moved)
  return moved >= want
end

local function suck(side, count)
  local ch = chestAt(side)
  if not ch then return false end
  count = count or MAXSTACK

  local name, avail
  if ch.infinite then
    name, avail = ch.infinite, count
  else
    local st = ch.stacks and ch.stacks[1]
    if not st or st.count <= 0 then return false end
    name, avail = st.name, math.min(count, st.count)
  end

  -- Fill the selected slot first, then spill, exactly as a real turtle does.
  local room = 0
  local sel = T.slots[T.selected]
  if not sel then room = MAXSTACK
  elseif sel.name == name then room = MAXSTACK - sel.count end

  local want = math.min(avail, math.max(room, 0))
  local got = 0
  if want > 0 then got = addToSlot(T.selected, name, want) end
  if got == 0 then got = giveItems(name, avail) end
  if got == 0 then return false end

  if not ch.infinite then
    ch.stacks[1].count = ch.stacks[1].count - got
    if ch.stacks[1].count <= 0 then table.remove(ch.stacks, 1) end
  end
  return true
end

function turtle.suck(n)     return suck("front", n) end
function turtle.suckUp(n)   return suck("up", n) end
function turtle.suckDown(n) return suck("down", n) end

local function drop(side, count)
  local ch = chestAt(side)
  if not ch then return false end
  local s = T.slots[T.selected]
  if not s then return false end
  local n = math.min(count or s.count, s.count)
  ch.stacks = ch.stacks or {}
  ch.stacks[#ch.stacks + 1] = { name = s.name, count = n }
  takeFromSlot(T.selected, n)
  return true
end

function turtle.drop(n)     return drop("front", n) end
function turtle.dropUp(n)   return drop("up", n) end
function turtle.dropDown(n) return drop("down", n) end

local FUEL = {
  ["minecraft:coal"]        = 80,
  ["minecraft:charcoal"]    = 80,
  ["minecraft:coal_block"]  = 800,
  ["minecraft:lava_bucket"] = 1000,
}

function turtle.refuel(n)
  local s = T.slots[T.selected]
  if not s or not FUEL[s.name] then return false end
  if n == 0 then return true end
  local burn = math.min(n or s.count, s.count)
  T.fuel = T.fuel + burn * FUEL[s.name]
  takeFromSlot(T.selected, burn)
  return true
end

function turtle.getFuelLevel() return T.fuel end
function turtle.getFuelLimit() return 100000 end

--[[--------------------------------------------------------------------------
  turtle.craft()

  Confirmed in game: the real turtle matches the recipe against the WHOLE
  inventory, not just the top-left 3x3. A single item anywhere else -- a spare
  coal block, leftover material in slot 16 -- and nothing matches.

  The mock used to ignore the other seven slots, which is exactly why the
  offline tests were happy with a crafting design that could not work. It now
  refuses the same way the real thing does.
----------------------------------------------------------------------------]]
local GRID_SLOTS = {
  [1] = true, [2] = true, [3] = true,
  [5] = true, [6] = true, [7] = true,
  [9] = true, [10] = true, [11] = true,
}

function turtle.craft(limit)
  limit = limit or 64

  for slot = 1, 16 do
    if not GRID_SLOTS[slot] and T.slots[slot] then
      return false, "No matching recipes"
    end
  end

  local shape = readGrid()
  if not shape then return false, "No matching recipes" end

  local r
  for _, cand in ipairs(RECIPES) do
    if matches(shape, cand) then r = cand break end
  end
  if not r then return false, "No matching recipes" end

  -- How many times we can actually run it.
  local steps = limit
  local used = {}
  for row = 1, 3 do
    for col = 1, 3 do
      local slot = gslot(row, col)
      if T.slots[slot] then
        used[#used + 1] = slot
        steps = math.min(steps, T.slots[slot].count)
      end
    end
  end
  if steps <= 0 then return false, "No matching recipes" end

  for _, slot in ipairs(used) do takeFromSlot(slot, steps) end

  local made = steps * r.count
  local gave = giveItems(r.result, made)
  if gave < made then return false, "No space for results" end
  return true
end

mock.turtle = turtle

--[[-- the rest of the CC globals --------------------------------------------]]

local files = {}

local fs = {}
local dirs = {}

function fs.exists(p) return files[p] ~= nil or dirs[p] == true end
function fs.delete(p) files[p] = nil ; dirs[p] = nil end
function fs.getDir(p) return (p:match("^(.*)/[^/]*$")) or "" end
function fs.makeDir(p) dirs[p] = true end
function fs.isDir(p) return dirs[p] == true end

function fs.open(p, mode)
  if mode == "w" or mode == "a" then
    local buf = {}
    if mode == "a" and files[p] then buf[1] = files[p] end
    return {
      write = function(s) buf[#buf + 1] = s end,
      writeLine = function(s) buf[#buf + 1] = s .. "\n" end,
      close = function() files[p] = table.concat(buf) end,
    }
  end
  if not files[p] then return nil end
  return {
    readAll = function() return files[p] end,
    readLine = function() return nil end,
    close = function() end,
  }
end

mock.fs = fs
mock.files = files

local textutils = {}

local function ser(v, indent)
  indent = indent or ""
  local t = type(v)
  if t == "number" or t == "boolean" then return tostring(v) end
  if t == "string" then return string.format("%q", v) end
  if t ~= "table" then return "nil" end

  local parts = {}
  local n = #v
  for i = 1, n do parts[#parts + 1] = ser(v[i], indent) end
  for k, val in pairs(v) do
    if not (type(k) == "number" and k >= 1 and k <= n and k % 1 == 0) then
      parts[#parts + 1] = "[" .. ser(k) .. "]=" .. ser(val, indent)
    end
  end
  return "{" .. table.concat(parts, ",") .. "}"
end

function textutils.serialize(v) return ser(v) end
function textutils.unserialize(s)
  local f = load("return " .. s)
  if not f then return nil end
  local ok, v = pcall(f)
  return ok and v or nil
end

mock.textutils = textutils

--[[-- rednet ---------------------------------------------------------------

  Enough of a radio to check what the turtles broadcast. No modem is attached
  by default, so reporting stays switched off unless a test asks for it -- which
  is also the check that a turtle without one behaves exactly as before.
----------------------------------------------------------------------------]]

local modemSide = nil
local sent      = {}

function mock.setModem(side) modemSide = side end
function mock.sent() return sent end
function mock.clearSent() sent = {} end

--- Turn a peripheral side name into the side a chest spec uses.
local function chestSideOf(s)
  if s == "bottom" then return "down" end
  if s == "top"    then return "up" end
  return s
end

local peripheralApi = {
  getType = function(s)
    if s == modemSide then return "modem" end
    if chestAt(chestSideOf(s)) then return "minecraft:chest" end
    return nil
  end,

  isPresent = function(s)
    return s == modemSide or chestAt(chestSideOf(s)) ~= nil
  end,

  --- Just enough inventory peripheral to read a chest without touching it,
  --- which is how the turtle checks whether what it needs is already made.
  wrap = function(s)
    if s == modemSide then return { open = function() end } end
    local ch = chestAt(chestSideOf(s))
    if not ch then return nil end
    return {
      size = function() return 27 end,
      list = function()
        local out = {}
        if ch.infinite then
          out[1] = { name = ch.infinite, count = 64 }
        else
          for i, st in ipairs(ch.stacks or {}) do
            out[i] = { name = st.name, count = st.count }
          end
        end
        return out
      end,
    }
  end,
}

local rednetApi = {
  open    = function() return true end,
  close   = function() return true end,
  isOpen  = function() return modemSide ~= nil end,
  broadcast = function(msg, protocol)
    sent[#sent + 1] = { msg = msg, protocol = protocol }
    return true
  end,
  receive = function() return nil end,
}

mock.peripheral = peripheralApi
mock.rednet     = rednetApi

--[[-- events ---------------------------------------------------------------

  A scriptable event queue, so the enlist/assign handshake can be driven
  without a running computer. Tests push the events they want the turtle to
  see; pulling from an empty queue is an error rather than a hang, which turns
  "waited forever" into a visible test failure.
----------------------------------------------------------------------------]]

local events  = {}
local timerId = 0

function mock.pushEvent(...) events[#events + 1] = { ... } end
function mock.pendingEvents() return #events end

--- Also resets the timer counter, so a test can push ("timer", 1) and have it
--- match the first timer the code under test starts.
function mock.clearEvents()
  events = {}
  timerId = 0
end

--- Install everything as globals.
function mock.install()
  _G.peripheral = peripheralApi
  _G.rednet     = rednetApi
  _G.keys       = { enter = 257 }

  os.pullEvent = function()
    if #events == 0 then error("mock: pullEvent with no events queued", 0) end
    return table.unpack(table.remove(events, 1))
  end
  os.startTimer = function() timerId = timerId + 1 return timerId end
  os.getComputerID = function() return 7 end
  os.getComputerLabel = function() return "wall-test" end
  _G.colours    = { red = 0x4000, white = 0x1 }
  _G.term = {
    getSize      = function() return 51, 19 end,
    clear        = function() end,
    setCursorPos = function() end,
    setTextColour = function() end,
  }
  _G.turtle = turtle
  _G.fs = fs
  _G.textutils = textutils
  _G.sleep = function() end
  _G.write = function(s) io.write(s) end
  _G.printError = function(s) print("ERR: " .. tostring(s)) end
  _G.read = function() return "y" end
  _G.shell = { getRunningProgram = function() return "wall/wall.lua" end }
end

--[[-- scenario builder ------------------------------------------------------]]

--- Build a quarry pit: interior x in [0,w-1], z in [0,d-1], air for y in
--- [0,h-1], solid floor at y=-1 and solid rock everywhere outside the pit up
--- to the rim.
function mock.buildPit(w, d, h, margin)
  margin = margin or 3
  for x = -margin, w - 1 + margin do
    for z = -margin, d - 1 + margin do
      mock.setBlock(x, -1, z, "minecraft:bedrock")
      local outside = x < 0 or x >= w or z < 0 or z >= d
      if outside then
        for y = 0, h - 1 do mock.setBlock(x, y, z, "minecraft:deepslate") end
      end
    end
  end
end

--- Wipe the world, the chests, the saved files and the turtle, so each
--- scenario starts from nothing.
function mock.reset()
  for k in pairs(world) do world[k] = nil end
  for k in pairs(chests) do chests[k] = nil end
  for k in pairs(files) do files[k] = nil end
  for i = 1, 16 do T.slots[i] = nil end
  T.x, T.y, T.z, T.h = 0, 0, 0, 0
  T.selected, T.fuel, T.moves, T.placed = 1, 100000, 0, 0
end

--- Everything the turtle placed, as { ["x,y,z"] = name }.
function mock.placedBlocks(predicate)
  local out = {}
  for k, v in pairs(world) do
    if predicate(k, v) then out[k] = v end
  end
  return out
end

return mock
