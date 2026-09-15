--[[--------------------------------------------------------------------------
  monitor -- assign the turtles their slices, launch them, and watch.

  Runs on an ordinary computer with a wireless modem, anywhere in range.

    lobby    turtles running `wall join` check in and wait
    scan     one turtle walks the wall ring; the rest trace the little ring
             round the launch pad, one at a time
    share    the scout's ring is passed to everyone, who translate it into
             their own coordinates
    watch    one screen showing what every turtle is doing

  Why the scan phase is shaped like that: walking the wall ring is a lap of the
  whole perimeter, and turtles cannot do it at once without blocking each
  other's traces. Having all eight walk it one at a time was most of the
  launch. Now one walks it, everyone else traces twenty-odd blocks round the
  pad, and two traces of that little ring are enough to line two turtles'
  coordinate systems up -- so the scout's answer can simply be handed out.

  The scout waits out on the ring until the others have finished, because
  coming back through them would spoil the traces it is waiting for.

  Usage:  monitor [protocol]
----------------------------------------------------------------------------]]

local PROTOCOL = ... or "wall"
local HOLES    = "wall_holes.txt"
local STALE    = 30
local SIDES    = { "left", "right", "top", "bottom", "front", "back" }

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

local phase    = "lobby"
local waiting  = {}          -- enlistment order: { id =, label = }
local enlisted = {}
local seen     = {}          -- assigned index -> latest status
local holes, holeSeen = {}, {}

local courses
local scoutData              -- { inner =, outer = } from the scout
local innerDone = {}         -- index -> true
local nextInner              -- who to send off to trace the pad ring next
local readyCells = {}        -- index -> cell count it worked out
local halted, note, assigned

local function now() return os.clock() end

local function indexOf(id)
  for i, t in ipairs(waiting) do
    if t.id == id then return i end
  end
  return nil
end

local function tell(id, msg)
  msg.to = id
  rednet.broadcast(msg, PROTOCOL)
end

--[[-- incoming ------------------------------------------------------------]]

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

--- Everyone but the scout has traced the pad ring, and the scout has reported.
local function scanComplete()
  if not scoutData then return false end
  for i = 2, #waiting do
    if not innerDone[i] then return false end
  end
  return true
end

local function sendNextInner()
  if nextInner and nextInner <= #waiting then
    tell(waiting[nextInner].id, { kind = "role", role = "inner" })
  end
end

