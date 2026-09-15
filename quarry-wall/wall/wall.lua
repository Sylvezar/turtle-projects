--[[--------------------------------------------------------------------------
  wall -- a survival //walls for a quarry pit.

    wall check                    check config.lua and the turtle. Moves nothing.
    wall scan                     trace the ring and measure. Places nothing.
    wall build [n] [i] [courses]  build this turtle's share.
    wall resume                   carry on from an interrupted run.
    wall seal [courses]           fill the gap under the wall's base.

  The same files go on every turtle. How many turtles there are, which one
  this is, and how tall the wall should be are asked at launch, so nothing
  needs editing between turtles.

  Put each turtle on the station platform facing the chests, with the marker
  ring laid one level below turtle height around the pit edge.
----------------------------------------------------------------------------]]

local here = fs.getDir(shell.getRunningProgram())
package.path = here .. "/?.lua;" .. package.path

local cfg     = require("config")
local nav     = require("nav")
local inv     = require("inv")
local craft   = require("craft")
local ring    = require("ring")
local scan    = require("scan")
local pattern = require("pattern")
local build   = require("build")
local report  = require("report")
local frame   = require("frame")

local function shortName(n) return (n:gsub("^minecraft:", "")) end

local function die(msg)
  printError("wall: " .. tostring(msg))
  error("", 0)
end

--[[--------------------------------------------------------------------------
  Prompts
----------------------------------------------------------------------------]]

local function askInt(label, lo, hi, default)
  while true do
    if default then
      write(("%s [%d]: "):format(label, default))
    else
      write(("%s: "):format(label))
    end

    local line = read()
    if line == "" and default then return default end

    local n = tonumber(line)
    if n and n == math.floor(n) and n >= lo and (not hi or n <= hi) then
      return n
    end

    if hi then
      printError(("  enter a whole number from %d to %d"):format(lo, hi))
    else
      printError(("  enter a whole number of at least %d"):format(lo))
    end
  end
end

local function confirm(question)
  write(question .. " (y/N) ")
  return read():lower():sub(1, 1) == "y"
end

--[[--------------------------------------------------------------------------
  Preflight -- everything checkable without moving a block
----------------------------------------------------------------------------]]

