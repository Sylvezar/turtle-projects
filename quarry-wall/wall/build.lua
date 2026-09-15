--[[--------------------------------------------------------------------------
  build.lua -- laying the courses.

  The turtle flies one level ABOVE the course it is laying and places
  downwards. That keeps it out of the space it is filling, lets it ride over
  the wall it has already built, and means a cell that already contains
  something is recognised with a single detectDown() and left alone.

  Nothing in here ever calls turtle.dig(). If a cell is occupied it is skipped
  and counted, which is what keeps floating builds in the middle of the pit --
  and anything the quarry left behind -- untouched. With no tool fitted (the
  two upgrade slots go to a crafting table and nothing else) the turtle could
  not break a block even if this code asked it to.
----------------------------------------------------------------------------]]

local nav   = require("nav")
local inv   = require("inv")
local craft = require("craft")
local ring   = require("ring")
local scan   = require("scan")
local report = require("report")

local build = {}

local STATE_FILE = "wall_state.txt"
local HOLES_FILE = "wall_holes.txt"

--[[--------------------------------------------------------------------------
  The hole log

  Cables, machines and anything else already standing in the wall line get
  skipped rather than broken, which leaves gaps. A count of them is useless on
  its own -- "21 holes" somewhere in 18,000 blocks is not something you can go
  and find. So each one is written down as it happens.

  Positions are given as a course number and a cell index counted round the
  ring from the anchor. Both are turtle-independent: every turtle traces the
  same canonical loop, so cell 92 means the same physical block whichever one
  reported it. The height is given as blocks above the marker ring, which you
  can count up from the glass.
----------------------------------------------------------------------------]]

function build.clearHoles()
  if fs.exists(HOLES_FILE) then fs.delete(HOLES_FILE) end
end

function build.holesFile() return HOLES_FILE end

local function holeHeader(cfg, meta, from, to, perLayer)
  local f = fs.open(HOLES_FILE, "w")
  if not f then return end
  f.writeLine(("wall holes -- turtle %d of %d, courses %d to %d")
              :format(meta.turtle, meta.turtles, from, to))
  f.writeLine(("ring: %d cells; cell 1 is the %s anchor, counting the way")
              :format(perLayer, cfg.ring.anchor))
  f.writeLine("the turtles walk it. Height is blocks above the marker ring.")
  f.writeLine("")
  f.close()
end

local function logHole(cfg, label, layer, idx, perLayer, reason)
  local height = (cfg.wall.aboveRing or 1) - 1 + layer

  local f = fs.open(HOLES_FILE, "a")
  if f then
    f.writeLine(("%s %-3d  ring+%-3d  cell %d/%d  %s")
                :format(label, layer, height, idx, perLayer, reason))
    f.close()
  end

  report.hole({ course = layer, height = height, cell = idx,
                cells = perLayer, reason = reason, phase = label })
end

--[[--------------------------------------------------------------------------
  Which courses belong to this turtle
----------------------------------------------------------------------------]]

--- Split `courses` into `turtles` contiguous bands and return the one `index`
--- owns, as an inclusive range. Flooring both ends makes the bands tile with
--- no gap and no overlap even when the division is uneven.
--- Flooring both ends makes the runs tile with no gap and no overlap even when
--- the division is uneven. Courses are split this way when building by course,
--- ring cells when building by column.
local function splitRun(total, parts, index)
  return math.floor((index - 1) * total / parts) + 1,
         math.floor(index * total / parts)
end

function build.band(courses, turtles, index)
  return splitRun(courses, turtles, index)
end

--[[--------------------------------------------------------------------------
  Geometry
----------------------------------------------------------------------------]]

--- Ray casting against the traced loop, so "which way is inwards" works for
--- any shape the marker ring describes, not just a rectangle.
function build.isInside(cells, x, z)
  local inside, n = false, #cells
  local j = n
  for i = 1, n do
    local a, b = cells[i], cells[j]
    if ((a.z > z) ~= (b.z > z))
    and (x < (b.x - a.x) * (z - a.z) / (b.z - a.z) + a.x) then
      inside = not inside
    end
    j = i
  end
  return inside
end

--- Position -> index, so we can tell a ring cell from an ordinary one.
function build.indexMap(cells)
  local m = {}
  for i, c in ipairs(cells) do m[c.x .. "," .. c.z] = i end
  return m
end

--[[--------------------------------------------------------------------------
  Where the turtle can stand to place into `c` sideways, best first.

  Three kinds of neighbour, and the distinction matters a great deal:

    interior     open pit. Always safe to stand in.
    ring, open   another wall cell this pass has not filled yet. A corner has
                 no interior neighbour at all -- both of its orthogonal
                 neighbours are ring cells -- so without these a corner could
                 never be placed from the side.
    ring, filled already placed, and therefore solid. Last resort.

  Anything outside the ring is pit face: solid rock the turtle can never reach.
  Those are dropped entirely rather than ordered last, because merely trying
  one costs a whole pathfinding budget.
----------------------------------------------------------------------------]]
local DIRS = { {0, 1, 2}, {1, 0, 3}, {0, -1, 0}, {-1, 0, 1} }

