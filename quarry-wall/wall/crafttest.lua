--[[--------------------------------------------------------------------------
  crafttest -- does turtle.craft() care about items outside the 3x3?

  The whole crafting design rests on one assumption: that turtle.craft() reads
  the top-left 3x3 and ignores the other seven slots, which is where materials
  are kept while crafting. If that is wrong, every craft fails as soon as there
  is anything in storage -- which is always.

  This settles it. Run it on a turtle standing at its station, facing the
  supply chest. It borrows cobbled deepslate, runs three crafts that differ
  only in what is sitting outside the recipe, and puts everything back.

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

--- Empty the turtle into the supply chest.
local function putEverythingBack()
  for s = 1, 16 do
    if turtle.getItemCount(s) > 0 then
      turtle.select(s)
      nav.dropAt(cfg.station.supply, turtle.getItemCount(s))
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

--- Lay out exactly `layout` (slot -> count) of cobbled deepslate and nothing
--- else, then try to craft one polished deepslate.
local function attempt(label, layout)
  putEverythingBack()

  -- Pull enough for this layout.
  local want = 0
  for _, n in pairs(layout) do want = want + n end

  while countRaw() < want do
    turtle.select(1)
    if not nav.suckAt(cfg.station.supply, 8) then
      printError("  could not get cobbled deepslate from the supply chest")
      return
    end
  end

  -- Consolidate into slot 1, then deal it out.
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

  -- Whatever is left over in slot 1 beyond its own share goes back, so the
  -- turtle holds exactly the layout and nothing more.
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

  turtle.select(16)
  local ok, err = turtle.craft(1)

  print(("%s"):format(label))
  print(("  slots: %s"):format(table.concat(occupied, " ")))
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
print("Borrowing cobbled deepslate from the supply chest.")
print("")

-- A: the recipe alone. This must work, or something else is wrong.
attempt("A  2x2 in slots 1,2,5,6, nothing else",
        { [1] = 1, [2] = 1, [5] = 1, [6] = 1 })

-- B: same recipe, one stray item in the last row.
attempt("B  same, plus one item in slot 16",
        { [1] = 1, [2] = 1, [5] = 1, [6] = 1, [16] = 1 })

-- C: same recipe, one stray item in the fourth column.
attempt("C  same, plus one item in slot 4",
        { [1] = 1, [2] = 1, [5] = 1, [6] = 1, [4] = 1 })

putEverythingBack()

print("")
print("Everything has been put back in the supply chest.")
print("")
print("If A works and B or C fail, the storage slots are the problem.")
