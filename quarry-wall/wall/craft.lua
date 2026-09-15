--[[--------------------------------------------------------------------------
  craft.lua -- turning cobbled deepslate into everything else.

  Every recipe below reduces to cobbled deepslate, so the one chest is the
  only input the station needs. Recipes are shaped, and Minecraft matches a
  shape anywhere in the grid, so anchoring each one to the top-left of the 3x3
  is safe.

  Grids are written as rows of characters, "A" being the single ingredient and
  " " an empty cell.
----------------------------------------------------------------------------]]

local inv = require("inv")

local craft = {}

craft.RAW = "minecraft:cobbled_deepslate"

local function R(result, count, ingredient, grid)
  return { result = "minecraft:" .. result,
           count  = count,
           key    = { A = "minecraft:" .. ingredient },
           grid   = grid }
end

local SQUARE = { "AA", "AA" }        -- 2x2
local ROW    = { "AAA" }             -- 1x3
local SLAB2  = { "A", "A" }          -- 2x1, vertical
local BLOCK6 = { "AAA", "AAA" }      -- 2x3
local STAIR  = { "A  ", "AA ", "AAA" }

local recipes = {}

local function add(r) recipes[r.result] = r end

-- The polish chain. Each step is 4-in/4-out, so a deepslate tile costs
-- exactly one cobbled deepslate, same as a polished block does.
add(R("polished_deepslate", 4, "cobbled_deepslate",  SQUARE))
add(R("deepslate_bricks",   4, "polished_deepslate", SQUARE))
add(R("deepslate_tiles",    4, "deepslate_bricks",   SQUARE))

-- Chiseled is the odd one: it comes from two slabs, and one cobbled
-- deepslate makes two slabs, so it also lands at 1:1.
add(R("cobbled_deepslate_slab", 6, "cobbled_deepslate", ROW))
add(R("chiseled_deepslate",     1, "cobbled_deepslate_slab", SLAB2))

add(R("polished_deepslate_slab", 6, "polished_deepslate", ROW))
add(R("deepslate_brick_slab",    6, "deepslate_bricks",   ROW))
add(R("deepslate_tile_slab",     6, "deepslate_tiles",    ROW))

add(R("cobbled_deepslate_wall",  6, "cobbled_deepslate",  BLOCK6))
add(R("polished_deepslate_wall", 6, "polished_deepslate", BLOCK6))
add(R("deepslate_brick_wall",    6, "deepslate_bricks",   BLOCK6))
add(R("deepslate_tile_wall",     6, "deepslate_tiles",    BLOCK6))

add(R("cobbled_deepslate_stairs",  4, "cobbled_deepslate",  STAIR))
add(R("polished_deepslate_stairs", 4, "polished_deepslate", STAIR))
add(R("deepslate_brick_stairs",    4, "deepslate_bricks",   STAIR))
add(R("deepslate_tile_stairs",     4, "deepslate_tiles",    STAIR))

craft.recipes = recipes

function craft.recipeFor(name) return recipes[name] end

--- The grid cells a recipe occupies, as { {slot=, item=}, ... }.
local function cells(r)
  local out = {}
  for row = 1, #r.grid do
    local line = r.grid[row]
    for col = 1, #line do
      local ch = line:sub(col, col)
      if ch ~= " " then
        out[#out + 1] = { slot = inv.gridSlot(row, col), item = r.key[ch] }
      end
    end
  end
  return out
end

craft.cells = cells

--- How many crafts we can safely run in one go: capped so a single batch's
--- output still fits in one stack, and so no grid slot needs more than 64.
local function maxSteps(r)
  return math.min(16, math.floor(64 / r.count))
end

--- Cobbled deepslate consumed per unit of `name`. Slabs come out at 0.5,
--- stairs at 1.5, everything else at 1.0.
function craft.rawCost(name)
  if name == craft.RAW then return 1 end
  local r = recipes[name]
  if not r then return nil end
  local total = 0
  for _, c in ipairs(cells(r)) do
    local sub = craft.rawCost(c.item)
    if not sub then return nil end
    total = total + sub
  end
  return total / r.count
end

--- Is `name` reachable from cobbled deepslate at all? Used by `wall plan` so
--- a typo in the pattern is caught before the turtle leaves the station.
function craft.isReachable(name)
  return name == craft.RAW or craft.rawCost(name) ~= nil
end

--- The chain of intermediates needed for `name`, root first.
function craft.chain(name)
  local out, cur = {}, name
  while cur and cur ~= craft.RAW do
    table.insert(out, 1, cur)
    local r = recipes[cur]
    if not r then break end
    cur = cells(r)[1].item
  end
  return out
end

--- Run one batch of `steps` crafts. The grid is cleared before staging and
--- again afterwards, because turtle.craft() leaves its output sitting in the
--- grid slots where the next stage would trip over it.
local function runBatch(r, steps)
  local ok, err = inv.clearGrid()
  if not ok then return false, err end

  for _, c in ipairs(cells(r)) do
    if not inv.stage(c.slot, c.item, steps) then
      inv.clearGrid()
      return false, ("could not stage %d x %s"):format(steps, c.item)
    end
  end

  local out = inv.firstEmpty(inv.STORAGE)
  if out then turtle.select(out) end

  local crafted, why = turtle.craft(steps)
  inv.clearGrid()

  if not crafted then return false, why or "turtle.craft() refused the recipe" end
  return true
end

--[[--------------------------------------------------------------------------
  ensure -- get at least `count` of `name` into the inventory, crafting
  intermediates as needed.

  Cobbled deepslate is the floor of the recursion: we never craft it, so if
  there isn't enough the caller has to go and pull more from the chest.
----------------------------------------------------------------------------]]
function craft.ensure(name, count)
  if inv.count(name) >= count then return true end

  if name == craft.RAW then
    return false, ("need %d cobbled deepslate, have %d")
                  :format(count, inv.count(craft.RAW))
  end

  local r = recipes[name]
  if not r then return false, "no recipe for " .. name end

  local guard = 0
  while inv.count(name) < count do
    guard = guard + 1
    if guard > 256 then
      return false, "crafting " .. name .. " stopped making progress"
    end

    local short = count - inv.count(name)
    local steps = math.min(maxSteps(r), math.ceil(short / r.count))

    -- Pull the ingredients up from further down the chain first.
    local need = {}
    for _, c in ipairs(cells(r)) do need[c.item] = (need[c.item] or 0) + steps end
    for item, n in pairs(need) do
      local ok, err = craft.ensure(item, n)
      if not ok then return false, err end
    end

    local ok, err = runBatch(r, steps)
    if not ok then return false, err end
  end

  return true
end

return craft
