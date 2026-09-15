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

local cells, terr = ring.survey(cfg, true)      -- strict
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
  6. Different turtles, different places, same ring
----------------------------------------------------------------------------]]

section("all turtles agree on the ring")

local reference

for _, setup in ipairs({ { SX, SZ, 0 }, { 3, 6, 1 }, { 7, 2, 2 }, { 2, 2, 3 } }) do
  mock.reset()
  buildQuarry(0, 0)
  station(setup[1], setup[2], setup[3])

  local c, err = ring.survey(cfg, false)
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

local hcells = ring.survey(cfg, false)
local courses, herr = scan.height(cfg, hcells)
ok(courses ~= nil, "measured a height: " .. tostring(herr))
eq(courses, COURSES, "course count matches the pit")
eq(scan.baseY(cfg), cfg.wall.aboveRing - 1, "base sits just above the gap")

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
  local c = ring.survey(cfg, false)
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
local scells = ring.survey(cfg, false)
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

local rc = ring.survey(cfg, false)
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
local rcells0 = ring.survey(cfg, false)
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
local rcells = ring.survey(cfg, false)

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
  11. Guards
----------------------------------------------------------------------------]]

section("guards")

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
                          "pattern", "build", "report", "wall", "monitor" }) do
    fs.delete("wall/" .. name .. ".lua")
  end

  local ran, rerr = pcall(ichunk)
  ok(ran, "install runs: " .. tostring(rerr))

  local checked, mismatched = 0, 0
  for _, name in ipairs({ "config", "nav", "inv", "craft", "ring", "scan",
                          "pattern", "build", "report", "wall", "monitor" }) do
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

  eq(checked, 11, "all eleven files unpacked")
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
