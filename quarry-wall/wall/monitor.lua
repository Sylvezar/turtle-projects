--[[--------------------------------------------------------------------------
  monitor -- assign the turtles their slices, launch them, and watch.

  Runs on an ordinary computer with a wireless modem, anywhere in range. It
  does three things in sequence:

    lobby      turtles running `wall join` check in and wait
    launch     each is handed a slice and released, one at a time
    watch      one screen showing what every turtle is doing

  Assigning here rather than typing an index into each turtle removes the one
  place a typo does real damage -- two turtles given the same index means a
  doubled band and a gap elsewhere, which you would not discover until you
  looked at the finished wall.

  Releasing one at a time matters more than it looks: tracing the marker ring
  is a full lap of the perimeter, and a turtle blocked part way round reads the
  blockage as "no ring this way" and can trace a wrong line. So the next turtle
  is released only when the previous one reports it has started building. The
  timeout is a fallback for a turtle that has gone silent altogether, and is
  pushed back every time the one being released says anything at all.

  Turtles started with `wall build` instead of `wall join` never enter the
  lobby; they just appear on the board once they start reporting.

  Usage:  monitor [protocol]
----------------------------------------------------------------------------]]

local PROTOCOL = ... or "wall"
local HOLES    = "wall_holes.txt"
local STALE    = 30        -- seconds of silence before a turtle reads "quiet"
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

local phase     = "lobby"     -- lobby -> launch -> watch
local waiting   = {}          -- enlistment order: { id = , label = }
local enlisted  = {}          -- id -> true, to dedupe re-announcements
local seen      = {}          -- assigned index -> latest status
local holes     = {}
local holeSeen  = {}

local courses, stagger        -- chosen at launch time
local halted                  -- a turtle failed; stop letting more go
local releasing, releaseTimer -- how far through the launch we are
local totalCourses

local function now() return os.clock() end

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

