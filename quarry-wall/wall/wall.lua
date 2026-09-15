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
local function report(result)
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

  local cells, err = ring.survey(cfg, strict)
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
local function runBuild(turtles, index, courses, yes)
  local at, aerr = build.checkStation(cfg)
  if not at then die(aerr) end

  print("Tracing the marker ring...")
  local cells, err = ring.survey(cfg, false)
  if not cells then die(err) end

  local d = ring.describe(cells)
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

  report(result)
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
function cmd.join()
  if not report.open(cfg) then
    die("join needs a wireless modem fitted -- use `wall build` instead")
  end

  local ok, ferr = build.refuel(cfg)
  if not ok then die(ferr) end

  print(("Turtle #%d waiting for the monitor to assign a slot."):format(report.id()))
  print("Ctrl+T to give up.")

  local dots = 0
  local assign, aerr = report.awaitAssignment(function()
    dots = dots + 1
    if dots % 5 == 0 then print("  still waiting...") end
  end)

  if not assign then die(aerr or "no assignment received") end

  print("")
  print(("Assigned slot %d of %d, %d courses.")
        :format(assign.index, assign.turtles, assign.courses))

  runBuild(assign.turtles, assign.index, assign.courses, true)
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
  local cells, err = ring.survey(cfg, false)
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

  report(result)
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
  local cells, err = ring.survey(cfg, false)
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