local function approaches(cells, indexOf, c, filled)
  local interior, open, blocked = {}, {}, {}

  for _, d in ipairs(DIRS) do
    local nx, nz = c.x + d[1], c.z + d[2]
    local n = { x = nx, z = nz, h = d[3] }
    local key = nx .. "," .. nz

    if indexOf[key] then
      if filled and filled[key] then
        blocked[#blocked + 1] = n
      else
        open[#open + 1] = n
      end
    elseif build.isInside(cells, nx, nz) then
      interior[#interior + 1] = n
    end
  end

  for _, n in ipairs(open)    do interior[#interior + 1] = n end
  for _, n in ipairs(blocked) do interior[#interior + 1] = n end
  return interior
end

--- Cells with no interior neighbour at all -- the corners of the ring. They
--- can only ever be placed from a neighbouring ring cell, so they have to be
--- done while those are still open.
function build.cornerFirst(cells, indexOf)
  local corners, rest = {}, {}

  for i, c in ipairs(cells) do
    local hasInterior = false
    for _, d in ipairs(DIRS) do
      local nx, nz = c.x + d[1], c.z + d[2]
      if not indexOf[nx .. "," .. nz] and build.isInside(cells, nx, nz) then
        hasInterior = true
        break
      end
    end
    if hasInterior then rest[#rest + 1] = i else corners[#corners + 1] = i end
  end

  for _, i in ipairs(rest) do corners[#corners + 1] = i end
  return corners
end

--[[--------------------------------------------------------------------------
  Fuel
----------------------------------------------------------------------------]]

--- Burn fuel one item at a time so we stop exactly at the target. Feeding a
--- whole stack in at once is how 64 coal blocks (51,200 fuel) disappear into
--- a tank that caps out around 20,000.
local function burnWhatWeHave(target)
  for _, s in ipairs(inv.ALL) do
    if turtle.getFuelLevel() >= target then return true end
    if turtle.getItemCount(s) > 0 then
      turtle.select(s)
      -- refuel(0) asks "is this combustible?" without consuming it, which is
      -- how we avoid feeding the wall into the fire box.
      if turtle.refuel(0) then
        while turtle.getItemCount(s) > 0 and turtle.getFuelLevel() < target do
          if not turtle.refuel(1) then break end
        end
      end
    end
  end
  return turtle.getFuelLevel() >= target
end

build.burnWhatWeHave = burnWhatWeHave

--[[--------------------------------------------------------------------------
  Put back whatever fuel we did not burn.

  Fuel is drawn in whole grabs but burned only up to the target, so there is
  always a remainder -- and it used to ride along in a slot for the rest of the
  trip, sitting in the inventory while the turtle tried to craft. Anything left
  over goes straight back in the fuel chest.
----------------------------------------------------------------------------]]
function build.returnSpareFuel(cfg)
  local spec = cfg.station.fuel
  if not spec then return end

  for _, s in ipairs(inv.ALL) do
    if turtle.getItemCount(s) > 0 then
      turtle.select(s)
      -- refuel(0) reports combustible without consuming.
      if turtle.refuel(0) then
        turtle.select(s)
        nav.dropAt(spec, turtle.getItemCount(s))
      end
    end
  end
end

function build.refuel(cfg)
  if turtle.getFuelLevel() == "unlimited" then return true end
  if turtle.getFuelLevel() >= cfg.fuel.reserve then return true end

  if burnWhatWeHave(cfg.fuel.refuelTo) then return true end

  local spec = cfg.station.fuel
  if not spec then
    return false, ("out of fuel (%d, need %d) and no fuel chest is configured")
                  :format(turtle.getFuelLevel(), cfg.fuel.reserve)
  end

  -- Chicken and egg: the fuel chest is reached by moving, and moving costs
  -- fuel. A turtle handed no fuel at all can never get to it, and would
  -- otherwise sit here for ten minutes before reporting an empty chest that is
  -- in fact full.
  local o = spec.offset or { 0, 0, 0 }
  if (o[1] ~= 0 or o[2] ~= 0 or o[3] ~= 0)
  and turtle.getFuelLevel() < 8 then
    return false, "out of fuel, and the fuel chest needs a move to reach -- "
               .. "put a coal block (or a few coal) straight into the turtle "
               .. "to get it started"
  end

  for attempt = 1, 120 do
    local slot = inv.firstEmpty(inv.ALL)
    if slot then
      turtle.select(slot)
      if nav.suckAt(spec, cfg.fuel.pullAtOnce) then
        if burnWhatWeHave(cfg.fuel.refuelTo) then
          build.returnSpareFuel(cfg)
          return true
        end
      end
    end
    if turtle.getFuelLevel() >= cfg.fuel.reserve then
      build.returnSpareFuel(cfg)
      return true
    end
    if attempt == 1 then print("Fuel chest empty -- waiting.") end
    sleep(5)
  end

  return false, "fuel chest stayed empty for 10 minutes"
end

--- Enough left to get home from here, with margin?
local function fuelToSpare(cfg)
  if turtle.getFuelLevel() == "unlimited" then return true end
  local p = nav.pos()
  local home = math.abs(p.x) + math.abs(p.y) + math.abs(p.z)
  return turtle.getFuelLevel() > home + 96
end

build.fuelToSpare = fuelToSpare

--[[--------------------------------------------------------------------------
  Am I actually at my station?

  Position is tracked in memory, so whatever cell the turtle is standing in
  when a program starts becomes its origin. Terminate a run out on the ring,
  restart it there, and the turtle will cheerfully build a wall offset by
  however far it had wandered.

  The cheapest reliable tell is the supply chest: it is at a known offset, and
  if there is no block there then this is not the station. Costs a turn and a
  detect, and runs before anything is placed.
----------------------------------------------------------------------------]]
function build.checkStation(cfg)
  local spec = cfg.station.supply
  if not spec then return true end

  if not nav.reach(spec) then
    return false, "could not reach the supply chest position"
  end

  local side = spec.side or "front"
  local there
  if side == "up" then there = turtle.detectUp()
  elseif side == "down" then there = turtle.detectDown()
  else there = turtle.detect() end

  if not there then
    return false, "no supply chest where one should be -- put the turtle back "
               .. "on its station facing the chests. If it was terminated part "
               .. "way through a run, break it and place it again; it keeps "
               .. "its files, inventory and fuel"
  end

  return true
end

--[[--------------------------------------------------------------------------
  Restocking
----------------------------------------------------------------------------]]

--- Which peripheral side a station entry sits on, for reading a chest.
local function peripheralSide(side)
  if side == "up"   then return "top" end
  if side == "down" then return "bottom" end
  return "front"
end

--[[--------------------------------------------------------------------------
  The overflow chest

  turtle.craft() matches against the whole inventory, so the turtle has to be
  completely empty to craft anything. Everything it is carrying goes here in
  the meantime, along with the odd few blocks stranded when the pattern changes
  from one type to the next.

  Which means the chest gradually fills with blocks that are already made. They
  get looked for before crafting anything, so the pattern coming back round to
  a type it has built before costs nothing.
----------------------------------------------------------------------------]]

--- Put everything on board into the overflow chest, optionally keeping up to
--- `keepMax` of `keepName`.
function build.park(cfg, keepName, keepMax)
  local spec = cfg.station.overflow
  if not spec then
    for _, s in ipairs(inv.ALL) do
      if turtle.getItemCount(s) > 0 then return false end
    end
    return true
  end

  if not nav.reach(spec) then return false end

  local kept = 0
  for _, s in ipairs(inv.ALL) do
    local held = turtle.getItemCount(s)
    if held > 0 then
      local drop = held
      if keepName and inv.nameAt(s) == keepName then
        local keep = math.min(held, math.max(0, (keepMax or math.huge) - kept))
        kept = kept + keep
        drop = held - keep
      end
      if drop > 0 then
        turtle.select(s)
        nav.dropAt(spec, drop)

        -- turtle.drop() reports success when it moved only PART of a stack,
        -- which happens as soon as the chest is nearly full. Taking that as
        -- "cleared" leaves items on board, and the next craft is refused with
        -- a stray in a slot nobody put there. Check the slot, not the call.
        local left = turtle.getItemCount(s)
        if left > 0 and not (keepName and inv.nameAt(s) == keepName) then
          return false, ("the overflow chest is full -- %d x %s would not fit")
                        :format(left, tostring(inv.nameAt(s)))
        end
      end
    end
  end

  return true
end

--[[--------------------------------------------------------------------------
  Carrying several block types at once.

  Everything up to here deals in one block at a time, because a course is made
  of one block. A patrol is not: it walks past every course in its band and has
  to be able to plug a hole in any of them, so it carries a little of each.
----------------------------------------------------------------------------]]

--- Park everything except up to `keep[name]` of each named block.
function build.parkExcept(cfg, keep)
  local spec = cfg.station.overflow
  if not spec then return false, "no overflow chest configured" end
  if not nav.reach(spec) then return false, "could not reach the overflow chest" end

  local kept = {}

  for _, s in ipairs(inv.ALL) do
    local held = turtle.getItemCount(s)
    if held > 0 then
      local name = inv.nameAt(s)
      local max  = keep[name]
      local drop = held

      if max then
        local room = max - (kept[name] or 0)
        local k = math.min(held, math.max(0, room))
        kept[name] = (kept[name] or 0) + k
        drop = held - k
      end

      if drop > 0 then
        turtle.select(s)
        nav.dropAt(spec, drop)
        -- Judged by the slot, not the call: drop reports success for a partial
        -- move, which is what a nearly full chest gives you.
        if turtle.getItemCount(s) > held - drop then
          return false, ("the overflow chest is full -- %s would not fit")
                        :format(tostring(name))
        end
      end
    end
  end

  return true
end

--- Take up to `wants[name]` of each named block back out of the overflow.
function build.collectMany(cfg, wants)
  local spec = cfg.station.overflow
  if not spec then return false end
  if not nav.reach(spec) then return false end

  local function satisfied()
    for name, n in pairs(wants) do
      if inv.count(name) < n then return false end
    end
    return true
  end

  for _ = 1, 64 do
    if satisfied() then break end
    local slot = inv.firstEmpty(inv.ALL)
    if not slot then break end
    turtle.select(slot)
    if not nav.suckAt(spec, 64) then break end
  end

  return build.parkExcept(cfg, wants)
end

--- How many of `name` are already sitting in the overflow chest. Reading the
--- chest costs nothing, so this is always worth doing before crafting.
function build.readyInOverflow(cfg, name)
  local spec = cfg.station.overflow
  if not spec or not peripheral then return 0 end
  if not nav.reach(spec) then return 0 end

  local ok, chest = pcall(peripheral.wrap, peripheralSide(spec.side or "front"))
  if not ok or type(chest) ~= "table" or not chest.list then return 0 end

  local listed, items = pcall(chest.list)
  if not listed or type(items) ~= "table" then return 0 end

  local n = 0
  for _, item in pairs(items) do
    if item and item.name == name then n = n + (item.count or 0) end
  end
  return n
end

--- Take up to `want` of `name` back out of the overflow, returning anything
--- else that comes up with it.
function build.collect(cfg, name, want)
  local spec = cfg.station.overflow
  if not spec then return inv.count(name) end
  if not nav.reach(spec) then return inv.count(name) end

  for _ = 1, 64 do
    if inv.count(name) >= want then break end
    local slot = inv.firstEmpty(inv.ALL)
    if not slot then break end
    turtle.select(slot)
    if not nav.suckAt(spec, 64) then break end
  end

  build.park(cfg, name, want)
  return inv.count(name)
end

--[[--------------------------------------------------------------------------
  Taking cobbled deepslate from the supply chest.

  Exactly `target` and not one more: a single spare block is enough to make
  every craft that follows fail.
----------------------------------------------------------------------------]]
local function pullRaw(cfg, target)
  local spec = cfg.station.supply
  local stalls = 0

  while inv.count(craft.RAW) < target do
    local slot = inv.firstEmpty(inv.ALL)
    if not slot then return false, "no free slot for cobbled deepslate" end

    turtle.select(slot)
    local take = math.min(64, target - inv.count(craft.RAW))

    if nav.suckAt(spec, take) then
      stalls = 0
      local got = inv.nameAt(slot)
      if got and got ~= craft.RAW then
        return false, ("the supply chest holds %s -- it must contain only "
                    .. "cobbled deepslate"):format(got)
      end
    else
      stalls = stalls + 1
      if stalls == 1 then print("Supply chest empty -- waiting.") end
      if stalls > 120 then
        return false, "supply chest stayed empty for 10 minutes"
      end
      sleep(5)
    end
  end

  return true
end

--[[--------------------------------------------------------------------------
  restock -- come home and load up with `block`.

  For plain cobbled deepslate there is nothing to craft, so it just fills up.
  Anything else has to be made, and making it means emptying the turtle first.
----------------------------------------------------------------------------]]
function build.restock(cfg, block, want, stillNeeded)
  if not nav.goHome() then return 0, "could not get back to the station" end

  local ok, err = build.refuel(cfg)
  if not ok then return 0, err end

  if block == craft.RAW then
    local ok2, perr2 = build.park(cfg, block, want)
    if not ok2 then return 0, perr2 or "could not clear the inventory" end
    local pulled, perr = pullRaw(cfg, want)
    if not pulled then return inv.count(block), perr end
    return inv.count(block)
  end

  if not cfg.station.overflow then
    return 0, "this pattern needs crafting, and crafting needs the turtle to "
           .. "be empty -- set station.overflow in config.lua so it has "
           .. "somewhere to put things"
  end

  -- Everything off the turtle: it has to be bare to craft at all.
  local cleared, cerr = build.park(cfg)
  if not cleared then
    return 0, cerr or "could not clear the inventory"
  end

  -- And say so here if it is not, rather than pulling material on top of
  -- whatever survived and failing later in a way that points at the wrong
  -- thing entirely.
  for _, s in ipairs(inv.ALL) do
    if turtle.getItemCount(s) > 0 then
      return 0, ("slot %d still holds %s after clearing out -- the turtle has "
              .. "to be empty to craft. Try `wall clear`.")
                :format(s, tostring(inv.nameAt(s)))
    end
  end

  local stocked, serr = build.stockUp(cfg, block, want)
  if not stocked then return 0, serr end

  return build.collect(cfg, block, want)
end

--[[--------------------------------------------------------------------------
  stockUp -- make sure the overflow chest holds `want` of `block`.

  Assumes the turtle is already empty, which is what crafting demands. Leaves
  everything in the overflow rather than on board, so several types can be
  stocked one after another without the previous one getting in the way.
----------------------------------------------------------------------------]]
function build.stockUp(cfg, block, want)
  local shortfall = want - build.readyInOverflow(cfg, block)

  while shortfall > 0 do
    local plan, perr = craft.planBatch(block, shortfall)
    if not plan then return false, perr end

    local pulled, rerr = pullRaw(cfg, plan.raw)
    if not pulled then return false, rerr end

    -- Exactly the batch, not at least it. A batch is sized so every stage of
    -- the chain divides evenly; one block more and the last stage has a
    -- remainder, which is a stray item, which is a refused craft.
    local have = inv.count(craft.RAW)

    if have > plan.raw then
      -- Put the surplus back rather than refusing to work. The overflow chest
      -- is directly underneath, so this costs nothing.
      print(("  %d spare cobbled deepslate, putting it back")
            :format(have - plan.raw))
      local shed, sherr = build.park(cfg, craft.RAW, plan.raw)
      if not shed then
        return false, sherr or "could not put the surplus back"
      end
      have = inv.count(craft.RAW)
    end

    if have ~= plan.raw then
      return false, ("needed exactly %d cobbled deepslate for this batch, have "
                  .. "%d -- the supply chest may have run dry")
                    :format(plan.raw, have)
    end

    local made, cerr = craft.runBatch(plan)
    if not made then return false, cerr end

    local parked, pkerr = build.park(cfg)
    if not parked then
      return false, pkerr or "could not park the finished batch"
    end
    shortfall = shortfall - plan.out
  end

  return true
end

--[[--------------------------------------------------------------------------
  loadKit -- carry a little of every block a patrol might need.
----------------------------------------------------------------------------]]
function build.loadKit(cfg, types, perType)
  local wants = {}
  for _, block in ipairs(types) do wants[block] = perType end
  return build.loadExactly(cfg, wants)
end

--[[--------------------------------------------------------------------------
  Placing a single cell
----------------------------------------------------------------------------]]

local function tryPlace(block, placer)
  if not inv.selectItem(block) then return false end
  for attempt = 1, 4 do
    if placer() then return true end
    if attempt < 4 then sleep(0.4) end   -- probably a mob standing in the cell
  end
  return false
end

--[[--------------------------------------------------------------------------
  Fill one ring cell on one course. Returns "placed", "skipped" or "missed".

  Normally the turtle hovers over the cell and places down. That fails when
  something already occupies the space directly above -- a block the quarry
  left in the perimeter column, say -- because the turtle cannot stand where
  the obstruction is. So it falls back to standing beside the cell, level with
  it, and placing sideways. Between the two a wall can be threaded past
  obstacles without breaking any of them.
----------------------------------------------------------------------------]]
--- Returns the outcome, and whether hovering over the cell turned out to be
--- impossible -- which tells the caller not to keep trying it.
function build.placeCell(cfg, cells, c, y, block, indexOf, filled, skipOverhead)
  local overheadFailed = false

  if not skipOverhead then
    if nav.goTo(c.x, y + 1, c.z) then
      if cfg.build.skipOccupied and turtle.detectDown() then return "skipped" end
      if tryPlace(block, turtle.placeDown) then return "placed" end
    else
      overheadFailed = true
    end
  end

  indexOf = indexOf or build.indexMap(cells)
  for _, n in ipairs(approaches(cells, indexOf, c, filled)) do
    if nav.goTo(n.x, y, n.z) then
      nav.turnTo(n.h)
      if cfg.build.skipOccupied and turtle.detect() then
        return "skipped", overheadFailed
      end
      if tryPlace(block, turtle.place) then return "placed", overheadFailed end
    end
  end

  return "missed", overheadFailed
end

--[[--------------------------------------------------------------------------
  Resume state
----------------------------------------------------------------------------]]

function build.saveState(s)
  local f = fs.open(STATE_FILE, "w")
  f.write(textutils.serialize(s))
  f.close()
end

function build.loadState()
  if not fs.exists(STATE_FILE) then return nil end
  local f = fs.open(STATE_FILE, "r")
  local s = textutils.unserialize(f.readAll())
  f.close()
  return s
end

function build.clearState()
  if fs.exists(STATE_FILE) then fs.delete(STATE_FILE) end
end

--[[--------------------------------------------------------------------------
  The main loop
----------------------------------------------------------------------------]]

local function remainingTypes(layers, from, to)
  local t = {}
  for i = from, to do t[layers[i]] = true end
  return t
end

local function shortName(name) return (name:gsub("^minecraft:", "")) end

--- How many courses from `layer` onwards use the same block, so one load can
--- cover several and save the climb back down.
local function runLength(layers, layer, last)
  local n = 1
  while layer + n <= last and layers[layer + n] == layers[layer] do
    n = n + 1
  end
  return n
end

--[[--------------------------------------------------------------------------
  run -- build courses `from`..`to` of `layers` on the traced `cells`.
----------------------------------------------------------------------------]]
function build.run(cfg, cells, layers, from, to, startIndex, meta)
  if ring.contains(cells, 0, 0) then
    return false, "the station is standing on the marker ring -- move it "
               .. "inside, or the wall will close over the chests"
  end

  local perLayer = #cells
  local base     = scan.baseY(cfg)
  local indexOf  = build.indexMap(cells)

  local placed, skipped, missed = 0, 0, 0
  local sinceSave = 0

  if meta.fresh then holeHeader(cfg, meta, from, to, perLayer) end

  local function save(layer, idx)
    local s = {
      layer = layer, index = idx,
      from = from, to = to,
      courses = meta.courses, turtles = meta.turtles, turtle = meta.turtle,
      ringCount = perLayer,
    }
    build.saveState(s)
  end

  for layer = from, to do
    local block = layers[layer]
    local still = remainingTypes(layers, layer, to)
    local cap   = cfg.build.maxCarryCrafted
    if block == craft.RAW then cap = cfg.build.maxCarryRaw end

    local y      = base + (layer - 1)
    local idx    = (layer == from) and startIndex or 1
    local filled = {}

    -- Cells that would not take a block first time round. A mob standing in
    -- the cell is not a block, so it reads as empty and simply refuses the
    -- placement -- and the pit is dark, so this happens. They are tried again
    -- at the end of the course, by which time whatever it was has wandered off.
    local blocked = {}

    -- Placing normally means hovering over the cell, but on the top course of
    -- a band the course above is another turtle's and already built. The trip
    -- up is then wasted on every single cell, and worst at the corners, where
    -- the sideways fallback has to climb back down again. It fails the same way
    -- for the whole course, so once is enough to learn it.
    local noHover = false

    print(("Course %d/%d  %s")
          :format(layer, to, shortName(block)))

    report.now({ state = "building", course = layer, cell = idx,
                 cells = perLayer, block = shortName(block),
                 placed = placed, skipped = skipped, missed = missed,
                 fuel = turtle.getFuelLevel() })

    while idx <= perLayer do
      if inv.count(block) == 0 then
        -- Take enough for the rest of this course plus any following courses
        -- made of the same block, so a load can span several.
        local want = perLayer - idx + 1
        if cfg.build.carryAcross then
          want = want + perLayer * (runLength(layers, layer, to) - 1)
        end
        want = math.min(cap, want)

        report.now({ state = "restocking", course = layer, cell = idx,
                     cells = perLayer, block = shortName(block),
                     placed = placed, skipped = skipped, missed = missed,
                     fuel = turtle.getFuelLevel() })

        local got, err = build.restock(cfg, block, want, still)
        if got == 0 then
          save(layer, idx)
          local why = err or ("could not obtain " .. shortName(block))
          report.now({ state = "stopped", course = layer, cell = idx,
                       cells = perLayer, error = why,
                       placed = placed, skipped = skipped, missed = missed,
                       fuel = turtle.getFuelLevel() })
          return false, why
        end
      end

      while idx <= perLayer and inv.count(block) > 0 do
        if not fuelToSpare(cfg) then
          save(layer, idx)
          -- Just go and refuel. Running a full restock here would park the
          -- load it is carrying and then collect nothing back, because it
          -- asked for none.
          if not nav.goHome() then
            return false, "could not get back to the station to refuel"
          end
          local fine, ferr = build.refuel(cfg)
          if not fine then return false, ferr end
        end

        local cell = cells[idx]
        local outcome, overhead = build.placeCell(cfg, cells, cell, y, block,
                                                  indexOf, filled, noHover)
        if overhead then noHover = true end

        if outcome == "placed" then
          placed = placed + 1
          filled[cell.x .. "," .. cell.z] = true
        elseif outcome == "skipped" then
          skipped = skipped + 1
          filled[cell.x .. "," .. cell.z] = true
          logHole(cfg, "course", layer, idx, perLayer, "occupied")
        else
          blocked[#blocked + 1] = idx
        end

        idx = idx + 1

        report.tick({ state = "building", course = layer, cell = idx,
                      cells = perLayer, block = shortName(block),
                      placed = placed, skipped = skipped, missed = missed,
                      fuel = turtle.getFuelLevel() })

        sinceSave = sinceSave + 1
        if sinceSave >= cfg.build.saveEvery then
          save(layer, idx)
          sinceSave = 0
        end
      end
    end

    -- Second go at anything that was blocked. Only what fails twice, minutes
    -- apart, is really a hole.
    if #blocked > 0 then
      print(("  %d cells were blocked; trying again"):format(#blocked))

      for _, i in ipairs(blocked) do
        if inv.count(block) == 0 then
          local got = build.restock(cfg, block, math.min(cap, #blocked), still)
          if got == 0 then break end
        end

        local cell = cells[i]
        local outcome, overhead = build.placeCell(cfg, cells, cell, y, block,
                                                  indexOf, filled, noHover)
        if overhead then noHover = true end

        if outcome == "placed" then
          placed = placed + 1
          filled[cell.x .. "," .. cell.z] = true
        elseif outcome == "skipped" then
          skipped = skipped + 1
          filled[cell.x .. "," .. cell.z] = true
          logHole(cfg, "course", layer, i, perLayer, "occupied")
        else
          missed = missed + 1
          logHole(cfg, "course", layer, i, perLayer, "UNREACHABLE")
        end
      end
    end
  end

  nav.goHome()
  build.clearState()

  report.now({ state = "done", course = to, cell = perLayer, cells = perLayer,
               placed = placed, skipped = skipped, missed = missed,
               fuel = turtle.getFuelLevel() })

  return true, { placed = placed, skipped = skipped, missed = missed }
end

--[[--------------------------------------------------------------------------
  patrol -- walk the finished wall looking for gaps, and plug them.

  A course is built in one pass and anything in the way at that moment -- a mob
  standing in the cell, a turtle, a cable -- leaves a hole. This goes back over
  the wall afterwards carrying a little of every block in the pattern, and fills
  whatever it finds missing.

  It flies up the column just INSIDE each wall cell and looks sideways, because
  the wall cell itself is where the wall is. That is also why corners are
  skipped: a corner has no interior neighbour to fly up beside, so there is
  nowhere to look from. They cannot be seen from inside the pit either, which
  is what makes that acceptable.
----------------------------------------------------------------------------]]

--- The interior cell next to `c`, and the heading that looks from it at `c`.
local function lookoutFor(cells, indexOf, c)
  for _, d in ipairs(DIRS) do
    local nx, nz = c.x + d[1], c.z + d[2]
    if not indexOf[nx .. "," .. nz] and build.isInside(cells, nx, nz) then
      return { x = nx, z = nz, h = d[3] }
    end
  end
  return nil
end

--[[--------------------------------------------------------------------------
  BUILDING BY COLUMNS

  The other way round from `build.run`: a turtle takes a stretch of the ring
  and builds every course of it, rather than taking a stretch of the courses
  and building every cell of each.

  It is the better arrangement, and the reason is restocking. Laying courses,
  the wall goes up one block at a time and the turtle has to fly the whole
  height of its band down to the chests and back every time it runs dry --
  pure overhead, hundreds of moves a load. Laying columns, the climb IS the
  work: every move up puts a block in the wall. And because the turtle
  serpentines -- up one column, over one, down the next -- it is back at the
  bottom after an EVEN number of columns, standing on the chests exactly when
  it needs them. Loads are sized to an even number of columns for that reason,
  even at the cost of carrying less.

  It also disposes of the whole awkward business of placing from above. A
  course-laying turtle hovers over the cell and places down, which means it
  needs the space above the wall to be empty -- and it is not, once the course
  above it exists. Everything here places sideways out of the open pit
  instead, where there is never anything in the way.

  The price is the crafting. A column spans the entire pattern, so a load has
  to hold every block type in it and each one is a separate batch. That turns
  out to be cheap: the overflow chest is directly under the turtle, so parking
  one batch to start the next costs no movement at all.
----------------------------------------------------------------------------]]

--- What one full-height column of the wall consumes, as { [block] = count }.
--- Every column is identical, so this is the unit everything else is sized in.
function build.columnNeeds(layers, courses)
  local needs = {}
  for c = 1, courses do
    needs[layers[c]] = (needs[layers[c]] or 0) + 1
  end
  return needs
end

--- Block names in a fixed order. `pairs` order varies between runs, and the
--- order decides which batch is crafted first, so pin it down.
local function sortedNames(t)
  local names = {}
  for name in pairs(t) do names[#names + 1] = name end
  table.sort(names)
  return names
end

-- Slots the material may occupy. Two of the sixteen are held back: one for the
-- coal a mid-run refuel pulls in, one for collectMany to suck into.
local SLOT_BUDGET = 14

local function slotsFor(needs, k)
  local n = 0
  for _, count in pairs(needs) do n = n + math.ceil(count * k / 64) end
  return n
end

--[[--------------------------------------------------------------------------
  How many whole columns to carry at a time.

  Even, so the serpentine finishes at the bottom where the chests are. That is
  the entire point of the arrangement and it is worth giving up a column of
  capacity to keep: an odd load strands the turtle at the top of the wall with
  an empty inventory and a full-height descent in front of it.
----------------------------------------------------------------------------]]
function build.columnsPerLoad(cfg, needs)
  local fixed = cfg.build.columnsPerLoad or 0
  if fixed > 0 then return fixed end

  local perColumn = 0
  for _, count in pairs(needs) do perColumn = perColumn + count end
  if perColumn == 0 then return 2 end

  local cap  = cfg.build.maxCarryCrafted or 256
  local best = 0

  for k = 2, 64, 2 do
    if perColumn * k > cap then break end
    if slotsFor(needs, k) > SLOT_BUDGET then break end
    best = k
  end

  -- A wall tall enough that a single column will not fit in the turtle at all.
  -- It still works, it just has to come down mid-column as the old builder did.
  if best == 0 then return 1 end
  return best
end

--[[--------------------------------------------------------------------------
  loadExactly -- come home, make everything in `wants`, and carry it away.

  Crafting needs the turtle completely empty, so each type is made in turn and
  parked in the overflow, and the whole lot collected at the end.
----------------------------------------------------------------------------]]
function build.loadExactly(cfg, wants)
  if not nav.goHome() then return false, "could not get back to the station" end

  local ok, err = build.refuel(cfg)
  if not ok then return false, err end

  local cleared, cerr = build.park(cfg)
  if not cleared then return false, cerr end

  for _, name in ipairs(sortedNames(wants)) do
    local stocked, serr = build.stockUp(cfg, name, wants[name])
    if not stocked then return false, serr end
  end

  return build.collectMany(cfg, wants)
end

--- Enough for `k` whole columns.
function build.loadColumns(cfg, needs, k)
  local wants = {}
  for name, count in pairs(needs) do wants[name] = count * k end
  return build.loadExactly(cfg, wants)
end

--[[--------------------------------------------------------------------------
  The order the columns are built in, and which way up each one is built.

  Corners come first, and always upwards. A corner has no interior neighbour to
  stand beside -- that is what makes it a corner -- so the only way to fill one
  is to ride up inside the column itself, laying each block into the space just
  vacated. That cannot be done downwards, and the topmost course has no room
  above it for the trick at all, so it is reached sideways from a neighbouring
  ring cell instead. Which only works while that neighbour is still open air:
  hence first.

  Everything after that alternates, so the turtle ends each pair of columns
  back at the bottom.
----------------------------------------------------------------------------]]
function build.columnOrder(cells, indexOf, lo, hi)
  local corners, rest = {}, {}

  for i = lo, hi do
    if lookoutFor(cells, indexOf, cells[i]) then
      rest[#rest + 1] = i
    else
      corners[#corners + 1] = i
    end
  end

  local order = {}
  for _, i in ipairs(corners) do
    order[#order + 1] = { cell = i, up = true, corner = true }
  end

  local up = true
  for _, i in ipairs(rest) do
    order[#order + 1] = { cell = i, up = up }
    up = not up
  end

  return order
end

--- Which cells of the ring this turtle owns.
function build.arc(ringCount, turtles, index)
  return splitRun(ringCount, turtles, index)
end

local function verticalHoleHeader(cfg, meta, lo, hi, perLayer)
  local f = fs.open(HOLES_FILE, "w")
  if not f then return end
  f.writeLine(("wall holes -- turtle %d of %d, ring cells %d to %d")
              :format(meta.turtle, meta.turtles, lo, hi))
  f.writeLine(("ring: %d cells; cell 1 is the %s anchor, counting the way")
              :format(perLayer, cfg.ring.anchor))
  f.writeLine("the turtles walk it. Height is blocks above the marker ring.")
  f.writeLine("")
  f.close()
end

--[[--------------------------------------------------------------------------
  runVertical -- build every course of ring cells `lo`..`hi`.

  `startAt` and `startCourse` are where a resumed run picks up: a position in
  the column order, and the course within that column.
----------------------------------------------------------------------------]]
function build.runVertical(cfg, cells, layers, courses, lo, hi,
                           startAt, startCourse, meta)
  if ring.contains(cells, 0, 0) then
    return false, "the station is standing on the marker ring -- move it "
               .. "inside, or the wall will close over the chests"
  end

  local perLayer = #cells
  local base     = scan.baseY(cfg)
  local indexOf  = build.indexMap(cells)
  local order    = build.columnOrder(cells, indexOf, lo, hi)
  local needs    = build.columnNeeds(layers, courses)
  local perLoad  = build.columnsPerLoad(cfg, needs)

  local placed, skipped, missed = 0, 0, 0
  local blocked   = {}
  local sinceSave = 0

  if meta.fresh then verticalHoleHeader(cfg, meta, lo, hi, perLayer) end

  local at = startAt or 1

  local function save(course)
    build.saveState({
      mode = "vertical",
      at = at, course = course, cell = order[at] and order[at].cell,
      from = lo, to = hi,
      courses = courses, turtles = meta.turtles, turtle = meta.turtle,
      ringCount = perLayer,
    })
  end

  local function status(state, cell, course)
    return { state = state, mode = "vertical",
             cell = cell, cells = perLayer,
             course = course, courses = courses,
             placed = placed, skipped = skipped, missed = missed,
             fuel = turtle.getFuelLevel() }
  end

  --- Do we hold a whole column's worth of every block the pattern uses?
  local function haveColumn()
    for name, count in pairs(needs) do
      if inv.count(name) < count then return false end
    end
    return true
  end

  --- Go and make another load. Only ever called between columns, so the turtle
  --- is at the bottom of the wall and the trip is a short one.
  local function reload(cell, course)
    save(course)
    report.now(status("restocking", cell, course))
    print(("  restocking -- %d columns' worth"):format(perLoad))
    return build.loadColumns(cfg, needs, perLoad)
  end

  for step = at, #order do
    at = step
    local entry = order[step]
    local c     = cells[entry.cell]

    local first, last, dir
    if entry.up then first, last, dir = startCourse or 1, courses, 1
    else first, last, dir = startCourse or courses, 1, -1 end
    startCourse = nil

    if not haveColumn() then
      local ok, err = reload(entry.cell, first)
      if not ok then
        report.now(status("stopped", entry.cell, first))
        return false, err
      end
    end

    if not fuelToSpare(cfg) then
      if not nav.goHome() then
        return false, "could not get back to the station to refuel"
      end
      local fine, ferr = build.refuel(cfg)
      if not fine then return false, ferr end
    end

    print(("Cell %d/%d  %s")
          :format(entry.cell, perLayer, entry.up and "up" or "down"))
    report.now(status("building", entry.cell, first))

    if entry.corner then
      -- Up inside the column itself, laying each block into the space the
      -- turtle has just left. placeCell does exactly that with its overhead
      -- approach, and falls back to reaching in from a neighbouring ring cell
      -- for the topmost course, where there is no room to hover.
      for course = first, last, dir do
        local y     = base + (course - 1)
        local block = layers[course]

        if inv.count(block) == 0 then
          local ok, err = reload(entry.cell, course)
          if not ok then
            report.now(status("stopped", entry.cell, course))
            return false, err
          end
        end

        local outcome = build.placeCell(cfg, cells, c, y, block, indexOf, nil)

        if outcome == "placed" then
          placed = placed + 1
        elseif outcome == "skipped" then
          skipped = skipped + 1
          logHole(cfg, "column", course, entry.cell, perLayer, "occupied")
        else
          blocked[#blocked + 1] = { cell = entry.cell, course = course }
        end

        sinceSave = sinceSave + 1
        if sinceSave >= cfg.build.saveEvery then
          save(course)
          sinceSave = 0
        end
        report.tick(status("building", entry.cell, course))
      end

    else
      local look = lookoutFor(cells, indexOf, c)

      --- Get beside the cell at `course`, facing it.
      local function beside(course)
        local y = base + (course - 1)
        local p = nav.pos()
        if p.x ~= look.x or p.y ~= y or p.z ~= look.z then
          if not nav.goTo(look.x, y, look.z) then return false end
        end
        nav.turnTo(look.h)
        return true
      end

      if not beside(first) then
        missed = missed + (math.abs(last - first) + 1)
        logHole(cfg, "column", first, entry.cell, perLayer,
                "UNREACHABLE -- could not get beside the column")
      else
        for course = first, last, dir do
          local block = layers[course]

          if inv.count(block) == 0 then
            local ok, err = reload(entry.cell, course)
            if not ok then
              report.now(status("stopped", entry.cell, course))
              return false, err
            end
          end

          if not beside(course) then
            blocked[#blocked + 1] = { cell = entry.cell, course = course }
          elseif cfg.build.skipOccupied and turtle.detect() then
            skipped = skipped + 1
            logHole(cfg, "column", course, entry.cell, perLayer, "occupied")
          elseif tryPlace(block, turtle.place) then
            placed = placed + 1
          else
            blocked[#blocked + 1] = { cell = entry.cell, course = course }
          end

          sinceSave = sinceSave + 1
          if sinceSave >= cfg.build.saveEvery then
            save(course)
            sinceSave = 0
          end
          report.tick(status("building", entry.cell, course))
        end
      end
    end
  end

  --[[------------------------------------------------------------------------
    Second go at whatever would not take a block. The pit is dark and a mob
    standing in a cell is not a block: it reads as empty and simply refuses
    the placement. Only what fails twice, a long while apart, is a real hole.
  --------------------------------------------------------------------------]]
  if #blocked > 0 then
    print(("%d cells were blocked; trying again"):format(#blocked))
    report.now(status("building", blocked[1].cell, blocked[1].course))

    for _, b in ipairs(blocked) do
      local c     = cells[b.cell]
      local y     = base + (b.course - 1)
      local block = layers[b.course]

      if inv.count(block) == 0 then
        local ok = build.loadColumns(cfg, needs, perLoad)
        if not ok then break end
      end

      local outcome = build.placeCell(cfg, cells, c, y, block, indexOf, nil)
      if outcome == "placed" then
        placed = placed + 1
      elseif outcome == "skipped" then
        skipped = skipped + 1
        logHole(cfg, "column", b.course, b.cell, perLayer, "occupied")
      else
        missed = missed + 1
        logHole(cfg, "column", b.course, b.cell, perLayer, "UNREACHABLE")
      end
    end
  end

  nav.goHome()
  build.clearState()

  report.now(status("done", hi, courses))

  return true, { placed = placed, skipped = skipped, missed = missed }
end

--- `cellLo`/`cellHi` narrow it to a stretch of the ring, which is what a
--- turtle that built by column wants: it owns an arc, not a band of courses.
function build.patrol(cfg, cells, layers, from, to, cellLo, cellHi)
  local base    = scan.baseY(cfg)
  local indexOf = build.indexMap(cells)

  local filled, corners, missed, checked = 0, 0, 0, 0
  local up = true

  for idx = cellLo or 1, cellHi or #cells do
    local c = cells[idx]
    local look = lookoutFor(cells, indexOf, c)

    -- A column can take a while, and the monitor calls a turtle "quiet" after
    -- half a minute of silence. Speak up once per column, and again every few
    -- courses inside it, so a patrol looks alive rather than hung.
    --- `placed`/`skipped`/`missed` keep the same meaning they have during a
    --- build, so the monitor's columns still read correctly: holes filled,
    --- corners passed over, cells that could not be dealt with.
    local function say(send, course)
      send({ state = "patrolling", course = course, cell = idx,
             cells = #cells, placed = filled, skipped = corners,
             missed = missed, fuel = turtle.getFuelLevel() })
    end

    say(report.now, from)

    if not look then
      corners = corners + 1
    else
      -- Serpentine: up one column, down the next, rather than dropping back to
      -- the bottom every time.
      local first, last, step
      if up then first, last, step = from, to, 1
      else first, last, step = to, from, -1 end
      up = not up

      local reached = nav.goTo(look.x, base + (first - 1), look.z)
      if not reached then
        missed = missed + (math.abs(to - from) + 1)
        logHole(cfg, "patrol", first, idx, #cells,
                "UNREACHABLE -- could not get beside the column")
      else
        nav.turnTo(look.h)

        for course = first, last, step do
          local y = base + (course - 1)

          if nav.pos().y ~= y then
            if not nav.goTo(look.x, y, look.z) then break end
            nav.turnTo(look.h)
          end

          checked = checked + 1
          say(report.tick, course)

          if not turtle.detect() then
            local block = layers[course]
            if inv.count(block) == 0 then
              local kit = {}
              for i = from, to do kit[layers[i]] = true end
              local list = {}
              for name in pairs(kit) do list[#list + 1] = name end

              report.now({ state = "restocking", course = course, cell = idx,
                           cells = #cells, block = shortName(block),
                           placed = filled, skipped = corners, missed = missed })

              local got, kerr = build.loadKit(cfg, list, 64)
              if not got then return false, kerr end

              if not nav.goTo(look.x, y, look.z) then break end
              nav.turnTo(look.h)
            end

            if inv.selectItem(block) and turtle.place() then
              filled = filled + 1
              logHole(cfg, "fixed", course, idx, #cells, "filled")
            else
              missed = missed + 1
              logHole(cfg, "patrol", course, idx, #cells,
                      "COULD NOT PLACE " .. shortName(block))
            end
          end
        end
      end
    end
  end

  nav.goHome()
  return true, { filled = filled, checked = checked,
                 corners = corners, missed = missed }
end

--[[--------------------------------------------------------------------------
  seal -- fill the gap between the marker ring and the wall's base.

  With `aboveRing` greater than 1 the wall leaves an opening all the way round
  so you can work underneath it and so the ring stays readable for a re-trace.
  This closes that opening afterwards. `skipOccupied` does the useful part:
  intact rock is detected and left alone, so only the actual gaps get filled.
----------------------------------------------------------------------------]]
function build.seal(cfg, cells, block)
  local base = scan.baseY(cfg)
  if base < 1 then return false, "there is no gap under the base to seal" end

  local cap = cfg.build.maxCarryCrafted
  if block == craft.RAW then cap = cfg.build.maxCarryRaw end

  local still   = { [block] = true }
  local indexOf = build.indexMap(cells)
  local placed, skipped, missed = 0, 0, 0

  -- Corners first: with the wall directly overhead there is nowhere to hover,
  -- so a corner can only be reached from a neighbouring ring cell -- and those
  -- are only open before the rest of the level goes in.
  local order = build.cornerFirst(cells, indexOf)

  for y = 0, base - 1 do
    local at     = 1
    local filled = {}
    local noHover = false
    print(("Sealing level %d of %d"):format(y + 1, base))

    while at <= #order do
      if inv.count(block) == 0 then
        local want = math.min(cap, #order - at + 1)
        local got, err = build.restock(cfg, block, want, still)
        if got == 0 then
          return false, err or ("could not obtain " .. shortName(block))
        end
      end

      while at <= #order and inv.count(block) > 0 do
        if not fuelToSpare(cfg) then
          local got, err = build.restock(cfg, block, 0, still)
          if got == 0 and err then return false, err end
        end

        local cell = cells[order[at]]
        local outcome, overhead = build.placeCell(cfg, cells, cell, y, block,
                                                  indexOf, filled, noHover)
        if overhead then noHover = true end

        if outcome == "placed" then
          placed = placed + 1
        elseif outcome == "skipped" then
          skipped = skipped + 1
        else
          missed = missed + 1
          logHole(cfg, "seal ", y + 1, order[at], #cells, "UNREACHABLE")
        end
        if outcome ~= "missed" then
          filled[cell.x .. "," .. cell.z] = true
        end
        at = at + 1
      end
    end
  end

  nav.goHome()
  return true, { placed = placed, skipped = skipped, missed = missed }
end

return build
