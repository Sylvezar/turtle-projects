--[[--------------------------------------------------------------------------
  inv.lua -- inventory bookkeeping.

  A turtle's 16 slots are laid out 4 wide:

        1   2   3 | 4
        5   6   7 | 8
        9  10  11 | 12
      ---------------
       13  14  15   16

  turtle.craft() reads the top-left 3x3 as the crafting grid, so slots
  1,2,3,5,6,7,9,10,11 have to hold exactly the recipe and nothing else -- a
  stray stack in slot 3 turns a 2x2 recipe into a 3x3 one that matches nothing.
  That leaves slots 4, 8, 12, 13, 14, 15 and 16 as the only place to keep
  materials while crafting, which is why a crafted course only carries 7
  stacks per trip while a plain cobbled deepslate course carries all 16.
----------------------------------------------------------------------------]]

local inv = {}

inv.GRID    = { 1, 2, 3, 5, 6, 7, 9, 10, 11 }
inv.STORAGE = { 4, 8, 12, 13, 14, 15, 16 }
inv.ALL     = { 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16 }

--- Maps a (row, col) of the 3x3 crafting grid to a turtle slot.
function inv.gridSlot(row, col)
  return (row - 1) * 4 + col
end

function inv.nameAt(slot)
  local d = turtle.getItemDetail(slot)
  return d and d.name or nil
end

function inv.count(name)
  local n = 0
  for _, s in ipairs(inv.ALL) do
    if inv.nameAt(s) == name then n = n + turtle.getItemCount(s) end
  end
  return n
end

--- Every distinct item on board, as { [name] = count }.
function inv.contents()
  local t = {}
  for _, s in ipairs(inv.ALL) do
    local n = inv.nameAt(s)
    if n then t[n] = (t[n] or 0) + turtle.getItemCount(s) end
  end
  return t
end

function inv.firstEmpty(range)
  for _, s in ipairs(range or inv.ALL) do
    if turtle.getItemCount(s) == 0 then return s end
  end
  return nil
end

function inv.freeSlots(range)
  local n = 0
  for _, s in ipairs(range or inv.ALL) do
    if turtle.getItemCount(s) == 0 then n = n + 1 end
  end
  return n
end

--- Select a slot holding `name`, preferring the emptiest so partial stacks get
--- used up rather than accumulating. Returns false if we have none.
function inv.selectItem(name)
  local best, bestCount = nil, math.huge
  for _, s in ipairs(inv.ALL) do
    if inv.nameAt(s) == name then
      local c = turtle.getItemCount(s)
      if c < bestCount then best, bestCount = s, c end
    end
  end
  if not best then return false end
  turtle.select(best)
  return true
end

--- Empty `src` into the storage slots, merging into part-stacks first so we
--- don't burn a whole slot on a handful of leftovers.
function inv.moveOut(src)
  if turtle.getItemCount(src) == 0 then return true end
  local name = inv.nameAt(src)
  turtle.select(src)

  for _, t in ipairs(inv.STORAGE) do
    if turtle.getItemCount(src) == 0 then return true end
    if t ~= src and inv.nameAt(t) == name then turtle.transferTo(t) end
  end
  for _, t in ipairs(inv.STORAGE) do
    if turtle.getItemCount(src) == 0 then return true end
    if t ~= src and turtle.getItemCount(t) == 0 then turtle.transferTo(t) end
  end

  return turtle.getItemCount(src) == 0
end

--- Clear the 3x3 so a craft can be staged (or so its output can be swept out
--- afterwards). Fails if storage cannot absorb everything.
function inv.clearGrid()
  for _, s in ipairs(inv.GRID) do
    if turtle.getItemCount(s) > 0 then
      if not inv.moveOut(s) then
        return false, "no room to clear the crafting grid"
      end
    end
  end
  return true
end

--- Stage exactly `count` of `name` into grid slot `dst`, drawing only from
--- storage so we never cannibalise a slot we already staged.
function inv.stage(dst, name, count)
  local have = turtle.getItemCount(dst)
  if have > 0 and inv.nameAt(dst) ~= name then return false end

  for _, s in ipairs(inv.STORAGE) do
    if have >= count then break end
    if inv.nameAt(s) == name then
      turtle.select(s)
      turtle.transferTo(dst, count - have)
      have = turtle.getItemCount(dst)
    end
  end

  return have >= count
end

--- Consolidate part-stacks of the same item so free slots come back.
function inv.compact()
  for i = #inv.ALL, 1, -1 do
    local src = inv.ALL[i]
    local name = inv.nameAt(src)
    if name then
      for j = 1, i - 1 do
        local dst = inv.ALL[j]
        if turtle.getItemCount(src) == 0 then break end
        if inv.nameAt(dst) == name and turtle.getItemSpace(dst) > 0 then
          turtle.select(src)
          turtle.transferTo(dst)
        end
      end
    end
  end
end

return inv
