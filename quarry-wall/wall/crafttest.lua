--[[--------------------------------------------------------------------------
  crafttest -- does turtle.craft() care about items outside the 3x3?

  The whole crafting design rests on one assumption: that turtle.craft() reads
  the top-left 3x3 and ignores the other seven slots, which is where materials
  are kept while crafting. If that is wrong, every craft fails as soon as there
  is anything in storage -- which is always.

  This settles it. Run it on a turtle standing at its station, facing the
  supply chest. It borrows cobbled deepslate, runs three crafts that differ
  only in what is sitting outside the recipe, and puts everything back.

  Items are routed by type when the turtle is emptied: fuel goes to the fuel
  chest, never into the supply chest. Putting coal in with the deepslate breaks
  the supply chest for every turtle afterwards, since `suck` takes whatever is
  in the first slot and cannot be asked for a particular item.

  Nothing is placed and nothing is broken.
----------------------------------------------------------------------------]]

local here = fs.getDir(shell.getRunningProgram())
package.path = here .. "/?.lua;" .. package.path

local cfg = require("config")
local nav = require("nav")

local RAW = "minecraft:cobbled_deepslate"

local function nameAt(slot)
  local d = turtle.getItemDetail(slot)
  return d and d.name or nil
end

--- Is the selected slot something the turtle would burn?
local function isFuel()
  return turtle.refuel(0) == true
end

--[[--------------------------------------------------------------------------
  Empty the turtle, putting each thing where it belongs.
----------------------------------------------------------------------------]]
local function stow()
  for s = 1, 16 do
    if turtle.getItemCount(s) > 0 then
      turtle.select(s)
      local count = turtle.getItemCount(s)

      if nameAt(s) == RAW then
        nav.dropAt(cfg.station.supply, count)

      elseif isFuel() then
        -- Fuel chest if there is one; otherwise burn it rather than
        -- contaminate the supply chest. Burning fuel is what it is for.
        if cfg.station.fuel then
          turtle.select(s)
          nav.dropAt(cfg.station.fuel, count)
        else
          turtle.select(s)
          while turtle.getItemCount(s) > 0 do
            if not turtle.refuel(1) then break end
          end
        end

      else
        printError(("  slot %d holds %s -- leaving it alone")
                   :format(s, tostring(nameAt(s))))
      end
    end
  end
end

local function countRaw()
  local n = 0
  for s = 1, 16 do
    if nameAt(s) == RAW then n = n + turtle.getItemCount(s) end
  end
  return n
end

--[[--------------------------------------------------------------------------
  Take cobbled deepslate from the supply chest, and only that.

  `suck` cannot be asked for a particular item, so anything else that comes up
  is routed onward rather than kept -- which also tidies the supply chest if
  something has already been dropped in there by mistake.
----------------------------------------------------------------------------]]
local function borrow(want)
  for _ = 1, 40 do
    if countRaw() >= want then return true end

    local slot
    for s = 16, 1, -1 do
      if turtle.getItemCount(s) == 0 then slot = s break end
    end
    if not slot then return false end

    turtle.select(slot)
    if not nav.suckAt(cfg.station.supply, 8) then return false end

    local got = nameAt(slot)
    if got and got ~= RAW then
      turtle.select(slot)
      if isFuel() and cfg.station.fuel then
        turtle.select(slot)
        nav.dropAt(cfg.station.fuel, turtle.getItemCount(slot))
        print(("  moved %s out of the supply chest"):format(got))
      else
        printError(("  supply chest contains %s"):format(got))
        turtle.select(slot)
        nav.dropAt(cfg.station.supply, turtle.getItemCount(slot))
        return false
      end
    end
  end

  return countRaw() >= want
end

--[[--------------------------------------------------------------------------
  Lay out exactly `layout` of cobbled deepslate and nothing else, then try one
  2x2 craft.
----------------------------------------------------------------------------]]
local function attempt(label, layout)
  stow()

  local want = 0
  for _, n in pairs(layout) do want = want + n end

  if not borrow(want) then
    printError(label .. ": could not get cobbled deepslate")
    return
  end

  -- Consolidate, then deal out exactly the layout.
  for s = 2, 16 do
    if nameAt(s) == RAW then
      turtle.select(s)
      turtle.transferTo(1)
    end
  end

  for slot, n in pairs(layout) do
    if slot ~= 1 then
      turtle.select(1)
      turtle.transferTo(slot, n)
    end
  end

  local keep = layout[1] or 0
  if turtle.getItemCount(1) > keep then
    turtle.select(1)
    nav.dropAt(cfg.station.supply, turtle.getItemCount(1) - keep)
  end

  local occupied = {}
  for s = 1, 16 do
    if turtle.getItemCount(s) > 0 then
      occupied[#occupied + 1] = s .. "x" .. turtle.getItemCount(s)
    end
  end

  turtle.select(3)
  local ok, err = turtle.craft(1)

  print(label)
  print("  slots: " .. table.concat(occupied, " "))
  if ok then
    print("  craft: OK")
  else
    printError("  craft: " .. tostring(err))
  end
end

--[[--------------------------------------------------------------------------]]

if not turtle.craft then
  printError("This turtle has no crafting table upgrade.")
  return
end

print("Testing what turtle.craft() will accept.")
print("Fuel goes to the fuel chest, not the supply chest.")
print("")

-- A: the recipe alone. This must work, or something else is wrong.
attempt("A  2x2 in slots 1,2,5,6, nothing else",
        { [1] = 1, [2] = 1, [5] = 1, [6] = 1 })

-- B: same recipe, one stray item in the bottom row.
attempt("B  same, plus one item in slot 16",
        { [1] = 1, [2] = 1, [5] = 1, [6] = 1, [16] = 1 })

-- C: same recipe, one stray item in the fourth column.
attempt("C  same, plus one item in slot 4",
        { [1] = 1, [2] = 1, [5] = 1, [6] = 1, [4] = 1 })

stow()

print("")
print("Put back. If A works and B or C fail, the storage slots are the")
print("problem and the crafting engine needs rebuilding.")
