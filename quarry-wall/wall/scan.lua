--[[--------------------------------------------------------------------------
  scan.lua -- working out how tall the wall needs to be.

  The footprint comes from the marker ring, so all that is left is the height,
  and how you find that depends on what is above the pit.

    "roof"  climb until something is overhead. For a pit dug underground, with
            rock above it. Nothing but the ceiling can stop the climb, so cave
            mouths in the pit face are irrelevant.

    "rim"   climb watching the pit face beside you, and call it when that face
            has been open air for a few levels. For a pit open to the sky,
            where there is nothing overhead to stop on.

  "rim" is the fragile one, and only because it has to be: with open sky above,
  the absence of wall is the only signal there is. A cave mouth in the face
  looks exactly like the top of the pit, which is what `confirm` is trying to
  paper over. If your pit has a ceiling, use "roof" and none of that applies.

  Either way this is the one measurement that can disagree between turtles, so
  the course count is typed in at launch rather than measured per turtle.
----------------------------------------------------------------------------]]

local nav  = require("nav")
local ring = require("ring")

local scan = {}

--- The local y of the wall's first course. The marker ring sits at -1, so
--- `aboveRing = 3` puts the base at +2 and leaves two open blocks under it.
function scan.baseY(cfg)
  return (cfg.wall.aboveRing or 1) - 1
end

--- Pick a ring cell on a corner of the bounding box. For "rim" that matters --
--- a corner has pit face on two sides, so one cave does not end the climb.
local function pickCorner(cells)
  local d = ring.describe(cells)
  for _, c in ipairs(cells) do
    if (c.x == d.minX or c.x == d.maxX)
    and (c.z == d.minZ or c.z == d.maxZ) then
      return c
    end
  end
  return cells[1]
end

--[[--------------------------------------------------------------------------
  Climb until the ceiling stops us.

  The turtle ends up in the highest cell it can occupy, and that cell is itself
  a wall cell -- it gets filled from the side, since there is no room to hover
  over it.
----------------------------------------------------------------------------]]
local function climbToRoof(cfg)
  local y = 0

  while y < cfg.height.max do
    if turtle.detectUp() then return y end
    if not nav.up() then return y end
    y = y + 1
  end

  return y, ("reached the %d block climb limit without finding a ceiling -- "
          .. "raise height.max, or set height.stopAt to \"rim\" if this pit is "
          .. "open to the sky"):format(cfg.height.max)
end

--[[--------------------------------------------------------------------------
  Climb watching the pit face, for a pit open to the sky.

  Detecting is free but turning costs a tick, so it faces one wall the whole
  way up and only pays for turns when that face reads air.
----------------------------------------------------------------------------]]
local function climbToRim(cfg, corner)
  local outward = {}
  for h = 0, 3 do
    nav.turnTo(h)
    if turtle.detect() then outward[#outward + 1] = h end
  end

  if #outward == 0 then
    return nil, "no pit face beside the ring -- is the ring against the wall?"
  end

  nav.turnTo(outward[1])

  local top, clear = -1, 0

  for y = 0, cfg.height.max do
    local face = turtle.detect()

    if not face then
      for i = 2, #outward do
        nav.turnTo(outward[i])
        if turtle.detect() then face = true break end
      end
      nav.turnTo(outward[1])
    end

    if face then
      top, clear = y, 0
    else
      clear = clear + 1
      if clear >= cfg.height.confirm then break end
    end

    if not nav.up() then
      return top, "the climb was blocked at +" .. y .. "; the height may be short"
    end
  end

  if top < 0 then
    return nil, "no pit face found at all -- check the ring is at the pit edge"
  end
  return top
end

--[[--------------------------------------------------------------------------
  height -- courses from the wall's base up to whatever stops it.
----------------------------------------------------------------------------]]
function scan.height(cfg, cells)
  local corner = pickCorner(cells)

  if not nav.goTo(corner.x, 0, corner.z) then
    nav.goHome()
    return nil, "could not reach the ring corner to measure height"
  end

  local mode = (cfg.height and cfg.height.stopAt) or "roof"
  local top, note

  if mode == "rim" then
    top, note = climbToRim(cfg, corner)
  else
    top, note = climbToRoof(cfg)
  end

  nav.goHome()

  if not top then return nil, note end

  local base = scan.baseY(cfg)
  local courses = top - base + 1

  if courses < 1 then
    return nil, ("nothing to build -- the wall base sits at +%d but the climb "
              .. "stopped at +%d"):format(base, top)
  end

  return courses, note
end

return scan
