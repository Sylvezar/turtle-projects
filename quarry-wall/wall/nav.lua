--[[--------------------------------------------------------------------------
  nav.lua -- position tracking and movement that never breaks a block.

  Coordinates are relative to wherever the turtle stood when the program
  started ("home" = 0,0,0). Headings:

      0 = the way the turtle faced at start        3 <- + -> 1
      1 = its right                                     0
      2 = behind it
      3 = its left
----------------------------------------------------------------------------]]

local nav = {}

local DX = { [0] =  0, [1] =  1, [2] =  0, [3] = -1 }
local DZ = { [0] =  1, [1] =  0, [2] = -1, [3] =  0 }

nav.DX, nav.DZ = DX, DZ

local pos = { x = 0, y = 0, z = 0, h = 0 }

function nav.pos()
  return { x = pos.x, y = pos.y, z = pos.z, h = pos.h }
end

function nav.setPos(p)
  pos.x, pos.y, pos.z, pos.h = p.x, p.y, p.z, p.h % 4
end

function nav.fuel()
  local lvl = turtle.getFuelLevel()
  if lvl == "unlimited" then return math.huge end
  return lvl
end

-- A move can fail because a mob is standing in the cell, which clears on its
-- own. It can also fail because a block is there, which never does. Retry a
-- few times, but bail immediately on "out of fuel" -- retrying that is just a
-- slower way to be stuck.
local RETRIES = 5

local function attempt(move)
  for i = 1, RETRIES do
    local ok, why = move()
    if ok then return true end
    if why and why:lower():find("fuel") then return false, "fuel" end
    if i < RETRIES then sleep(0.3) end
  end
  return false, "blocked"
end

function nav.forward()
  local ok, why = attempt(turtle.forward)
  if ok then
    pos.x = pos.x + DX[pos.h]
    pos.z = pos.z + DZ[pos.h]
  end
  return ok, why
end

function nav.back()
  local ok, why = attempt(turtle.back)
  if ok then
    pos.x = pos.x - DX[pos.h]
    pos.z = pos.z - DZ[pos.h]
  end
  return ok, why
end

function nav.up()
  local ok, why = attempt(turtle.up)
  if ok then pos.y = pos.y + 1 end
  return ok, why
end

function nav.down()
  local ok, why = attempt(turtle.down)
  if ok then pos.y = pos.y - 1 end
  return ok, why
end

function nav.turnTo(h)
  h = h % 4
  while pos.h ~= h do
    if (pos.h + 1) % 4 == h then
      turtle.turnRight()
      pos.h = (pos.h + 1) % 4
    else
      turtle.turnLeft()
      pos.h = (pos.h + 3) % 4
    end
  end
end

--- Turn to face `h`, then take one step. Returns false if the way is blocked.
function nav.step(h)
  nav.turnTo(h)
  return nav.forward()
end

--[[--------------------------------------------------------------------------
  goTo -- greedy movement with detours, and no digging ever.

  Order of preference is climb, then horizontal, then descend. Climbing first
  is what keeps the turtle from walking into the side of the wall it is
  standing on; descending last keeps it from settling onto a course it still
  has to fly over.

  When every preferred axis is blocked it sidesteps before it climbs, because
  climbing to get past an obstacle and then immediately wanting to descend
  again is how a greedy mover ends up oscillating in place.

  The step budget is the real guard against that: it is generous enough for
  any reasonable detour and finite enough that a boxed-in turtle gives up and
  says so rather than grinding fuel forever.
----------------------------------------------------------------------------]]
--- Would `m` exactly undo `prev`?
local function reverses(prev, m)
  if prev == nil then return false end
  if prev == "up"   then return m == "down" end
  if prev == "down" then return m == "up"   end
  if type(prev) == "number" and type(m) == "number" then
    return (prev + 2) % 4 == m
  end
  return false
end

