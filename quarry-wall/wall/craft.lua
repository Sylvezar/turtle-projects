--[[--------------------------------------------------------------------------
  craft.lua -- turning cobbled deepslate into everything else.

  Every recipe below reduces to cobbled deepslate, so the one chest is the only
  input the station needs.

  THE CONSTRAINT THAT SHAPES ALL OF THIS: turtle.craft() matches the recipe
  against the WHOLE inventory, not just the top-left 3x3. One stray item in any
  other slot -- a spare coal block, leftover material, the output of the last
  batch -- and nothing matches. So at the moment of the craft the turtle must
  hold the recipe and absolutely nothing else.

  That rules out keeping a working stock on board while crafting, and it is why
  batches are planned rather than improvised: a batch is sized so that every
  stage of the chain divides exactly, leaving no remainder anywhere to spoil
  the next craft. What cannot fit in one batch is parked in the overflow chest
  by the caller and collected at the end.

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

-- The polish chain. Each step is 4-in/4-out, so a deepslate tile costs exactly
-- one cobbled deepslate, same as a polished block does.
add(R("polished_deepslate", 4, "cobbled_deepslate",  SQUARE))
add(R("deepslate_bricks",   4, "polished_deepslate", SQUARE))
add(R("deepslate_tiles",    4, "deepslate_bricks",   SQUARE))

-- Chiseled is the odd one: it comes from two slabs, and one cobbled deepslate
-- makes two slabs, so it also lands at 1:1.
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
      if line:sub(col, col) ~= " " then
        out[#out + 1] = { slot = inv.gridSlot(row, col),
                          item = r.key[line:sub(col, col)] }
      end
    end
  end
  return out
end

craft.cells = cells

local function cellCount(r) return #cells(r) end

--- Cobbled deepslate consumed per unit. Slabs come out at 0.5, stairs at 1.5,
--- everything else at 1.0.
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

function craft.isReachable(name)
  return name == craft.RAW or craft.rawCost(name) ~= nil
end

--- The recipes needed to get from cobbled deepslate to `name`, in order.
function craft.chainOf(name)
  local out, cur = {}, name
  while cur and cur ~= craft.RAW do
    local r = recipes[cur]
    if not r then return nil end
    table.insert(out, 1, r)
    cur = cells(r)[1].item
  end
  return out
end

--[[--------------------------------------------------------------------------
  planBatch -- the largest batch of `name` that divides exactly.

  Works backwards from the finished block. For a chosen number of crafting
  steps at the final stage, each earlier stage must produce exactly what the
  next one consumes -- no remainder, because a remainder is a stray item and a
  stray item means no recipe matches.

  Also bounded by what a crafting grid can physically hold: at most 64 items in
  any one cell, and at most 64 steps in one turtle.craft() call.

  Returns { steps = {per stage}, raw = cobbled needed, out = blocks produced }.
  `out` may exceed `want` slightly when `want` is not a whole number of crafts;
  three spare deepslate tiles is the usual worst case.
----------------------------------------------------------------------------]]
function craft.planBatch(name, want)
  local chain = craft.chainOf(name)
  if not chain then return nil, "no recipe for " .. name end
  if want < 1 then return nil, "nothing wanted" end

  local last = chain[#chain]
  local top  = math.min(64, math.max(1, math.ceil(want / last.count)))

  --- Does `s` crafts of the last stage divide cleanly all the way down?
  local function trySteps(s)
    local steps, need = {}, s

    for i = #chain, 1, -1 do
      local r = chain[i]
      if need < 1 or need > 64 then return nil end
      steps[i] = need

      local inputItems = need * cellCount(r)
      if i > 1 then
        local prev = chain[i - 1]
        if inputItems % prev.count ~= 0 then return nil end
        -- math.floor, not integer division: CC:Tweaked is Lua 5.2 and has
        -- no such operator.
        need = math.floor(inputItems / prev.count)
      else
        need = inputItems          -- raw cobbled deepslate
      end
    end

    return { steps = steps, chain = chain, raw = need, out = s * last.count }
  end

  -- The biggest batch that does not overshoot, first.
  for s = top, 1, -1 do
    local plan = trySteps(s)
    if plan then return plan end
  end

  -- Nothing divides inside what was asked for. Some chains have a minimum: a
  -- chiseled deepslate takes two slabs and slabs come six at a time, so three
  -- is the smallest batch that comes out even -- and asking for one has no
  -- exact answer at all. Make the smallest batch that does divide and carry the
  -- remainder; it goes to the overflow chest and gets used next time round.
  for s = top + 1, 64 do
    local plan = trySteps(s)
    if plan then return plan end
  end

  return nil, ("cannot find a clean batch for %s"):format(name)
end

--[[--------------------------------------------------------------------------
  runBatch -- convert a turtle holding exactly `plan.raw` cobbled deepslate,
  and nothing else, into `plan.out` finished blocks.

  Each stage consumes everything the last one made, so the inventory never has
  anything in it but the current stage's material.
----------------------------------------------------------------------------]]
function craft.runBatch(plan)
  for i, r in ipairs(plan.chain) do
    local steps = plan.steps[i]

    local ok, err = inv.stageOnly(cells(r), steps)
    if not ok then
      return false, ("staging %s: %s"):format(r.result, tostring(err))
    end

    local crafted, why = turtle.craft(steps)
    if not crafted then
      return false, ("%s: %s"):format(r.result, tostring(why or "craft refused"))
    end
  end

  return true
end

return craft
