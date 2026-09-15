--[[--------------------------------------------------------------------------
  frame.lua -- lining up two turtles' coordinates without GPS.

  Every turtle counts from wherever it was standing when it started, so no two
  of them agree on where anything is. Normally that does not matter: each one
  traces the ring itself and builds in its own numbers. But tracing a 162 cell
  ring eight times, one at a time so they do not collide, is most of the launch.

  The way out is a second, small ring of markers round the launch pad. Tracing
  is anchored at a marker block and wound in a fixed direction, so any two
  turtles walking that little ring come back with the SAME cells in the SAME
  order -- cell 3 of mine is cell 3 of yours, the same physical block, written
  in two different coordinate systems.

  Two cells that are known to be the same block is exactly enough to pin down
  the rotation and offset between the two systems. After that, one turtle can
  walk the big ring and everyone else can translate its answer into their own
  numbers without leaving the pad.

  The rotation is always a quarter turn -- turtles only ever face four ways --
  so there are four candidates and we simply try them.
----------------------------------------------------------------------------]]

local frame = {}

--- Rotate a vector by `r` quarter turns. Which way round does not matter, as
--- long as it is consistent: derive() tries all four and keeps whichever one
--- actually maps the rings onto each other.
local function rot(x, z, r)
  if r == 0 then return  x,  z end
  if r == 1 then return  z, -x end
  if r == 2 then return -x, -z end
  return -z, x
end

frame.rot = rot

--- Put a cell of the other turtle's frame into mine.
function frame.apply(t, cell)
  local x, z = rot(cell.x - t.px, cell.z - t.pz, t.r)
  return { x = x + t.mx, z = z + t.mz, kind = cell.kind }
end

--- Does this transform map every one of their cells onto mine?
function frame.verify(t, mine, theirs)
  if #mine ~= #theirs then return false end
  for i = 1, #mine do
    local c = frame.apply(t, theirs[i])
    if c.x ~= mine[i].x or c.z ~= mine[i].z then return false end
  end
  return true
end

--[[--------------------------------------------------------------------------
  derive -- the transform taking `theirs` into `mine`.

  Both lists must be traces of the same ring, which means the same cells in the
  same order. The first two give the rotation; the first gives the offset; and
  then the whole list is checked, because a transform that lines up two cells
  but not the rest means the traces are not of the same ring at all -- and
  building a wall on that would put it somewhere quite wrong.
----------------------------------------------------------------------------]]
function frame.derive(mine, theirs)
  if type(mine) ~= "table" or type(theirs) ~= "table" then
    return nil, "missing a trace"
  end
  if #mine < 2 or #theirs < 2 then
    return nil, "a ring of fewer than two cells cannot line anything up"
  end
  if #mine ~= #theirs then
    return nil, ("traces disagree: %d cells against %d"):format(#mine, #theirs)
  end

  local tdx, tdz = theirs[2].x - theirs[1].x, theirs[2].z - theirs[1].z
  local mdx, mdz = mine[2].x - mine[1].x, mine[2].z - mine[1].z

  for r = 0, 3 do
    local rx, rz = rot(tdx, tdz, r)
    if rx == mdx and rz == mdz then
      local t = {
        r = r,
        px = theirs[1].x, pz = theirs[1].z,
        mx = mine[1].x,   mz = mine[1].z,
      }
      if frame.verify(t, mine, theirs) then return t end
    end
  end

  return nil, "the two traces do not describe the same ring"
end

--- Whole list, their frame to mine.
function frame.map(t, cells)
  local out = {}
  for i, c in ipairs(cells) do out[i] = frame.apply(t, c) end
  return out
end

--[[--------------------------------------------------------------------------
  Rings travel over rednet as a flat list of numbers rather than a table per
  cell: 162 cells is a few kilobytes either way, and this is the cheaper way
  to send it.
----------------------------------------------------------------------------]]
function frame.flatten(cells)
  local flat = {}
  for i, c in ipairs(cells) do
    flat[i * 2 - 1] = c.x
    flat[i * 2]     = c.z
  end
  return flat
end

function frame.unflatten(flat)
  if type(flat) ~= "table" then return nil end
  local cells = {}
  for i = 1, #flat, 2 do
    cells[#cells + 1] = { x = flat[i], z = flat[i + 1] }
  end
  -- The anchor is always first; the trace is rotated to make it so.
  if cells[1] then cells[1].kind = "anchor" end
  return cells
end

return frame
