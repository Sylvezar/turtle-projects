--[[--------------------------------------------------------------------------
  run.lua -- offline tests for the wall program.

  Runs the real modules against the fake world in mock.lua:

      py -3 test/drive.py
----------------------------------------------------------------------------]]

package.path = "wall/?.lua;test/?.lua;" .. package.path

local mock = require("mock")
mock.install()

local craft   = require("craft")
local inv     = require("inv")
local pattern = require("pattern")
local nav     = require("nav")
local ring    = require("ring")
local scan    = require("scan")
local build   = require("build")
local report  = require("report")
local cfg     = require("config")

local pass, fail = 0, 0

local function ok(cond, what)
  if cond then pass = pass + 1
  else fail = fail + 1 ; print("  FAIL: " .. what) end
end

local function eq(got, want, what)
  if got == want then pass = pass + 1
  else
    fail = fail + 1
    print(("  FAIL: %s -- got %s, want %s")
          :format(what, tostring(got), tostring(want)))
  end
end

local function section(n) print("") print("== " .. n) end
local function M(n) return "minecraft:" .. n end

--[[--------------------------------------------------------------------------
  The simulated quarry
----------------------------------------------------------------------------]]

local W, D, H = 11, 9, 27          -- pit footprint and how far the face rises
local SX, SZ  = 5, 4               -- station, well inside the ring
local COURSES = 24                 -- what scan.height should work out
local ROOF    = 27                 -- solid ceiling, so "roof" mode has a stop