local function preflight(layers)
  local problems, needsCrafting = {}, false
  local seen = {}

  for _, name in ipairs(layers) do
    if not seen[name] then
      seen[name] = true
      if not craft.isReachable(name) then
        problems[#problems + 1] =
          shortName(name) .. " cannot be made from cobbled deepslate"
      elseif name ~= craft.RAW then
        needsCrafting = true
      end
    end
  end

  if needsCrafting and not turtle.craft then
    problems[#problems + 1] =
      "this pattern needs crafting, but the turtle has no crafting table "
      .. "upgrade -- use a Crafty Turtle, or a pattern of plain cobbled "
      .. "deepslate only"
  end

  return problems, needsCrafting
end

local function reportBands(layers, from, to, perLayer)
  local blocks = 0

  print("")
  for _, b in ipairs(pattern.bands(layers)) do
    local lo = math.max(b.from, from)
    local hi = math.min(b.to, to)
    if lo <= hi then
      local n = (hi - lo + 1) * perLayer
      blocks = blocks + n
      if lo == hi then
        print(("  %3d      %-22s %6d"):format(lo, shortName(b.block), n))
      else
        print(("  %3d-%-3d  %-22s %6d"):format(lo, hi, shortName(b.block), n))
      end
    end
  end

  local raw = 0
  for i = from, to do raw = raw + craft.rawCost(layers[i]) * perLayer end

  print(("  %-31s %6d  (%d cobbled, %.0f stacks)")
        :format("TOTAL", blocks, math.ceil(raw), math.ceil(raw) / 64))

  return blocks
end

--[[--------------------------------------------------------------------------
  Commands
----------------------------------------------------------------------------]]

--- Final tally, pointing at the hole log when there is anything in it.
--- NOT called `report`: that is the module required at the top of this file,
--- and a local of the same name shadows it for everything below.
local function summarise(result)
  print("")
  print(("Done. %d placed, %d already occupied and left alone, %d missed.")
        :format(result.placed, result.skipped, result.missed))

  local holes = result.skipped + result.missed
  if holes > 0 then
    print(("%d gaps listed in %s."):format(holes, build.holesFile()))
    if result.missed > 0 then
      printError(("%d were UNREACHABLE -- boxed in on every side. Check those.")
                 :format(result.missed))
    end
  end
end

local cmd = {}

function cmd.check()
  local layers, err = pattern.layers(cfg.pattern, cfg.height.suggest)
  if not layers then die(err) end

  local problems, needsCrafting = preflight(layers)

  -- Written by the installer, so a turtle can say which build it is running
  -- without reinstalling to find out.
  local hasVersion, version = pcall(require, "version")
  if hasVersion and type(version) == "table" then
    print(("Build:     %s  (%s)"):format(tostring(version.build),
                                         tostring(version.made)))
  else
    print("Build:     unknown (installed by hand?)")
  end

  print(("Fuel:      %s"):format(tostring(turtle.getFuelLevel())))
  print(("Crafting:  %s"):format(
    turtle.craft and "crafting table fitted"
                  or (needsCrafting and "MISSING" or "not needed")))
  print(("Ring:      %s, anchored on %s")
        :format(cfg.ring.block, cfg.ring.anchor))
  print(("Base:      %d above the ring"):format(cfg.wall.aboveRing))
  print(("Overflow:  %s"):format(cfg.station.overflow and "configured"
                                 or "none (leftovers stay on board)"))

  print("")
  if #problems == 0 then
    print("Pattern is buildable from cobbled deepslate.")
  else
    for _, p in ipairs(problems) do printError("  " .. p) end
  end
end

function cmd.scan(args)
  -- The shape of the ring is verified from the traced list for free, so the
  -- exhaustive version -- which steps into every neighbour of every cell, and
  -- takes minutes -- is opt-in rather than the default.
  local strict = false
  for _, a in ipairs(args or {}) do
    if a == "--strict" then strict = true end
  end

  print("Looking for the marker ring...")
  if strict then print("(strict: checking every neighbour, this is slow)") end

  local ok, ferr = build.refuel(cfg)
  if not ok then die(ferr) end

  local cells, err = ring.survey(cfg.ring, { strict = strict })
  if not cells then die(err) end

  local d = ring.describe(cells)
  print("")
  print(("Ring:      %d cells, %d x %d bounding box")
        :format(d.count, d.width, d.depth))
  print(("Anchor:    %d,%d relative to this turtle"):format(d.anchor.x, d.anchor.z))

  if ring.contains(cells, 0, 0) then
    printError("The station is ON the ring. Move it inside the pit.")
  end

  print("Measuring height...")
  local courses, herr = scan.height(cfg, cells)
  if not courses then die(herr) end
  if herr then printError("note: " .. herr) end

  print("")
  print(("Courses:   %d  (base sits %d above the ring)")
        :format(courses, cfg.wall.aboveRing))
  print(("Wall:      %d blocks in total"):format(courses * d.count))
  print("")
  print("Give this course count to EVERY turtle -- they must all agree or")
  print("their slices will not line up.")
  print("")
  print("Nothing was placed.")
end

local function gather(args)
  local turtles = tonumber(args[1])
  local index   = tonumber(args[2])
  local courses = tonumber(args[3])

  if not turtles then turtles = askInt("How many turtles", 1) end
  if not index   then index   = askInt("Which one is this", 1, turtles) end
  if not courses then
    courses = askInt("How many courses tall", 1, nil, cfg.height.suggest)
  end

  if index > turtles then die("index " .. index .. " is above the turtle count") end
  return turtles, index, courses
end

--- Trace the ring, resolve the pattern, and lay this turtle's share. Shared
--- by `build` (numbers typed in) and `join` (numbers handed over by radio).
local function runBuild(turtles, index, courses, yes, known)
  local at, aerr = build.checkStation(cfg)
  if not at then die(aerr) end

  report.identify({ turtle = index, turtles = turtles, courses = courses })

  local cells = known
  if not cells then
    -- Say so before tracing, not after. Tracing is a full lap of the ring and
    -- the turtle was previously silent throughout, so the monitor could not
    -- tell a turtle working from one that had died.
    report.now({ state = "tracing" })
    print("Tracing the marker ring...")

    local err
    cells, err = ring.survey(cfg.ring)
    if not cells then die(err) end
  end

  local d = ring.describe(cells)
  report.now({ state = "traced", cells = d.count })
  print(("  %d cells, anchored at %d,%d"):format(d.count, d.anchor.x, d.anchor.z))

  local layers, perr = pattern.layers(cfg.pattern, courses)
  if not layers then die(perr) end

  local problems = preflight(layers)
  if #problems > 0 then
    for _, p in ipairs(problems) do printError("  " .. p) end
    die("fix config.lua and try again")
  end

  local from, to = build.band(courses, turtles, index)
  if from > to then
    die(("turtle %d of %d has no courses -- more turtles than courses")
        :format(index, turtles))
  end

  print("")
  print(("Turtle %d of %d -- courses %d to %d of %d")
        :format(index, turtles, from, to, courses))
  reportBands(layers, from, to, d.count)

  print("")
  if not yes and not confirm("Start?") then
    print("Nothing placed.")
    return
  end

  build.clearHoles()
  report.identify({ turtle = index, turtles = turtles,
                    from = from, to = to, courses = courses })

  local meta = { courses = courses, turtles = turtles,
                 turtle = index, fresh = true }
  local done, result = build.run(cfg, cells, layers, from, to, 1, meta)
  if not done then die(result) end

  summarise(result)
end

function cmd.build(args)
  local yes = false
  local rest = {}
  for _, a in ipairs(args) do
    if a == "-y" then yes = true else rest[#rest + 1] = a end
  end

  local ok, ferr = build.refuel(cfg)
  if not ok then die(ferr) end

  if report.open(cfg) then print("Reporting to the monitor.") end

  local turtles, index, courses = gather(rest)
  runBuild(turtles, index, courses, yes)
end

--[[--------------------------------------------------------------------------
  join -- wait for the monitor to hand out a slot.

  Removes the eight hand-typed indices, which is the one place a typo does real
  damage, and lets the monitor release turtles one at a time so they are not
  all tracing the ring at once.

  Needs a modem. `wall build` remains the way to run without one.
----------------------------------------------------------------------------]]
--[[--------------------------------------------------------------------------
  join -- take a slice from the monitor, and get the ring without walking it.

  Walking the big ring takes a lap of the perimeter, and eight turtles cannot
  do it at once without blocking each other's traces. Doing it one at a time is
  most of the launch.

  So only one turtle walks it. Everyone traces the small ring round the launch
  pad instead -- twenty-odd blocks -- and because a trace is anchored and wound
  the same way every time, two turtles' inner traces are the same cells in the
  same order. That is enough to work out the rotation and offset between their
  coordinate systems, and translate the scout's big ring into each turtle's own
  numbers without anyone leaving the pad.
----------------------------------------------------------------------------]]
function cmd.join()
  if not report.open(cfg) then
    die("join needs a wireless modem fitted -- use `wall build` instead")
  end

  local ok, ferr = build.refuel(cfg)
  if not ok then die(ferr) end

  local at, aerr = build.checkStation(cfg)
  if not at then die(aerr) end

  local me = report.id()
  print(("Turtle #%d waiting for the monitor."):format(me))

  local role = report.await(function(m) return m.kind == "role" end,
                            report.enlist)
  if not role then die("no role received") end

  local inner = cfg.innerRing
  if not inner then die("station has no innerRing configured") end

  print("Tracing the inner ring...")
  report.now({ state = "inner" })

  local innerMine, ierr = ring.survey(inner)
  if not innerMine then die("inner ring: " .. tostring(ierr)) end
  print(("  %d cells"):format(#innerMine))

  local mine

  if role.role == "scout" then
    print("Scouting the wall ring...")
    report.now({ state = "scouting" })

    -- Nobody else may touch the pad ring until this turtle is away from it:
    -- the scout traces the pad ring too, and two turtles on that little loop
    -- at once is how the first attempt ended.
    local outerErr
    mine, outerErr = ring.survey(cfg.ring, {
      onFound = function() report.now({ kind = "padclear" }) end,
    })
    if not mine then die("wall ring: " .. tostring(outerErr)) end
    print(("  %d cells"):format(#mine))

    -- Measure the height while out here. It costs a climb, but the others are
    -- busy on the pad ring meanwhile, so it takes no extra wall-clock time --
    -- and it means nobody has to be told the course count by hand.
    print("Measuring height...")
    report.now({ state = "measuring" })

    local courses, herr = scan.height(cfg, mine, { stayOut = true })
    if not courses then die("height: " .. tostring(herr)) end
    if herr then printError("note: " .. herr) end
    print(("  %d courses"):format(courses))

    -- Park back on the ring, well clear of the pad.
    nav.goTo(mine[1].x, 0, mine[1].z)

    -- Hand both rings over and sit still out here: the others are using the
    -- pad, and a turtle wandering back through them would spoil their traces.
    report.now({ kind = "scanned", role = "scout",
                 courses = courses,
                 inner = frame.flatten(innerMine),
                 outer = frame.flatten(mine) })

    print("Waiting for the others to finish...")
    report.await(function(m) return m.kind == "comehome" end)

    if not nav.goHome() then die("could not get back to the station") end
    report.now({ kind = "athome" })

  else
    if not nav.goHome() then die("could not get back to the station") end
    report.now({ kind = "scanned", role = "inner",
                 inner = frame.flatten(innerMine) })

    print("Waiting for the wall ring...")
    local rings = report.await(function(m) return m.kind == "rings" end)
    if not rings then die("no ring data received") end

    local theirInner = frame.unflatten(rings.inner)
    local theirOuter = frame.unflatten(rings.outer)
    if not theirInner or not theirOuter then die("ring data was unreadable") end

    local t, terr = frame.derive(innerMine, theirInner)
    if not t then die("could not line up with the scout: " .. tostring(terr)) end

    mine = frame.map(t, theirOuter)

    local sane, serr = ring.checkShape(mine)
    if not sane then die("the shared ring does not hold up: " .. tostring(serr)) end

    print(("Wall ring: %d cells, worked out without walking it."):format(#mine))
  end

  if cfg.ring.expectCells and #mine ~= cfg.ring.expectCells then
    die(("ring has %d cells, config expects %d")
        :format(#mine, cfg.ring.expectCells))
  end

  report.now({ kind = "ready", cells = #mine })

  local assign = report.await(function(m) return m.kind == "assign" end)
  if not assign then die("no assignment received") end

  print(("Assigned slot %d of %d, %d courses.")
        :format(assign.index, assign.turtles, assign.courses))

  -- Everyone is released together now that no one needs to walk the ring, but
  -- leaving in the same tick from a tight station is asking for a jam.
  sleep(assign.index * 2)

  runBuild(assign.turtles, assign.index, assign.courses, true, mine)
end

function cmd.resume()
  local s = build.loadState()
  if not s then die("no saved run to resume") end

  print(("Resuming turtle %d of %d, course %d, cell %d.")
        :format(s.turtle, s.turtles, s.layer, s.index))
  print("The turtle must be back at its station, facing the way it started.")
  if not confirm("Ready?") then return end

  nav.setPos({ x = 0, y = 0, z = 0, h = 0 })

  local at, aerr = build.checkStation(cfg)
  if not at then die(aerr) end

  local ok, ferr = build.refuel(cfg)
  if not ok then die(ferr) end

  print("Re-tracing the ring...")
  local cells, err = ring.survey(cfg.ring)
  if not cells then die(err) end

  -- The trace is anchored and wound the same way every time, so the saved
  -- index still means the same physical cell -- as long as the ring itself
  -- has not changed underneath us.
  if #cells ~= s.ringCount then
    die(("the ring has changed since the run started (%d cells now, %d then) "
      .. "-- the saved position would land in the wrong place")
        :format(#cells, s.ringCount))
  end

  local layers, perr = pattern.layers(cfg.pattern, s.courses)
  if not layers then die(perr) end

  report.open(cfg)
  report.identify({ turtle = s.turtle, turtles = s.turtles,
                    from = s.layer, to = s.to, courses = s.courses })

  local meta = { courses = s.courses, turtles = s.turtles,
                 turtle = s.turtle, fresh = false }
  local done, result = build.run(cfg, cells, layers, s.layer, s.to, s.index, meta)
  if not done then die(result) end

  summarise(result)
end

function cmd.seal(args)
  local gap = cfg.wall.aboveRing - 1
  if gap < 1 then
    print("There is no gap under the wall to seal.")
    return
  end

  local at, aerr = build.checkStation(cfg)
  if not at then die(aerr) end

  local ok, ferr = build.refuel(cfg)
  if not ok then die(ferr) end

  print("Tracing the marker ring...")
  local cells, err = ring.survey(cfg.ring)
  if not cells then die(err) end

  local layers = pattern.layers(cfg.pattern, tonumber(args[1]) or cfg.height.suggest)
  local block  = layers[1]

  print(("Sealing %d courses under the base with %s (%d cells each).")
        :format(gap, shortName(block), #cells))
  print("Anything already solid is left alone.")

  if not confirm("Start?") then return end

  local done, result = build.seal(cfg, cells, block)
  if not done then die(result) end

  print("")
  print(("Done. %d placed, %d were already solid, %d missed.")
        :format(result.placed, result.skipped, result.missed))
end

function cmd.help()
  print("wall check                    check config and turtle, move nothing")
  print("wall join                     wait for the monitor to assign a slot")
  print("wall scan [--strict]          trace the ring and measure, place nothing")
  print("wall build [n] [i] [courses]  build this turtle's share")
  print("wall resume                   carry on from an interrupted run")
  print("wall seal [courses]           fill the gap under the wall base")
end

--[[--------------------------------------------------------------------------
  Entry
----------------------------------------------------------------------------]]

local args = { ... }
local name = table.remove(args, 1) or "help"

local fn = cmd[name]
if not fn then
  printError("unknown command: " .. name)
  cmd.help()
  return
end

fn(args)