--- Hand out the slices. Only once every turtle has said what it worked out,
--- and only if they all worked out the same ring.
local function assignAll()
  if assigned then return end

  local size
  for i = 1, #waiting do
    local n = readyCells[i]
    if not n then return end
    if size and n ~= size then
      halted = true
      note = ("turtle %d worked out %d cells, others %d"):format(i, n, size)
      return
    end
    size = n
  end

  -- The scout measured the height out at the ring, so this is a confirmation
  -- rather than something to look up.
  term.clear()
  term.setCursorPos(1, 1)
  print(("All %d turtles have the ring, %d cells."):format(#waiting, size))
  print("")
  if courses then
    print(("The scout measured %d courses."):format(courses))
  else
    print("The scout did not report a height.")
  end
  print("")
  write(("Courses to build [%s]: "):format(tostring(courses or "")))

  local typed = read()
  if typed ~= "" then courses = tonumber(typed) end
  while not courses or courses < 1 or courses ~= math.floor(courses) do
    write("  enter a whole number of at least 1: ")
    courses = tonumber(read())
  end

  for i, t in ipairs(waiting) do
    tell(t.id, { kind = "assign", index = i,
                 turtles = #waiting, courses = courses })
  end

  assigned = true
  phase = "watch"
end

local function handle(msg)
  if type(msg) ~= "table" then return end

  if msg.kind == "enlist" and msg.id then
    if phase == "lobby" then
      if not enlisted[msg.id] then
        enlisted[msg.id] = true
        waiting[#waiting + 1] = { id = msg.id, label = msg.label }
      end
      return
    end

    -- A turtle we already know, shouting again: it crashed and was restarted.
    -- Put it back where the fleet has got to rather than making the whole
    -- launch start over, which is otherwise the only way back in.
    local i = indexOf(msg.id)
    if not i then return end

    if phase == "scan" then
      if i == 1 then
        tell(msg.id, { kind = "role", role = "scout" })
      elseif nextInner and i <= nextInner then
        tell(msg.id, { kind = "role", role = "inner" })
      end
    elseif phase == "share" and scoutData then
      tell(msg.id, { kind = "rings",
                     inner = scoutData.inner, outer = scoutData.outer })
    elseif phase == "watch" and courses then
      tell(msg.id, { kind = "assign", index = i,
                     turtles = #waiting, courses = courses })
      note = ("turtle %d rejoined"):format(i)
    end
    return
  end

  if msg.kind == "hole" then noteHole(msg) return end

  local who = msg.id and indexOf(msg.id) or nil

  if msg.kind == "scanned" and who then
    if msg.role == "scout" then
      scoutData = { inner = msg.inner, outer = msg.outer }
      if msg.courses then courses = msg.courses end
    else
      innerDone[who] = true
      nextInner = nextInner + 1
      sendNextInner()
    end
    if scanComplete() then
      tell(waiting[1].id, { kind = "comehome" })
    end
    return
  end

  if msg.kind == "padclear" and who == 1 then
    -- The scout has cleared the launch pad; the others can start on it now.
    if not nextInner then
      nextInner = 2
      sendNextInner()
    end
    return
  end

  if msg.kind == "athome" and who == 1 then
    rednet.broadcast({ kind = "rings",
                       inner = scoutData.inner,
                       outer = scoutData.outer }, PROTOCOL)
    phase = "share"
    return
  end

  if msg.kind == "ready" and who then
    readyCells[who] = msg.cells
    assignAll()
    return
  end

  if msg.kind == "rejoined" and who then
    halted = false
    return
  end

  if not msg.turtle then return end

  local t = seen[msg.turtle] or {}
  for k, v in pairs(msg) do t[k] = v end
  t.last = now()
  seen[msg.turtle] = t

  if t.state == "stopped" then
    halted = true
    note = ("turtle %s: %s"):format(tostring(msg.turtle),
                                    tostring(t.error or "stopped"))
  end
end

--[[-- coverage ------------------------------------------------------------]]

local function coverage()
  if not courses then return "waiting for turtles", false end

  local claimed = {}
  for _, t in pairs(seen) do
    if t.from and t.to then
      for c = t.from, t.to do claimed[c] = (claimed[c] or 0) + 1 end
    end
  end

  local gap, dup
  for c = 1, courses do
    local n = claimed[c] or 0
    if n == 0 and not gap then gap = c end
    if n > 1 and not dup then dup = c end
  end

  if dup then
    return ("OVERLAP at course %d -- two turtles share a slice"):format(dup), true
  end
  if gap then return ("unclaimed from course %d"):format(gap), false end
  return ("coverage 1-%d complete"):format(courses), false
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

local function colour(name)
  if not term.setTextColour then return end
  if not colours or not colours[name] then return end
  pcall(term.setTextColour, colours[name])
end

local function header(text)
  local w = term.getSize()
  term.clear()
  term.setCursorPos(1, 1)
  print("wall monitor -- " .. text)
  print(string.rep("-", math.min(w, 50)))
end

local function footer(text, bad)
  local _, h = term.getSize()
  term.setCursorPos(1, h - 1)
  print(string.rep("-", 50))
  if halted then
    colour("red")
    write("HALTED -- " .. tostring(note or "a turtle stopped"))
    colour("white")
  else
    if bad then colour("red") end
    write(text)
    colour("white")
  end
end

local function drawLobby()
  header("lobby")
  print("On each turtle run:  wall join")
  print("")
  for i, t in ipairs(waiting) do
    print((" %2d   id %-4s %s"):format(i, tostring(t.id), t.label or ""))
  end
  footer(#waiting == 0 and "no turtles yet"
         or ("%d enlisted -- press ENTER to assign and launch"):format(#waiting))
end

local function drawScan()
  header(phase == "scan" and "scanning" or "sharing the ring")

  for i, t in ipairs(waiting) do
    local what
    if i == 1 then
      if phase == "share" then what = "back at the pad"
      elseif scoutData then what = "waiting out on the ring"
      elseif nextInner then what = "walking the wall ring"
      else what = "on the pad ring" end
    else
      if readyCells[i] then what = ("ready, %d cells"):format(readyCells[i])
      elseif innerDone[i] then what = "pad ring done"
      elseif nextInner and i == nextInner then what = "tracing the pad ring"
      elseif not nextInner then what = "waiting for the pad"
      else what = "waiting" end
    end
    print((" %2d   id %-4s %s"):format(i, tostring(t.id), what))
  end

  local ready = 0
  for _ in pairs(readyCells) do ready = ready + 1 end
  footer(("%d of %d have the ring"):format(ready, #waiting))
end

local function drawWatch()
  header(("%d turtles    %d holes"):format(#waiting, #holes))
  print(" #  band      doing            done  skip miss")

  local indices = {}
  for i in pairs(seen) do indices[#indices + 1] = i end
  table.sort(indices)

  local _, h = term.getSize()
  local row = 4

  for _, i in ipairs(indices) do
    if row >= h - 2 then break end
    local t = seen[i]
    local band = (t.from and t.to) and (t.from .. "-" .. t.to) or "?"
    local doing

    if now() - (t.last or 0) > STALE then doing = "quiet"
    elseif t.state == "done"       then doing = "done"
    elseif t.state == "stopped"    then doing = "STOPPED"
    elseif t.state == "restocking" then doing = "restock c" .. tostring(t.course)
    else doing = ("c%s %s/%s"):format(tostring(t.course), tostring(t.cell),
                                      tostring(t.cells)) end

    print((" %-2s %s %s %s %s %s")
          :format(tostring(i), pad(band, 9), pad(doing, 16),
                  rpad(t.placed or 0, 5), rpad(t.skipped or 0, 5),
                  rpad(t.missed or 0, 4)))
    row = row + 1
  end

  local text, bad = coverage()
  footer(text, bad)
end

local function draw()
  if phase == "lobby" then drawLobby()
  elseif phase == "scan" or phase == "share" then drawScan()
  else drawWatch() end
end

--[[-- launching -----------------------------------------------------------]]

local function beginLaunch()
  if #waiting == 0 then return end

  term.clear()
  term.setCursorPos(1, 1)
  print(("%d turtles enlisted:"):format(#waiting))
  for i, t in ipairs(waiting) do
    print(("  %d   id %-4s %s"):format(i, tostring(t.id), t.label or ""))
  end
  print("")

  write(("Launch with these %d? Later arrivals miss out. (y/N) "):format(#waiting))
  if read():lower():sub(1, 1) ~= "y" then return end

  phase = "scan"

  -- Turtle 1 walks the wall ring. It has to trace the pad ring first, so the
  -- rest wait until it says it is clear of the pad before starting on it.
  tell(waiting[1].id, { kind = "role", role = "scout" })
  nextInner = nil
end

--[[-- loop ----------------------------------------------------------------]]

print("Listening on protocol '" .. PROTOCOL .. "' via the " .. side .. " modem.")
print("Holes are appended to " .. HOLES .. ". Ctrl+T to stop.")
sleep(1)

local redraw = os.startTimer(1)

while true do
  local event = { os.pullEvent() }
  local name = event[1]

  if name == "rednet_message" then
    if event[4] == PROTOCOL then handle(event[3]) end

  elseif name == "timer" then
    if event[2] == redraw then redraw = os.startTimer(1) end

  elseif name == "key" and phase == "lobby" then
    if event[2] == keys.enter then beginLaunch() end
  end

  draw()
end
