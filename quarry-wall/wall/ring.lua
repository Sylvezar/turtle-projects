--[[--------------------------------------------------------------------------
  ring.lua -- reading the marker ring off the floor.

  The wall follows a ring of blocks laid one level below where the turtles
  stand, rather than a rectangle measured by walking until something stops
  you. That matters for three reasons:

    * nothing can confuse it. Pillars on the floor, cave mouths in the pit
      face and bumpy bedrock all broke the old probing approach; none of them
      touch this one.
    * every turtle gets the same answer, because they are all reading the
      same physical blocks. No GPS, no shared origin, no per-turtle offsets.
    * the wall follows whatever shape you mark. It does not have to be a
      rectangle.

  One block of the ring is the `anchor`. The traced loop is rotated to start
  there and wound in a fixed direction, so the cell list is identical on every
  turtle and on every re-trace -- which is what makes a resume land exactly
  where it stopped.
----------------------------------------------------------------------------]]

local nav = require("nav")

local ring = {}

--- config.lua takes block names without the namespace; inspectDown() hands
--- them back with it.
local function full(name)
  if name:find(":") then return name end
  return "minecraft:" .. name
end

ring.full = full

--- What kind of marker, if any, is directly below the turtle.
--- Returns "ring", "anchor", or nil.
local function kindBelow(cfg)
  local ok, block = turtle.inspectDown()
  if not ok then return nil end
  if block.name == full(cfg.ring.block)  then return "ring"   end
  if block.name == full(cfg.ring.anchor) then return "anchor" end
  return nil
end

ring.kindBelow = kindBelow

--- Step one block in direction `h` and report what marker is underneath.
--- Steps back if there is none, so the turtle always ends up where it was
--- unless it found something.
local function probeStep(cfg, h)
  nav.turnTo(h)
  if not nav.forward() then return nil end
  local kind = kindBelow(cfg)
  if kind then return kind end
  nav.back()
  return nil
end