function nav.goTo(tx, ty, tz)
  local budget = (math.abs(tx - pos.x) + math.abs(ty - pos.y)
               + math.abs(tz - pos.z)) * 8 + 80

  local last = nil

  local function attemptMove(m)
    local okMove, why
    if m == "up" then
      okMove, why = nav.up()
    elseif m == "down" then
      okMove, why = nav.down()
    else
      okMove, why = nav.step(m)
    end
    if okMove then last = m end
    return okMove, why
  end

  for _ = 1, budget do
    if pos.x == tx and pos.y == ty and pos.z == tz then return true end

    -- One move out, take it directly. If it will not go, the target cell is
    -- occupied and no amount of walking around will help -- say so straight
    -- away instead of burning the whole budget circling a solid block. This
    -- matters: placing a course always tries the cell above the target first,
    -- and during a seal that cell is the wall itself, every single time.
    if math.abs(tx - pos.x) + math.abs(ty - pos.y) + math.abs(tz - pos.z) == 1 then
      local m
      if ty > pos.y then m = "up"
      elseif ty < pos.y then m = "down"
      elseif tx ~= pos.x then m = (tx > pos.x) and 1 or 3
      else m = (tz > pos.z) and 0 or 2 end

      local okMove, why = attemptMove(m)
      if okMove then return true end
      if why == "fuel" then return false, "out of fuel" end
      return false, "target blocked"
    end

    -- Preferred moves first, then detours. Climbing comes before lining up
    -- horizontally so the turtle gains height over an obstacle rather than
    -- walking into its side.
    local opts = {}
    if ty > pos.y then opts[#opts + 1] = "up" end
    if ty < pos.y then opts[#opts + 1] = "down" end
    if tx ~= pos.x then opts[#opts + 1] = (tx > pos.x) and 1 or 3 end
    if tz ~= pos.z then opts[#opts + 1] = (tz > pos.z) and 0 or 2 end

    opts[#opts + 1] = "up"
    opts[#opts + 1] = (pos.h + 1) % 4
    opts[#opts + 1] = (pos.h + 3) % 4
    opts[#opts + 1] = "down"

    local moved, why

    -- A greedy mover with no memory oscillates: it sidesteps around an
    -- obstacle, then on the very next step corrects the axis it just moved
    -- on and walks straight back into it. Refusing to immediately undo the
    -- last move is enough to break that, and costs one variable.
    for _, m in ipairs(opts) do
      if not reverses(last, m) then
        moved, why = attemptMove(m)
        if moved then break end
        if why == "fuel" then return false, "out of fuel" end
      end
    end

    -- Genuinely nowhere else to go: backing up is better than giving up.
    if not moved then
      for _, m in ipairs(opts) do
        moved, why = attemptMove(m)
        if moved then break end
      end
    end

    if not moved then return false, "boxed in" end
  end

  if pos.x == tx and pos.y == ty and pos.z == tz then return true end
  return false, "no path"
end

function nav.goHome()
  local ok, err = nav.goTo(0, 0, 0)
  if ok then nav.turnTo(0) end
  return ok, err
end

--[[--------------------------------------------------------------------------
  Station access.

  A container is described by where the turtle has to stand to reach it and
  which way it then looks:

      { offset = {0, 1, 0}, side = "front", heading = 0 }

  The offset is what lets a fuel chest sit on top of the supply chest: the
  turtle steps up one block, and the chest it could not reach from the floor
  is now in front of it.
----------------------------------------------------------------------------]]

--- Go and stand where `spec` says, facing the right way.
function nav.reach(spec)
  if not spec then return false end
  local o = spec.offset or { 0, 0, 0 }
  if not nav.goTo(o[1], o[2], o[3]) then return false end
  if (spec.side or "front") == "front" then nav.turnTo(spec.heading or 0) end
  return true
end

function nav.suckAt(spec, count)
  if not nav.reach(spec) then return false end
  local side = spec.side or "front"
  if side == "up"   then return turtle.suckUp(count) end
  if side == "down" then return turtle.suckDown(count) end
  return turtle.suck(count)
end

function nav.dropAt(spec, count)
  if not nav.reach(spec) then return false end
  local side = spec.side or "front"
  if side == "up"   then return turtle.dropUp(count) end
  if side == "down" then return turtle.dropDown(count) end
  return turtle.drop(count)
end

return nav
