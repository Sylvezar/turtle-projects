--[[--------------------------------------------------------------------------
  scan.lua -- working out how tall the wall needs to be.

  The footprint comes from the marker ring now, so all that is left to measure
  is the height. The turtle stands on a corner of the ring and climbs, watching
  the pit faces that meet there. Once they have been open air for `confirm`
  levels running, the rim is below it.

  This is the one measurement that can still disagree between turtles -- a
  cave at the corner one of them picked will cut its climb short. That is why
  the course count is typed in at launch rather than measured per turtle:
  measure once, check it looks right, and give every turtle the same number.
----------------------------------------------------------------------------]]

local nav  = require("nav")
local ring = require("ring")

local scan = {}

--- The local y of the wall's first course. The marker ring sits at -1, so
--- `aboveRing = 3` puts the base at +2 and leaves two open blocks under it.
function scan.baseY(cfg)
  return (cfg.wall.aboveRing or 1) - 1
end

--- Pick a ring cell on a corner of the bounding box -- it has pit face on two
--- sides, so a cave in one of them does not end the climb on its own.
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
  height -- courses from the wall's base up to the rim.
----------------------------------------------------------------------------]]
function scan.height(cfg, cells)
  local corner = pickCorner(cells)

  if not nav.goTo(corner.x, 0, corner.z) then
    nav.goHome()
    return nil, "could not reach the ring corner to measure height"
  end

  -- Outward is wherever there is rock at ring level.
  local outward = {}
  for h = 0, 3 do
    nav.turnTo(h)
    if turtle.detect() then outward[#outward + 1] = h end
  end

  if #outward == 0 then
    nav.goHome()
    return nil, "no pit face beside the ring -- is the ring against the wall?"
  end

  local top, clear, note = -1, 0, nil

  for y = 0, cfg.height.max do
    local face = false
    for _, h in ipairs(outward) do
      nav.turnTo(h)
      if turtle.detect() then face = true end
    end

    if face then
      top, clear = y, 0
    else
      clear = clear + 1
      if clear >= cfg.height.confirm then break end
    end

    if not nav.up() then
      note = "the climb was blocked at +" .. y .. "; the height may be short"
      break
    end
  end

  nav.goHome()

  if top < 0 then
    return nil, "no pit face found at all -- check the ring is at the pit edge"
  end

  local base = scan.baseY(cfg)
  local courses = top - base + 1
  if courses < 1 then
    return nil, ("the rim is below the wall base -- aboveRing is %d but the "
              .. "pit face stops at +%d"):format(cfg.wall.aboveRing, top)
  end

  return courses, note
end

return scan
