--[[--------------------------------------------------------------------------
  monitor -- one screen showing every turtle on the job.

  Runs on an ordinary computer with a wireless modem, anywhere in range. It
  listens for the broadcasts the turtles send and shows what each one is doing,
  collecting all their holes into a single wall_holes.txt on this computer.

  It is a listener and nothing more. It never sends anything, the turtles never
  wait for it, and starting or stopping it has no effect on a run in progress.

  Its one active job is checking that the bands tile. Eight turtles each told
  by hand which index they are is the one place a typo does real damage -- two
  turtles on index 3 means a doubled band and a gap somewhere else, which you
  would otherwise not discover until you looked at the finished wall. The
  coverage line on the bottom catches it in the first few seconds.

  Usage:  monitor [protocol]
----------------------------------------------------------------------------]]

local PROTOCOL  = ... or "wall"
local HOLES     = "wall_holes.txt"
local STALE     = 30        -- seconds of silence before a turtle is "quiet"
local SIDES     = { "left", "right", "top", "bottom", "front", "back" }

--[[-- modem ---------------------------------------------------------------]]

local function openModem()
  for _, side in ipairs(SIDES) do
    if peripheral.getType(side) == "modem" then
      rednet.open(side)
      return side
    end
  end
  return nil
end

local side = openModem()
if not side then
  printError("No modem attached. Put a wireless or ender modem on this")
  printError("computer and run monitor again.")
  return
end

--[[-- state ---------------------------------------------------------------]]

local seen      = {}        -- [index] = latest status
local holes     = {}
local holeSeen  = {}
local totalCourses

local function now() return os.clock() end

local function noteHole(msg)
  local key = ("%s/%s/%s"):format(tostring(msg.turtle), tostring(msg.course),
                                  tostring(msg.cell))
  if holeSeen[key] then return end
  holeSeen[key] = true

  local line = ("turtle %-2s %s %-3s  ring+%-3s  cell %s/%s  %s")
               :format(tostring(msg.turtle), msg.phase or "course",
                       tostring(msg.course), tostring(msg.height),
                       tostring(msg.cell), tostring(msg.cells),
                       tostring(msg.reason))
  holes[#holes + 1] = line

  local f = fs.open(HOLES, "a")
  if f then f.writeLine(line) f.close() end
end

local function handle(msg)
  if type(msg) ~= "table" or not msg.turtle then return end

  if msg.courses then totalCourses = msg.courses end

  if msg.kind == "hole" then
    noteHole(msg)
    return
  end

  local t = seen[msg.turtle] or {}
  for k, v in pairs(msg) do t[k] = v end
  t.last = now()
  seen[msg.turtle] = t
end

--[[--------------------------------------------------------------------------
  Do the bands tile?

  Every course from 1 to the total should be claimed by exactly one turtle.
  Anything else is a hand-typed index gone wrong.
----------------------------------------------------------------------------]]
local function coverage()
  if not totalCourses then return "waiting for turtles", false end

  local claimed = {}
  for _, t in pairs(seen) do
    if t.from and t.to then
      for c = t.from, t.to do claimed[c] = (claimed[c] or 0) + 1 end
    end
  end

  local gap, dup
  for c = 1, totalCourses do
    local n = claimed[c] or 0
    if n == 0 and not gap then gap = c end
    if n > 1 and not dup then dup = c end
  end

  if dup then return ("OVERLAP at course %d -- two turtles share an index"):format(dup), true end
  if gap then return ("unclaimed from course %d"):format(gap), false end
  return ("coverage 1-%d complete"):format(totalCourses), false
end

--[[-- drawing -------------------------------------------------------------]]

local function pad(s, n)
  s = tostring(s)
  if #s >= n then return s:sub(1, n) end
  return s .. string.rep(" ", n - #s)
end

local function rpad(s, n)
  s = tostring(s)
  if #s >= n then return s:sub(1, n) end
  return string.rep(" ", n - #s) .. s
end

--- Colour the text if this terminal can, and quietly carry on if it cannot --
--- a plain computer has no setTextColour at all.
local function colour(name)
  if not term.setTextColour then return end
  if not colours or not colours[name] then return end
  pcall(term.setTextColour, colours[name])
end

local function draw()
  local w, h = term.getSize()
  term.clear()
  term.setCursorPos(1, 1)

  local n = 0
  for _ in pairs(seen) do n = n + 1 end

  print(("wall monitor    %d turtle%s    %d hole%s")
        :format(n, n == 1 and "" or "s", #holes, #holes == 1 and "" or "s"))
  print(string.rep("-", math.min(w, 50)))
  print(" #  band      doing            done  skip miss")

  local indices = {}
  for i in pairs(seen) do indices[#indices + 1] = i end
  table.sort(indices)

  local row = 4
  for _, i in ipairs(indices) do
    if row >= h - 2 then break end
    local t = seen[i]

    local band = (t.from and t.to) and (t.from .. "-" .. t.to) or "?"
    local doing

    if now() - (t.last or 0) > STALE then
      doing = "quiet"
    elseif t.state == "done" then
      doing = "done"
    elseif t.state == "stopped" then
      doing = "STOPPED"
    elseif t.state == "restocking" then
      doing = "restock c" .. tostring(t.course)
    else
      doing = ("c%s %s/%s"):format(tostring(t.course), tostring(t.cell),
                                   tostring(t.cells))
    end

    print((" %-2s %s %s %s %s %s")
          :format(tostring(i), pad(band, 9), pad(doing, 16),
                  rpad(t.placed or 0, 5), rpad(t.skipped or 0, 5),
                  rpad(t.missed or 0, 4)))
    row = row + 1
  end

  term.setCursorPos(1, h - 1)
  print(string.rep("-", math.min(w, 50)))

  local text, bad = coverage()
  if bad then colour("red") end
  write(text)
  colour("white")
end

--[[-- loop ----------------------------------------------------------------]]

print("Listening on protocol '" .. PROTOCOL .. "' via the " .. side .. " modem.")
print("Holes are appended to " .. HOLES .. ". Ctrl+T to stop.")
sleep(1.5)

while true do
  local _, msg = rednet.receive(PROTOCOL, 1)
  if msg then handle(msg) end
  draw()
end