--- Lay out a pit with a marker ring and a station platform.
--- Ring sits at y=0; turtles stand at y=1, one level above it.
local function buildQuarry(anchorX, anchorZ)
  local margin = 3
  for x = -margin, W - 1 + margin do
    for z = -margin, D - 1 + margin do
      mock.setBlock(x, -1, z, "minecraft:bedrock")
      if x < 0 or x >= W or z < 0 or z >= D then
        for y = 0, H - 1 do mock.setBlock(x, y, z, "minecraft:deepslate") end
      end
    end
  end

  local cells = {}
  for x = 0, W - 1 do
    for z = 0, D - 1 do
      if x == 0 or x == W - 1 or z == 0 or z == D - 1 then
        mock.setBlock(x, 0, z, "minecraft:glass")
        cells[#cells + 1] = { x = x, z = z }
      end
    end
  end
  mock.setBlock(anchorX, 0, anchorZ, "minecraft:sea_lantern")

  -- A ceiling over the whole pit: this is a hole dug underground, not one
  -- open to the sky, which is what "roof" mode measures against.
  for x = -margin, W - 1 + margin do
    for z = -margin, D - 1 + margin do
      mock.setBlock(x, ROOF, z, "minecraft:deepslate")
    end
  end

  mock.setBlock(SX, 0, SZ, "minecraft:glowstone")   -- station platform
  return cells
end

--- Put a turtle at (x, 1, z) facing `h`, with supply and fuel chests in front
--- of it -- fuel one block higher, as on the real station.
local function station(x, z, h)
  local DX = { [0] = 0, [1] = 1, [2] = 0, [3] = -1 }
  local DZ = { [0] = 1, [1] = 0, [2] = -1, [3] = 0 }
  local fx, fz = x + DX[h], z + DZ[h]

  mock.setBlock(fx, 1, fz, "minecraft:chest")
  mock.setBlock(fx, 2, fz, "minecraft:chest")

  mock.setChest({ side = "front", at = { x, 1, z }, heading = h,
                  infinite = M("cobbled_deepslate") })
  mock.setChest({ side = "front", at = { x, 2, z }, heading = h,
                  stacks = { { name = M("coal_block"), count = 64 } } })

  -- The floor under the turtle is a chest: crafting needs the turtle to be
  -- completely empty, so everything it carries goes in here meanwhile.
  mock.setBlock(x, 0, z, "minecraft:chest")
  mock.setChest({ side = "down", at = { x, 1, z }, stacks = {} })

  mock.setTurtle(x, 1, z, h)
  nav.setPos({ x = 0, y = 0, z = 0, h = 0 })
end

--- Turn a turtle-local ring cell into world coordinates.
local function toWorld(c, ox, oz, h)
  local DX = { [0] = 0, [1] = 1, [2] = 0, [3] = -1 }
  local DZ = { [0] = 1, [1] = 0, [2] = -1, [3] = 0 }
  local fx, fz = DX[h], DZ[h]
  local rx, rz = DX[(h + 1) % 4], DZ[(h + 1) % 4]
  return ox + c.x * rx + c.z * fx, oz + c.x * rz + c.z * fz
end

--[[--------------------------------------------------------------------------
  0. Lua 5.2 compatibility

  CC:Tweaked runs Lua 5.2. This harness runs a much newer Lua, so anything
  added in 5.3 or later compiles perfectly here and then fails on the turtle
  with a syntax error -- which is exactly what // integer division did, after
  560 green checks. A compile that passes here proves nothing about the
  version actually in the game, so the newer syntax is banned outright.
----------------------------------------------------------------------------]]

section("Lua 5.2 compatibility")

local SOURCES = { "config", "nav", "inv", "craft", "ring", "scan", "pattern",
                  "build", "report", "wall", "monitor", "crafttest", "frame" }

local FORBIDDEN = {
  { "//",              "integer division -- use math.floor" },
  { "<<",              "bit shift" },
  { ">>",              "bit shift" },
  { "math%.tointeger", "math.tointeger" },
  { "math%.type",      "math.type" },
  { "math%.ult",       "math.ult" },
  { "table%.move",     "table.move" },
}

--- Crude but adequate: block comments, then line comments.
local function stripComments(src)
  src = src:gsub("%-%-%[%[.-%]%]", " ")
  src = src:gsub("%-%-%[=%[.-%]=%]", " ")
  src = src:gsub("%-%-[^" .. string.char(10) .. "]*", " ")
  return src
end

for _, name in ipairs(SOURCES) do
  local path = "wall/" .. name .. ".lua"
  local fh = io.open(path, "r")
  if not fh then
    fail = fail + 1
    print("  FAIL: cannot read " .. path)
  else
    local code = stripComments(fh:read("*a"))
    fh:close()
    for _, rule in ipairs(FORBIDDEN) do
      local where = code:find(rule[1])
      if where then
        fail = fail + 1
        print(("  FAIL: %s uses %s"):format(path, rule[2]))
      else
        pass = pass + 1
      end
    end
  end
end

--[[--------------------------------------------------------------------------
  1. Recipes
----------------------------------------------------------------------------]]

section("raw cost per block")

eq(craft.rawCost(M("cobbled_deepslate")),  1, "cobbled deepslate")
eq(craft.rawCost(M("polished_deepslate")), 1, "polished deepslate")
eq(craft.rawCost(M("deepslate_tiles")),    1, "deepslate tiles")
eq(craft.rawCost(M("chiseled_deepslate")), 1, "chiseled deepslate")
eq(craft.rawCost(M("cobbled_deepslate_slab")),   0.5, "slab")
eq(craft.rawCost(M("cobbled_deepslate_stairs")), 1.5, "stairs")
ok(not craft.isReachable(M("granite")), "granite is not reachable")

--[[--------------------------------------------------------------------------
  2. Pattern
----------------------------------------------------------------------------]]

section("pattern layers")

local pat = {
  bottom    = { { block = "deepslate_tiles", height = 4 } },
  repeating = { { block = "cobbled_deepslate", height = 6 },
                { block = "polished_deepslate", height = 1 } },
  top       = { { block = "deepslate_bricks", height = 2 },
                { block = "chiseled_deepslate", height = 1 } },
}

local L = pattern.layers(pat, 20)
eq(#L, 20, "20 courses")
eq(L[1],  M("deepslate_tiles"),    "floor band")
eq(L[11], M("polished_deepslate"), "repeat accent")
eq(L[20], M("chiseled_deepslate"), "cap")

local V = pattern.layers(pat, 2)
eq(V[2], M("chiseled_deepslate"), "very shallow pit keeps the cap")

--[[--------------------------------------------------------------------------
  2b. The cycle actually configured in config.lua
----------------------------------------------------------------------------]]

section("the configured 21 course cycle")

-- Five course header, then eight alternating pairs.
local cycle = {
  "chiseled_deepslate",
  "polished_deepslate", "polished_deepslate", "polished_deepslate",
  "chiseled_deepslate",
}
for band = 1, 8 do
  local block = (band % 2 == 1) and "deepslate_tiles" or "deepslate_bricks"
  cycle[#cycle + 1] = block
  cycle[#cycle + 1] = block
end

eq(#cycle, 21, "the cycle is 21 courses tall")

local bands = 0
for i = 6, 21, 2 do
  if cycle[i] == cycle[i + 1] then bands = bands + 1 end
end
eq(bands, 8, "eight bands of two")

local C = pattern.layers(cfg.pattern, 65)
eq(#C, 65, "65 courses resolved")

local repeats = true
for i = 1, 65 do
  if C[i] ~= M(cycle[((i - 1) % 21) + 1]) then
    repeats = false
    if i <= 25 then
      print(("    course %d: got %s want %s")
            :format(i, tostring(C[i]), M(cycle[((i - 1) % 21) + 1])))
    end
  end
end
ok(repeats, "the cycle repeats exactly, course 22 back to chiseled")

for _, name in ipairs({ "chiseled_deepslate", "polished_deepslate",
                        "deepslate_tiles", "deepslate_bricks" }) do
  ok(craft.isReachable(M(name)), name .. " is craftable from cobbled deepslate")
  eq(craft.rawCost(M(name)), 1, name .. " costs one cobbled deepslate")
end

-- Four block types in one cycle, so a turtle whose band spans a cycle carries
-- leftovers of all four. Seven slots are usable while crafting.
local bandTypes = {}
for i = 1, 21 do bandTypes[C[i]] = true end
local n = 0
for _ in pairs(bandTypes) do n = n + 1 end
eq(n, 4, "a full cycle uses four distinct blocks")

--[[--------------------------------------------------------------------------
  2c. Staging a full batch
----------------------------------------------------------------------------]]

section("staging")

--- Put `n` of `name` on board, filling slots in order the way pullRaw does.
local function loadUp(name, n)
  for i = 1, 16 do mock.T.slots[i] = nil end
  local left, slot = n, 1
  while left > 0 and slot <= 16 do
    local put = math.min(64, left)
    mock.T.slots[slot] = { name = name, count = put }
    left, slot = left - put, slot + 1
  end
  turtle.select(1)
end

-- 232 cobbled deepslate lands as 64,64,64,40 across slots 1 to 4. Clearing the
-- grid then has to move a full stack into a slot with only part of a stack's
-- room -- which the turtle reports as a failure even though it moved what
-- fitted. Getting that wrong strands the turtle mid-stage.
loadUp(M("cobbled_deepslate"), 232)

local polished = craft.recipeFor(M("polished_deepslate"))
ok(polished ~= nil, "found the polished deepslate recipe")

if polished then
  local staged, serr = inv.stageOnly(craft.cells(polished), 58)
  ok(staged, "staged a full 232 block batch: " .. tostring(serr))

  if staged then
    local cellSlots = { [1] = true, [2] = true, [5] = true, [6] = true }
    local wrong = 0
    for slot = 1, 16 do
      local held = turtle.getItemCount(slot)
      if cellSlots[slot] then
        if held ~= 58 then wrong = wrong + 1 end
      elseif held > 0 then
        wrong = wrong + 1
      end
    end
    eq(wrong, 0, "58 in each of the four cells and nothing anywhere else")
  end
end

-- The same again at a size that needs no shuffling, as a control.
loadUp(M("cobbled_deepslate"), 16)
if polished then
  local small = inv.stageOnly(craft.cells(polished), 4)
  ok(small, "and a small batch stages too")
end

for i = 1, 16 do mock.T.slots[i] = nil end

--[[--------------------------------------------------------------------------
  3. Band splitting -- must tile with no gap and no overlap
----------------------------------------------------------------------------]]

section("band splitting")

local function checkTiling(courses, turtles)
  local covered, prevHi = {}, 0
  for i = 1, turtles do
    local lo, hi = build.band(courses, turtles, i)
    if lo <= hi then
      ok(lo == prevHi + 1,
         ("%d/%d turtle %d starts right after the last"):format(courses, turtles, i))
      prevHi = hi
      for c = lo, hi do
        ok(not covered[c], ("course %d covered once"):format(c))
        covered[c] = true
      end
    end
  end
  eq(prevHi, courses, ("%d courses over %d turtles reaches the top")
                      :format(courses, turtles))
end

checkTiling(118, 8)
checkTiling(120, 8)
checkTiling(24, 8)
checkTiling(7, 8)      -- more turtles than courses
checkTiling(100, 1)

local lo8, hi8 = build.band(118, 8, 3)
eq(lo8, 30, "118/8 turtle 3 starts at 30")
eq(hi8, 44, "118/8 turtle 3 ends at 44")

--[[--------------------------------------------------------------------------
  4. Point in polygon
----------------------------------------------------------------------------]]

section("inside test")

local square = {}
for x = 0, 4 do square[#square + 1] = { x = x, z = 0 } end
for z = 1, 4 do square[#square + 1] = { x = 4, z = z } end
for x = 3, 0, -1 do square[#square + 1] = { x = x, z = 4 } end
for z = 3, 1, -1 do square[#square + 1] = { x = 0, z = z } end

ok(build.isInside(square, 2, 2), "centre is inside")
ok(not build.isInside(square, -1, 2), "west of the ring is outside")
ok(not build.isInside(square, 5, 2), "east of the ring is outside")
ok(not build.isInside(square, 2, -1), "north of the ring is outside")
ok(not build.isInside(square, 2, 5), "south of the ring is outside")

--[[--------------------------------------------------------------------------
  5. Ring tracing
----------------------------------------------------------------------------]]

section("tracing the marker ring")

mock.reset()
local expected = buildQuarry(0, 0)
station(SX, SZ, 0)

local cells, terr = ring.survey(cfg.ring, { strict = true })      -- strict
ok(cells ~= nil, "traced the ring: " .. tostring(terr))

if cells then
  eq(#cells, #expected, "every ring cell found")
  eq(cells[1].kind, "anchor", "the list starts on the anchor block")

  local ax, az = toWorld(cells[1], SX, SZ, 0)
  eq(ax, 0, "anchor is at world x=0")
  eq(az, 0, "anchor is at world z=0")

  -- Every traced cell is a real ring cell, and no duplicates.
  local seen, wrong = {}, 0
  for _, c in ipairs(cells) do
    local wx, wz = toWorld(c, SX, SZ, 0)
    local key = wx .. "," .. wz
    if seen[key] then wrong = wrong + 1 end
    seen[key] = true
    local b = mock.getBlock(wx, 0, wz)
    if b ~= "minecraft:glass" and b ~= "minecraft:sea_lantern" then
      wrong = wrong + 1
    end
  end
  eq(wrong, 0, "all traced cells are ring blocks, none repeated")

  eq(nav.pos().x, 0, "back home in x after the trace")
  eq(nav.pos().z, 0, "back home in z after the trace")
end

--[[--------------------------------------------------------------------------
  5b. The free shape check
----------------------------------------------------------------------------]]

section("ring shape check")

local goodRing = {}
for x = 0, 4 do goodRing[#goodRing + 1] = { x = x, z = 0 } end
for z = 1, 4 do goodRing[#goodRing + 1] = { x = 4, z = z } end
for x = 3, 0, -1 do goodRing[#goodRing + 1] = { x = x, z = 4 } end
for z = 3, 1, -1 do goodRing[#goodRing + 1] = { x = 0, z = z } end

ok(ring.checkShape(goodRing), "a clean one-wide loop passes")

-- A cell hanging off the side makes one cell have three neighbours.
local fat = {}
for _, c in ipairs(goodRing) do fat[#fat + 1] = { x = c.x, z = c.z } end
fat[#fat + 1] = { x = 1, z = 1 }        -- touches (1,0) and (0,1)

local fatOk, fatErr = ring.checkShape(fat)
ok(not fatOk, "a two-wide patch is rejected")
ok(fatErr and fatErr:find("one block wide"),
   "and says what is wrong: " .. tostring(fatErr))

-- A repeated cell means the trace doubled back.
local dup = {}
for _, c in ipairs(goodRing) do dup[#dup + 1] = { x = c.x, z = c.z } end
dup[#dup + 1] = { x = 0, z = 0 }

local dupOk, dupErr = ring.checkShape(dup)
ok(not dupOk, "a repeated cell is rejected")
ok(dupErr and dupErr:find("twice"), "and says so: " .. tostring(dupErr))

-- The real traced ring passes it, which is what makes the slow physical
-- neighbour walk unnecessary.
if cells then
  ok(ring.checkShape(cells), "the traced quarry ring passes the shape check")
end

--[[--------------------------------------------------------------------------
  5c. Lining two turtles up from a shared ring
----------------------------------------------------------------------------]]

section("frame transforms")

local frame = require("frame")

--- Rewrite a cell list as another turtle standing at (ox,oz) facing `h` would
--- have traced it -- the inverse of what toWorld does.
local function asSeenFrom(cellList, wx, wz, ox, oz, h)
  local DXl = { [0] = 0, [1] = 1, [2] = 0, [3] = -1 }
  local DZl = { [0] = 1, [1] = 0, [2] = -1, [3] = 0 }
  local out = {}
  for i, c in ipairs(cellList) do
    -- world position of this cell
    local worldX = wx + c.x
    local worldZ = wz + c.z
    -- express it in the other turtle's frame
    local dx, dz = worldX - ox, worldZ - oz
    local fx, fz = DXl[h], DZl[h]
    local rx, rz = DXl[(h + 1) % 4], DZl[(h + 1) % 4]
    out[i] = { x = dx * rx + dz * rz, z = dx * fx + dz * fz, kind = c.kind }
  end
  return out
end

-- Two turtles, different places and facings, tracing the same physical ring.
mock.reset()
buildQuarry(0, 0)

station(SX, SZ, 0)
local frameA = ring.survey(cfg.ring)
ok(frameA ~= nil, "turtle A traced the ring")

mock.reset()
buildQuarry(0, 0)
station(3, 6, 1)
local frameB = ring.survey(cfg.ring)
ok(frameB ~= nil, "turtle B traced the ring")

if frameA and frameB then
  eq(#frameA, #frameB, "both traces are the same length")

  local t, terr = frame.derive(frameB, frameA)
  ok(t ~= nil, "a transform lines A onto B: " .. tostring(terr))

  if t then
    local mapped = frame.map(t, frameA)
    local wrongCell = 0
    for i = 1, #mapped do
      if mapped[i].x ~= frameB[i].x or mapped[i].z ~= frameB[i].z then
        wrongCell = wrongCell + 1
      end
    end
    eq(wrongCell, 0, "every one of A's cells lands on B's")

    -- And the same transform is what turns the scout's wall ring into B's
    -- numbers, which is the whole point.
    local flat = frame.flatten(frameA)
    eq(#flat, #frameA * 2, "flattening gives two numbers per cell")
    local back = frame.unflatten(flat)
    eq(#back, #frameA, "and unflattening gives them back")
    eq(back[1].kind, "anchor", "the anchor is still first")
  end
end

-- Traces of different rings must be refused, not fudged.
local shifted = {}
for i, c in ipairs(frameA or {}) do shifted[i] = { x = c.x, z = c.z } end
if #shifted > 2 then
  shifted[3] = { x = shifted[3].x + 5, z = shifted[3].z }
  local bad, badErr = frame.derive(frameA, shifted)
  ok(bad == nil, "a mismatched trace is refused")
  ok(badErr ~= nil, "and says so: " .. tostring(badErr))
end

--[[--------------------------------------------------------------------------
  5d. Remembering the ring
----------------------------------------------------------------------------]]

section("ring cache")

mock.reset()
buildQuarry(0, 0)
station(SX, SZ, 0)

ring.clearCache(cfg.ring)
local walked, fromCache = ring.survey(cfg.ring)
ok(walked ~= nil, "walked the ring the first time")
ok(not fromCache, "and did not claim it came from a cache")

local movesAfterWalk = mock.T.moves

station(SX, SZ, 0)
local remembered, wasCached = ring.survey(cfg.ring)
ok(remembered ~= nil, "got the ring the second time")
ok(wasCached, "and that time it came from the cache")

if walked and remembered then
  eq(#remembered, #walked, "the remembered ring is the same size")
  local differs = 0
  for i = 1, #walked do
    if remembered[i].x ~= walked[i].x or remembered[i].z ~= walked[i].z then
      differs = differs + 1
    end
  end
  eq(differs, 0, "and cell for cell identical")
end

-- A ring worked out from someone else's trace is just as good, and saving it
-- is what stops a turtle walking the perimeter on its next resume.
mock.reset()
buildQuarry(0, 0)
station(SX, SZ, 0)
ring.clearCache(cfg.ring)

local derived = ring.survey(cfg.ring)
ring.clearCache(cfg.ring)
ring.remember(cfg.ring, derived)

station(SX, SZ, 0)
local recalled, recalledCached = ring.survey(cfg.ring)
ok(recalledCached, "a remembered ring is used without walking it")
eq(recalled and #recalled or 0, #derived, "and is the right size")

--[[--------------------------------------------------------------------------
  6. Different turtles, different places, same ring
----------------------------------------------------------------------------]]

section("all turtles agree on the ring")

local reference

for _, setup in ipairs({ { SX, SZ, 0 }, { 3, 6, 1 }, { 7, 2, 2 }, { 2, 2, 3 } }) do
  mock.reset()
  buildQuarry(0, 0)
  station(setup[1], setup[2], setup[3])

  local c, err = ring.survey(cfg.ring)
  ok(c ~= nil, ("turtle at %d,%d facing %d traced it: %s")
               :format(setup[1], setup[2], setup[3], tostring(err)))

  if c then
    local world = {}
    for i, cell in ipairs(c) do
      local wx, wz = toWorld(cell, setup[1], setup[2], setup[3])
      world[i] = wx .. "," .. wz
    end

    if not reference then
      reference = world
    else
      local same = #world == #reference
      if same then
        for i = 1, #world do
          if world[i] ~= reference[i] then same = false break end
        end
      end
      ok(same, ("turtle at %d,%d facing %d produced an identical cell list")
               :format(setup[1], setup[2], setup[3]))
    end
  end
end

--[[--------------------------------------------------------------------------
  7. Height
----------------------------------------------------------------------------]]

section("height")

mock.reset()
buildQuarry(0, 0)
station(SX, SZ, 0)

local hcells = ring.survey(cfg.ring)

-- Roof mode: climb until the ceiling stops us. Turtle level is world y=1 and
-- the ceiling is at ROOF, so the topmost occupiable level is ROOF-1.
cfg.height.stopAt = "roof"
local courses, herr = scan.height(cfg, hcells)
ok(courses ~= nil, "measured a height against the roof: " .. tostring(herr))
eq(courses, ROOF - 1 - 1 - scan.baseY(cfg) + 1, "roof mode course count")
eq(scan.baseY(cfg), cfg.wall.aboveRing - 1, "base sits just above the gap")

-- A cave in the pit face must not shorten a roof-mode climb; only the ceiling
-- stops it. Punch a hole in one corner column and re-measure.
for y = 10, 14 do
  mock.setBlock(W, y, 0, nil)
  mock.setBlock(W - 1, y, -1, nil)
end
local caved = scan.height(cfg, hcells)
eq(caved, courses, "a cave in the face does not fool roof mode")

-- Once some of the wall is standing, the climb hits that rather than the
-- ceiling. Measuring the pit against our own wall gives nonsense, so it falls
-- back on the configured height and says why.
local wallY = 1 + scan.baseY(cfg)
for _, c in ipairs(hcells) do
  mock.setBlock(c.x + SX, wallY, c.z + SZ, M("deepslate_tiles"))
end

local blockedH, blockedNote = scan.height(cfg, hcells)
eq(blockedH, cfg.height.suggest, "falls back on the configured height")
ok(blockedNote and blockedNote:find("already built"),
   "and says why: " .. tostring(blockedNote))

for _, c in ipairs(hcells) do
  mock.setBlock(c.x + SX, wallY, c.z + SZ, nil)
end

-- Rim mode still works where there is genuinely open sky.
mock.reset()
buildQuarry(0, 0)
for x = -3, W + 2 do
  for z = -3, D + 2 do mock.setBlock(x, ROOF, z, nil) end   -- take the roof off
end
station(SX, SZ, 0)
local rimCells = ring.survey(cfg.ring)
cfg.height.stopAt = "rim"
local rimCourses, rimErr = scan.height(cfg, rimCells)
ok(rimCourses ~= nil, "rim mode measures an open pit: " .. tostring(rimErr))
eq(rimCourses, COURSES, "rim mode course count matches the pit face")

cfg.height.stopAt = "roof"

--[[--------------------------------------------------------------------------
  8. Eight turtles building the whole wall
----------------------------------------------------------------------------]]

section("eight turtles, one wall")

mock.reset()
local ringCells = buildQuarry(0, 0)

-- A floating build in the middle that must be left alone.
local floating = {}
for x = 4, 5 do
  for y = 8, 9 do
    for z = 3, 4 do
      mock.setBlock(x, y, z, "minecraft:oak_planks")
      floating[#floating + 1] = { x, y, z }
    end
  end
end

-- Something already standing in a wall cell, and a block sitting directly
-- above another one so the sideways fallback has to be used.
mock.setBlock(0, 6, 3, "minecraft:mossy_cobblestone")
mock.setBlock(0, 8, 5, "minecraft:mossy_cobblestone")

build.clearHoles()

local TURTLES = 8
local layers  = pattern.layers(cfg.pattern, COURSES)
local base    = scan.baseY(cfg)
local totals  = { placed = 0, skipped = 0, missed = 0 }
local allOk   = true

for i = 1, TURTLES do
  station(SX, SZ, 0)
  local c = ring.survey(cfg.ring)
  local from, to = build.band(COURSES, TURTLES, i)
  local meta = { courses = COURSES, turtles = TURTLES, turtle = i }

  local done, result = build.run(cfg, c, layers, from, to, 1, meta)
  if not done then
    allOk = false
    print(("  turtle %d failed: %s"):format(i, tostring(result)))
  else
    totals.placed  = totals.placed  + result.placed
    totals.skipped = totals.skipped + result.skipped
    totals.missed  = totals.missed  + result.missed
  end
end

ok(allOk, "all eight turtles finished")
print(("  placed %d, skipped %d, missed %d")
      :format(totals.placed, totals.skipped, totals.missed))

eq(totals.missed, 0, "no cell was unreachable")
eq(totals.skipped, 2, "exactly the two pre-existing blocks were skipped")
eq(totals.placed, #ringCells * COURSES - 2, "every other cell filled")

-- Every ring cell on every course holds the right block.
local wrong = 0
for course = 1, COURSES do
  local wy = 1 + base + (course - 1)      -- turtle level is world y=1
  for _, c in ipairs(ringCells) do
    local got  = mock.getBlock(c.x, wy, c.z)
    local want = layers[course]
    if (c.x == 0 and wy == 6 and c.z == 3)
    or (c.x == 0 and wy == 8 and c.z == 5) then
      want = "minecraft:mossy_cobblestone"
    end
    if got ~= want then
      wrong = wrong + 1
      if wrong <= 3 then
        print(("    at %d,%d,%d got %s want %s")
              :format(c.x, wy, c.z, tostring(got), tostring(want)))
      end
    end
  end
end
eq(wrong, 0, "the whole wall is correct, course by course")

-- Nothing was broken and nothing strayed inside.
local intact = true
for _, p in ipairs(floating) do
  if mock.getBlock(p[1], p[2], p[3]) ~= "minecraft:oak_planks" then intact = false end
end
ok(intact, "the floating build is untouched")

local strayed = 0
for x = 1, W - 2 do
  for z = 1, D - 2 do
    for y = 1, H - 1 do
      local b = mock.getBlock(x, y, z)
      if b and b ~= "minecraft:oak_planks" and b ~= "minecraft:chest" then
        strayed = strayed + 1
      end
    end
  end
end
eq(strayed, 0, "nothing was placed inside the pit")

-- The working gap under the base is still open.
local gapOpen = true
for y = 1, base do
  for _, c in ipairs(ringCells) do
    if mock.getBlock(c.x, y, c.z) then gapOpen = false end
  end
end
ok(gapOpen, "the gap under the wall base was left open")

--[[--------------------------------------------------------------------------
  8b. The hole log
----------------------------------------------------------------------------]]

section("the hole log")

ok(fs.exists(build.holesFile()), "a hole log was written")

if fs.exists(build.holesFile()) then
  local f = fs.open(build.holesFile(), "r")
  local text = f.readAll()
  f.close()

  local lines = {}
  for line in text:gmatch("[^\n]+") do
    if line:find("cell") then lines[#lines + 1] = line end
  end

  eq(#lines, 2, "one entry per skipped block")
  for _, l in ipairs(lines) do print("  " .. l) end

  -- The two blocks sit at world y=6 and y=8. Turtle level is y=1 and the base
  -- is 2 above that, so they are courses 4 and 6 -- and 6 and 8 above the ring.
  local text4 = text:find("course 4") ~= nil
  local text6 = text:find("course 6") ~= nil
  ok(text4, "the block at world y=6 is logged as course 4")
  ok(text6, "the block at world y=8 is logged as course 6")
  ok(text:find("ring%+6") ~= nil, "and as 6 blocks above the marker ring")
  ok(text:find("ring%+8") ~= nil, "and as 8 blocks above the marker ring")
  ok(text:find("occupied") ~= nil, "logged as occupied rather than unreachable")
  ok(text:find("UNREACHABLE") == nil, "nothing was unreachable")

  -- The cell index has to be findable by counting round the ring, so it must
  -- be within range and point at the right physical block.
  local idx = tonumber(lines[1]:match("cell (%d+)/"))
  ok(idx and idx >= 1 and idx <= #ringCells,
     "the cell index is within the ring")
end

--[[--------------------------------------------------------------------------
  9. Sealing the gap
----------------------------------------------------------------------------]]

section("sealing the gap under the base")

station(SX, SZ, 0)
local scells = ring.survey(cfg.ring)
local sdone, sres = build.seal(cfg, scells, M("deepslate_tiles"))
ok(sdone, "seal finished: " .. tostring(sres))

if sdone then
  print(("  placed %d, already solid %d, missed %d")
        :format(sres.placed, sres.skipped, sres.missed))
  local filled = 0
  for y = 1, base do
    for _, c in ipairs(ringCells) do
      if mock.getBlock(c.x, y, c.z) == M("deepslate_tiles") then
        filled = filled + 1
      end
    end
  end
  eq(filled, #ringCells * base, "the whole gap is now filled")
end

--[[--------------------------------------------------------------------------
  10. Resume
----------------------------------------------------------------------------]]

section("resume from a saved position")

mock.reset()
local rcells = buildQuarry(0, 0)
station(SX, SZ, 0)

local rc = ring.survey(cfg.ring)
local rlayers = pattern.layers(cfg.pattern, COURSES)
local RFROM, RTO, RIDX = 5, 8, 10
local meta = { courses = COURSES, turtles = TURTLES, turtle = 2 }

local rdone, rres = build.run(cfg, rc, rlayers, RFROM, RTO, RIDX, meta)
ok(rdone, "resumed run finished: " .. tostring(rres))

if rdone then
  local expectedPlaced = (#rc - RIDX + 1) + #rc * (RTO - RFROM)
  eq(rres.placed, expectedPlaced, "placed exactly from the resume point on")

  local early = 0
  for _, c in ipairs(rcells) do
    if mock.getBlock(c.x, 1 + base + (RFROM - 1) - 1, c.z) then early = early + 1 end
  end
  eq(early, 0, "the course below the resume point was left alone")

  local before = 0
  for i = 1, RIDX - 1 do
    local c = rc[i]
    local wx, wz = toWorld(c, SX, SZ, 0)
    if mock.getBlock(wx, 1 + base + (RFROM - 1), wz) then before = before + 1 end
  end
  eq(before, 0, "cells before the resume index were left alone")
end

ok(not fs.exists("wall_state.txt"), "state file cleared after success")

--[[--------------------------------------------------------------------------
  10b. Progress reporting over rednet
----------------------------------------------------------------------------]]

section("progress reporting")

-- With no modem fitted, reporting must stay off and change nothing.
mock.setModem(nil)
mock.clearSent()
report.close()
ok(not report.open(cfg), "no modem, so reporting stays off")

mock.reset()
local rr = buildQuarry(0, 0)
station(SX, SZ, 0)
local rcells0 = ring.survey(cfg.ring)
build.run(cfg, rcells0, pattern.layers(cfg.pattern, 4), 1, 2, 1,
          { courses = 4, turtles = 1, turtle = 1 })
eq(#mock.sent(), 0, "a turtle with no modem broadcasts nothing")

-- Now fit one and check what comes out.
mock.setModem("right")
mock.clearSent()
report.close()
ok(report.open(cfg), "a modem is found and rednet opened")

report.identify({ turtle = 3, turtles = 8, from = 30, to = 44, courses = 118 })

mock.reset()
local rr2 = buildQuarry(0, 0)
mock.setBlock(0, 6, 3, "minecraft:mossy_cobblestone")   -- one deliberate hole
station(SX, SZ, 0)
local rcells = ring.survey(cfg.ring)

build.run(cfg, rcells, pattern.layers(cfg.pattern, 6), 1, 5, 1,
          { courses = 6, turtles = 1, turtle = 3, fresh = true })

local msgs = mock.sent()
ok(#msgs > 0, "the turtle broadcast something")

local kinds, states = {}, {}
local hole, status
for _, m in ipairs(msgs) do
  eq(m.protocol, "wall", "sent on the wall protocol")
  kinds[m.msg.kind] = (kinds[m.msg.kind] or 0) + 1
  if m.msg.state then states[m.msg.state] = true end
  if m.msg.kind == "hole" and not hole then hole = m.msg end
  if m.msg.kind == "status" and not status then status = m.msg end
end

ok(kinds.status and kinds.status > 0, "status messages were sent")
eq(kinds.hole, 1, "exactly one hole message, for the one obstruction")

ok(states.building, "reported that it was building")
ok(states.restocking, "reported when it went to restock")
ok(states.done, "reported when it finished")

if status then
  eq(status.turtle, 3, "status carries the turtle index")
  eq(status.turtles, 8, "status carries the turtle count")
  eq(status.from, 30, "status carries the band start")
  eq(status.to, 44, "status carries the band end")
  eq(status.courses, 118, "status carries the total course count")
  ok(status.placed ~= nil, "status carries a placed count")
  ok(status.fuel ~= nil, "status carries the fuel level")
end

if hole then
  eq(hole.turtle, 3, "the hole names the turtle that found it")
  eq(hole.course, 4, "the hole is on course 4")
  eq(hole.height, 6, "the hole is 6 above the ring")
  eq(hole.reason, "occupied", "the hole is occupied, not unreachable")
  ok(hole.cell and hole.cell >= 1 and hole.cell <= #rcells,
     "the hole has a cell index within the ring")
  eq(hole.cells, #rcells, "the hole says how big the ring is")
end

-- Rate limiting: far fewer messages than blocks placed.
local placedBlocks = #rcells * 5 - 1
ok(kinds.status < placedBlocks / 4,
   ("status is rate limited (%d messages for %d blocks)")
   :format(kinds.status or 0, placedBlocks))

mock.setModem(nil)
report.close()


--[[--------------------------------------------------------------------------
  10c. Enlisting and being assigned a slot
----------------------------------------------------------------------------]]

section("enlist and assign")

mock.setModem("right")
report.close()
report.open(cfg)
mock.clearSent()
mock.clearEvents()

-- The monitor answers straight away.
mock.pushEvent("rednet_message", 1,
               { kind = "assign", to = 7, index = 3, turtles = 8,
                 courses = 118 }, "wall")

local assign, aerr = report.awaitAssignment()
ok(assign ~= nil, "got an assignment: " .. tostring(aerr))

if assign then
  eq(assign.index, 3, "assignment carries the slot index")
  eq(assign.turtles, 8, "assignment carries the turtle count")
  eq(assign.courses, 118, "assignment carries the course count")
end

local enlists = 0
for _, m in ipairs(mock.sent()) do
  if m.msg.kind == "enlist" then
    enlists = enlists + 1
    eq(m.msg.id, 7, "the enlist names this computer's id")
  end
end
ok(enlists >= 1, "it announced itself before waiting")

-- An assignment meant for another turtle is ignored.
mock.clearSent()
mock.clearEvents()
mock.pushEvent("rednet_message", 1,
               { kind = "assign", to = 99, index = 1, turtles = 8,
                 courses = 118 }, "wall")
mock.pushEvent("rednet_message", 1,
               { kind = "assign", to = 7, index = 5, turtles = 8,
                 courses = 118 }, "wall")

local mine = report.awaitAssignment()
ok(mine ~= nil and mine.index == 5,
   "an assignment addressed to another turtle is ignored")

-- Re-announces on the timer rather than going quiet.
mock.clearSent()
mock.clearEvents()
mock.pushEvent("timer", 1)
mock.pushEvent("rednet_message", 1,
               { kind = "assign", to = 7, index = 2, turtles = 8,
                 courses = 118 }, "wall")

local ticks = 0
report.awaitAssignment(function() ticks = ticks + 1 end)
eq(ticks, 1, "it re-announces while waiting")

local reannounced = 0
for _, m in ipairs(mock.sent()) do
  if m.msg.kind == "enlist" then reannounced = reannounced + 1 end
end
ok(reannounced >= 2, "and shouts again rather than waiting silently")

mock.setModem(nil)
report.close()
mock.clearEvents()

--[[--------------------------------------------------------------------------
  11. Guards
----------------------------------------------------------------------------]]

section("guards")

-- Terminated out on the ring and restarted there: the supply chest is not
-- where the turtle thinks it is, and it must say so before placing anything.
mock.reset()
local gcells = buildQuarry(0, 0)
station(SX, SZ, 0)

local atHome, aerr = build.checkStation(cfg)
ok(atHome, "at the station, the supply chest is found: " .. tostring(aerr))

-- Same world, but the turtle believes a ring cell is its origin.
mock.setTurtle(0, 1, 4, 0)
nav.setPos({ x = 0, y = 0, z = 0, h = 0 })

local astray, serr = build.checkStation(cfg)
ok(not astray, "away from the station, it notices")
ok(serr and serr:find("break it and place it again"),
   "and says how to recover: " .. tostring(serr))

-- A turtle handed no fuel cannot reach a fuel chest that needs a move.
mock.reset()
buildQuarry(0, 0)
station(SX, SZ, 0)
mock.T.fuel = 0

local fok, ferr = build.refuel(cfg)
ok(not fok, "a turtle with no fuel at all reports rather than stalling")
ok(ferr and ferr:find("straight into the turtle"),
   "and says how to get it started: " .. tostring(ferr))

-- With a little fuel on board it bootstraps itself off the chest.
mock.reset()
buildQuarry(0, 0)
station(SX, SZ, 0)
mock.T.fuel = 0
mock.T.slots[1] = { name = M("coal_block"), count = 2 }

fok, ferr = build.refuel(cfg)
ok(fok, "a coal block in the inventory is enough to start: " .. tostring(ferr))
ok(turtle.getFuelLevel() >= cfg.fuel.reserve, "and it fuelled up properly")

-- Surplus fuel must not ride along: it would sit in a slot while the turtle
-- tries to craft, which is exactly what broke the first real run.
local leftOver = 0
for _, s in ipairs(inv.ALL) do
  local n = inv.nameAt(s)
  if n == M("coal_block") or n == M("coal") then
    leftOver = leftOver + turtle.getItemCount(s)
  end
end
eq(leftOver, 0, "no fuel is left in the inventory after refuelling")

mock.T.fuel = 100000

local onRing = {}
for _, c in ipairs(square) do onRing[#onRing + 1] = c end
local bad, berr = build.run(cfg, onRing, { M("cobbled_deepslate") }, 1, 1, 1,
                            { courses = 1, turtles = 1, turtle = 1 })
ok(not bad, "refuses to build with the station on the ring")
ok(berr and berr:find("marker ring"), "and says why: " .. tostring(berr))

--[[--------------------------------------------------------------------------
  12. Command line
----------------------------------------------------------------------------]]

section("wall.lua command line")

mock.reset()
buildQuarry(0, 0)
station(SX, SZ, 0)

local chunk, lerr = loadfile("wall/wall.lua")
ok(chunk ~= nil, "wall.lua compiles: " .. tostring(lerr))

if chunk then
  local ran, rerr = pcall(chunk, "check")
  ok(ran, "wall check runs: " .. tostring(rerr))
  ran, rerr = pcall(chunk, "help")
  ok(ran, "wall help runs: " .. tostring(rerr))

  -- Actually drive a build through the front end. `check` and `help` touch
  -- almost nothing, and once missed a local named `report` shadowing the
  -- module of the same name -- which broke every command that reports.
  mock.reset()
  local cliRing = buildQuarry(0, 0)
  station(SX, SZ, 0)
  mock.setModem(nil)

  local built, berr2 = pcall(chunk, "build", "1", "1", "3", "-y")
  ok(built, "wall build runs end to end: " .. tostring(berr2))

  if built then
    local base = scan.baseY(cfg)
    local placedCells = 0
    for course = 1, 3 do
      for _, c in ipairs(cliRing) do
        if mock.getBlock(c.x, 1 + base + (course - 1), c.z) then
          placedCells = placedCells + 1
        end
      end
    end
    eq(placedCells, #cliRing * 3, "and placed the whole three course wall")
  end

  -- With no modem, join must bow out cleanly. A crash here reads as a Lua
  -- error message; a clean exit via die() carries an empty one.
  local joined, jerr = pcall(chunk, "join")
  ok(not joined and (jerr == "" or jerr == nil),
     "wall join without a modem exits cleanly: " .. tostring(jerr))
end

local mchunk, merr = loadfile("wall/monitor.lua")
ok(mchunk ~= nil, "monitor.lua compiles: " .. tostring(merr))

if mchunk then
  -- No modem attached: it should say so and return rather than throw.
  mock.setModem(nil)
  local ran, rerr = pcall(mchunk, "wall")
  ok(ran, "monitor exits cleanly with no modem: " .. tostring(rerr))
end

--[[--------------------------------------------------------------------------
  13. The single-file installer
----------------------------------------------------------------------------]]

section("install.lua")

local ichunk, ierr = loadfile("install.lua")
ok(ichunk ~= nil, "install.lua compiles: " .. tostring(ierr))

if ichunk then
  -- Wipe anything the earlier tests left, then unpack for real.
  for _, name in ipairs({ "config", "nav", "inv", "craft", "ring", "scan",
                          "pattern", "build", "report", "wall", "monitor",
                          "frame" }) do
    fs.delete("wall/" .. name .. ".lua")
  end

  local ran, rerr = pcall(ichunk)
  ok(ran, "install runs: " .. tostring(rerr))

  local checked, mismatched = 0, 0
  for _, name in ipairs({ "config", "nav", "inv", "craft", "ring", "scan",
                          "pattern", "build", "report", "wall", "monitor",
                          "frame" }) do
    local path = "wall/" .. name .. ".lua"

    if not fs.exists(path) then
      fail = fail + 1
      print("  FAIL: " .. path .. " was not written")
    else
      -- Compare against the real file on disk, through plain Lua io rather
      -- than the mock filesystem.
      local real = io.open(path, "rb")
      local want = real and real:read("*a") or nil
      if real then real:close() end

      local h = fs.open(path, "r")
      local got = h.readAll()
      h.close()

      checked = checked + 1

      -- Compare the bodies, ignoring line-ending style and any trailing
      -- blank lines. chr(13) rather than an escape, to keep this readable.
      local CR = string.char(13)
      local a = got:gsub(CR, ""):gsub("%s+$", "")
      local b = (want or ""):gsub(CR, ""):gsub("%s+$", "")

      if a ~= b then
        mismatched = mismatched + 1
        print(("  FAIL: %s differs (%d unpacked, %d on disk)")
              :format(path, #got, #(want or "")))
      end
    end
  end

  eq(checked, 12, "all twelve source files unpacked")
  eq(mismatched, 0, "every unpacked file matches its source exactly")

  -- A reinstall must not clobber an edited config.
  local cf = fs.open("wall/config.lua", "w")
  cf.write("-- my edits")
  cf.close()

  pcall(ichunk)

  local after = fs.open("wall/config.lua", "r")
  local kept = after.readAll()
  after.close()
  ok(kept:find("my edits") ~= nil,
     "reinstalling leaves an edited config.lua alone")
end

--[[--------------------------------------------------------------------------
----------------------------------------------------------------------------]]

print("")
print(("%d passed, %d failed"):format(pass, fail))
if fail > 0 then os.exit(1) end