--- Which of the four neighbours are ring cells. Costs two moves per miss, so
--- it is only used for the start cell and for the strict check.
local function neighbours(cfg, exclude)
  local found = {}
  for h = 0, 3 do
    if h ~= exclude then
      local kind = probeStep(cfg, h)
      if kind then
        found[#found + 1] = { h = h, kind = kind }
        nav.turnTo((h + 2) % 4)
        nav.forward()          -- step back off it, we are only counting
      end
    end
  end
  return found
end

--[[--------------------------------------------------------------------------
  Finding the ring from the station.

  Walks outward until the block below is a ring block. Only `ring` counts as a
  starting point, never `anchor` -- station floors are commonly made of the
  same stuff as the anchor, and a solid platform is not a ring.
----------------------------------------------------------------------------]]
function ring.find(cfg)
  local far = cfg.ring.searchDistance

  -- Behind first: with the turtle facing the chest stack, that is the one
  -- direction guaranteed not to start by walking into the station.
  for _, h in ipairs({ 2, 1, 3, 0 }) do
    if not nav.goHome() then return false, "could not get back to the station" end
    nav.turnTo(h)
    for _ = 1, far do
      if not nav.forward() then break end
      if kindBelow(cfg) == "ring" then return true end
    end
  end

  nav.goHome()
  return false, ("could not find any %s within %d blocks of the station")
                :format(full(cfg.ring.block), far)
end

--[[--------------------------------------------------------------------------
  Tracing the loop.

  From a cell known to be on the ring, walk it. At each step it tries straight
  ahead first and only then the two turns, never reversing -- so a straight
  run costs one move per cell and only corners cost extra.

  `strict` additionally checks every cell has exactly two ring neighbours,
  which catches a stretch that is two blocks wide (where the trace would
  otherwise happily run out along one lane and back along the other). It costs
  several moves per cell, so `wall scan` uses it and `wall build` does not.
----------------------------------------------------------------------------]]
function ring.trace(cfg, strict)
  local start = nav.pos()
  local first = kindBelow(cfg)
  if not first then return nil, "not standing on the ring" end

  local cells = { { x = start.x, z = start.z, kind = first } }

  local startNeighbours = neighbours(cfg)
  if #startNeighbours == 0 then
    return nil, "the ring is a single isolated block"
  end
  if #startNeighbours > 2 then
    return nil, ("the ring is ambiguous at %d,%d -- %d neighbours, expected 2")
                :format(start.x, start.z, #startNeighbours)
  end

  local dir = startNeighbours[1].h
  local kind = probeStep(cfg, dir)
  if not kind then return nil, "lost the ring on the first step" end
  cells[2] = { x = nav.pos().x, z = nav.pos().z, kind = kind }

  local limit = 4 * cfg.ring.searchDistance + 16

  while true do
    local came = (dir + 2) % 4

    if strict then
      local n = neighbours(cfg, came)
      if #n ~= 1 then
        local p = nav.pos()
        return nil, ("the ring is ambiguous at %d,%d -- %d ways on, expected 1")
                    :format(p.x, p.z, #n)
      end
    end

    local moved
    for _, h in ipairs({ dir, (dir + 1) % 4, (dir + 3) % 4 }) do
      local k = probeStep(cfg, h)
      if k then dir, moved = h, k break end
    end

    if not moved then
      local p = nav.pos()
      return nil, ("the ring dead-ends at %d,%d"):format(p.x, p.z)
    end

    local p = nav.pos()
    if p.x == start.x and p.z == start.z then break end   -- loop closed

    cells[#cells + 1] = { x = p.x, z = p.z, kind = moved }
    if #cells > limit then
      return nil, "the ring never closed -- is it a loop?"
    end
  end

  return cells
end

--[[--------------------------------------------------------------------------
  Canonical form.

  Two turtles facing different ways trace the same loop into differently
  rotated coordinates, and may walk it in opposite directions. Rotation is
  fine -- each turtle builds in its own frame -- but the winding and the
  starting cell have to be pinned down, or the index stored in a resume file
  means something different after a reboot.

  Winding is settled by the shoelace formula. A turtle's local frame is always
  a proper rotation of the world, so the sign of the area is the same for all
  of them regardless of which way they face.
----------------------------------------------------------------------------]]
local function signedArea(cells)
  local total = 0
  for i = 1, #cells do
    local p = cells[i]
    local q = cells[(i % #cells) + 1]
    total = total + (p.x * q.z - q.x * p.z)
  end
  return total / 2
end

function ring.canonicalise(cells)
  if #cells < 3 then return nil, "the ring is too small to be a loop" end

  if signedArea(cells) < 0 then
    local flipped = {}
    for i = #cells, 1, -1 do flipped[#flipped + 1] = cells[i] end
    cells = flipped
  end

  local at
  for i, c in ipairs(cells) do
    if c.kind == "anchor" then at = i break end
  end
  if not at then
    return nil, "no anchor block in the ring -- every turtle needs the same "
             .. "starting point, so swap one ring block for the anchor"
  end

  local out = {}
  for i = 0, #cells - 1 do
    out[i + 1] = cells[((at - 1 + i) % #cells) + 1]
  end
  return out
end

--- Find it, walk it, and hand back the canonical cell list.
function ring.survey(cfg, strict)
  local found, err = ring.find(cfg)
  if not found then return nil, err end

  local cells, terr = ring.trace(cfg, strict)
  if not cells then nav.goHome() return nil, terr end

  local canon, cerr = ring.canonicalise(cells)
  nav.goHome()
  if not canon then return nil, cerr end

  return canon
end

--- Bounding box and anchor position, for reporting.
function ring.describe(cells)
  local d = {
    count = #cells,
    minX = math.huge, maxX = -math.huge,
    minZ = math.huge, maxZ = -math.huge,
    anchor = cells[1],
  }
  for _, c in ipairs(cells) do
    if c.x < d.minX then d.minX = c.x end
    if c.x > d.maxX then d.maxX = c.x end
    if c.z < d.minZ then d.minZ = c.z end
    if c.z > d.maxZ then d.maxZ = c.z end
  end
  d.width = d.maxX - d.minX + 1
  d.depth = d.maxZ - d.minZ + 1
  return d
end

--- Is (x,z) one of the ring cells? Used to keep the station off the wall line.
function ring.contains(cells, x, z)
  for _, c in ipairs(cells) do
    if c.x == x and c.z == z then return true end
  end
  return false
end

return ring