local function handle(msg)
  if type(msg) ~= "table" then return end

  if msg.kind == "enlist" and msg.id then
    if not enlisted[msg.id] then
      enlisted[msg.id] = true
      waiting[#waiting + 1] = { id = msg.id, label = msg.label }
    end
    return
  end

  if msg.kind == "hole" then
    noteHole(msg)
    return
  end

  if not msg.turtle then return end
  if msg.courses then totalCourses = msg.courses end

  local t = seen[msg.turtle] or {}
  for k, v in pairs(msg) do t[k] = v end
  t.last = now()
  seen[msg.turtle] = t
end

--[[--------------------------------------------------------------------------
  Do the bands tile?

  Every course from 1 to the total should be claimed by exactly one turtle.
  With the monitor assigning them that should be automatic, but a turtle
  started by hand with `wall build` can still land on top of one.
----------------------------------------------------------------------------]]
local function coverage()
  local total = totalCourses or courses
  if not total then return "waiting for turtles", false end

  local claimed = {}
  for _, t in pairs(seen) do
    if t.from and t.to then
      for c = t.from, t.to do claimed[c] = (claimed[c] or 0) + 1 end
    end
  end

  local gap, dup
  for c = 1, total do
    local n = claimed[c] or 0
    if n == 0 and not gap then gap = c end
    if n > 1 and not dup then dup = c end
  end

  -- All eight trace the same physical ring, so a turtle that came back with a
  -- different cell count was disturbed part way round and its wall line is
  -- wrong. Worth shouting about.
  local sizes = {}
  for i, t in pairs(seen) do
    if t.cells then sizes[t.cells] = (sizes[t.cells] or 0) + 1 end
  end
  local kinds = 0
  for _ in pairs(sizes) do kinds = kinds + 1 end
  if kinds > 1 then
    return "RING MISMATCH -- turtles traced different sized rings", true
  end

  if dup then
    return ("OVERLAP at course %d -- two turtles share a slice"):format(dup), true
  end
  if gap then return ("unclaimed from course %d"):format(gap), false end
  return ("coverage 1-%d complete"):format(total), false
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

local function drawLobby()
  header("lobby")
  print("On each turtle run:  wall join")
  print("")

  for i, t in ipairs(waiting) do
    print((" %2d   id %-4s %s"):format(i, tostring(t.id), t.label or ""))
  end

  local _, h = term.getSize()
  term.setCursorPos(1, h - 1)
  print(string.rep("-", 50))
  if #waiting == 0 then
    write("no turtles yet")
  else
    write(("%d enlisted -- press ENTER to assign and launch"):format(#waiting))
  end
end

local function drawLaunch()
  header("launching")

  for i, t in ipairs(waiting) do
    local note
    if i < releasing then
      local st = seen[i]
      note = (st and st.state) and ("released, " .. st.state) or "released"
    elseif i == releasing then
      note = "releasing now"
    else
      note = "waiting"
    end
    print((" %2d   id %-4s %s"):format(i, tostring(t.id), note))
  end

  local _, h = term.getSize()
  term.setCursorPos(1, h - 1)
  print(string.rep("-", 50))

  if halted then
    colour("red")
    write("HALTED -- turtle " .. tostring(releasing) .. ": "
          .. tostring((seen[releasing] or {}).error or "stopped"))
    colour("white")
  else
    write(("%d of %d released"):format(math.min(releasing - 1, #waiting),
                                       #waiting))
  end
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

    if now() - (t.last or 0) > STALE then
      doing = "quiet"
    elseif t.state == "done" then
      doing = "done"
    elseif t.state == "stopped" then
      doing = "STOPPED"
    elseif t.state == "tracing" then
      doing = "tracing ring"
    elseif t.state == "traced" then
      doing = "traced " .. tostring(t.cells)
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
  print(string.rep("-", 50))

  -- An error outranks the coverage line: it is the thing that needs acting on.
  local failed
  for i, t in pairs(seen) do
    if t.state == "stopped" then failed = failed or { i = i, t = t } end
  end

  if failed then
    colour("red")
    write(("turtle %d STOPPED: %s"):format(failed.i,
          tostring(failed.t.error or "no reason given")))
    colour("white")
    return
  end

  local text, bad = coverage()
  if bad then colour("red") end
  write(text)
  colour("white")
end

local function draw()
  if phase == "lobby"  then drawLobby()  return end
  if phase == "launch" then drawLaunch() return end
  drawWatch()
end

--[[-- launching -----------------------------------------------------------]]

local function releaseNext()
  if releasing > #waiting then
    phase = "watch"
    return
  end

  local t = waiting[releasing]
  rednet.broadcast({ kind = "assign", to = t.id, index = releasing,
                     turtles = #waiting, courses = courses }, PROTOCOL)

  releaseTimer = os.startTimer(stagger)
end

--- Move on once the turtle we just released says it is building -- tracing the
--- ring is the part that must not overlap, and that is over by then.
local function maybeAdvance()
  if phase ~= "launch" then return end
  local st = seen[releasing]
  if not st then return end

  -- A turtle that has stopped has failed. Releasing the next one on top of
  -- that just produces eight failures instead of one, and buries the error.
  if st.state == "stopped" then
    halted = true
    return
  end

  if st.state == "building" or st.state == "restocking" then
    releasing = releasing + 1
    releaseNext()
  end
end

local function beginLaunch()
  if #waiting == 0 then return end

  term.clear()
  term.setCursorPos(1, 1)
  print(("%d turtles enlisted:"):format(#waiting))
  for i, t in ipairs(waiting) do
    print(("  %d   id %-4s %s"):format(i, tostring(t.id), t.label or ""))
  end
  print("")

  -- The count is locked in here: the wall is split between exactly these
  -- turtles, and anything that enlists later waits forever for an assignment
  -- that never comes. Worth one keypress to be sure.
  write(("Launch with these %d? Later arrivals miss out. (y/N) "):format(#waiting))
  if read():lower():sub(1, 1) ~= "y" then
    return          -- stays in the lobby, still collecting
  end

  print("")
  print("Run `wall scan` on one turtle first if you have not; it prints the")
  print("course count.")
  print("")

  write("How many courses tall: ")
  courses = tonumber(read())
  while not courses or courses < 1 or courses ~= math.floor(courses) do
    write("  enter a whole number of at least 1: ")
    courses = tonumber(read())
  end

  -- A fallback for a turtle that has gone silent, not the normal path: the
  -- next turtle is released as soon as this one reports it is building. Set it
  -- well above how long a lap of the ring takes.
  write("Give up waiting after [300]s: ")
  stagger = tonumber(read()) or 300
  if stagger < 30 then stagger = 30 end

  phase = "launch"
  releasing = 1
  releaseNext()
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
    if event[4] == PROTOCOL then
      local msg = event[3]
      handle(msg)

      -- Any word from the turtle being released means it is alive and working,
      -- so push the give-up timer back. Only genuine silence should advance
      -- the queue on a timeout.
      if phase == "launch" and type(msg) == "table"
      and msg.turtle == releasing then
        releaseTimer = os.startTimer(stagger)
      end

      maybeAdvance()
    end

  elseif name == "timer" then
    if event[2] == redraw then
      redraw = os.startTimer(1)
    elseif event[2] == releaseTimer and phase == "launch" then
      releasing = releasing + 1
      releaseNext()
    end

  elseif name == "key" and phase == "lobby" then
    if event[2] == keys.enter then beginLaunch() end
  end

  draw()
end
