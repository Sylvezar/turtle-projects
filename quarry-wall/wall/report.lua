--[[--------------------------------------------------------------------------
  report.lua -- optional progress reporting over rednet.

  Entirely optional and entirely one-way. Turtles broadcast what they are
  doing; nothing waits for a reply and nothing depends on anyone listening. A
  turtle with no modem fitted, or with reporting turned off, behaves exactly
  as it did before -- every call here becomes a no-op.

  That matters: the wall does not need a network to work. The ring gives every
  turtle the same answer without one. This is a window onto the job, not a
  part of it.

  A turtle has two upgrade slots. The crafting table takes one and a modem
  takes the other, which leaves no room for a pickaxe -- so fitting a modem
  keeps the "cannot break anything" guarantee intact.
----------------------------------------------------------------------------]]

local report = {}

local SIDES = { "left", "right", "top", "bottom", "front", "back" }

local open     = false
local protocol = "wall"
local every    = 16
local counter  = 0
local me       = {}

--- Find a modem on any side and open rednet on it. Returns false quietly when
--- there is no modem, which is the normal case for a turtle without one.
function report.open(cfg)
  local r = (cfg and cfg.report) or {}
  if r.enabled == false then return false end

  protocol = r.protocol or "wall"
  every    = r.every or 16

  if not rednet or not peripheral then return false end

  for _, side in ipairs(SIDES) do
    local ok, kind = pcall(peripheral.getType, side)
    if ok and kind == "modem" then
      pcall(rednet.open, side)
      open = true
      return true
    end
  end

  return false
end

function report.isOpen() return open end

function report.close()
  open = false
  counter = 0
  me = {}
end

--- Who this turtle is, stamped onto every message so the monitor can tell
--- them apart and check their bands tile properly.
function report.identify(info)
  me = info or {}
end

local function send(msg)
  if not open then return end

  msg.turtle  = msg.turtle  or me.turtle
  msg.turtles = msg.turtles or me.turtles
  msg.from    = msg.from    or me.from
  msg.to      = msg.to      or me.to
  msg.courses = msg.courses or me.courses

  if os and os.getComputerID then msg.id = os.getComputerID() end

  pcall(rednet.broadcast, msg, protocol)
end

--- Send now, whatever the rate limit says. For state changes worth seeing
--- immediately: a course starting, a restock, finishing, failing.
function report.now(msg)
  msg.kind = msg.kind or "status"
  counter = 0
  send(msg)
end

--- Send at most every `every` calls, so placing eighteen thousand blocks does
--- not turn into eighteen thousand broadcasts.
function report.tick(msg)
  if not open then return end
  counter = counter + 1
  if counter < every then return end
  counter = 0
  msg.kind = msg.kind or "status"
  send(msg)
end

--- A gap in the wall, sent as it happens so the monitor can collect every
--- turtle's holes into one list.
function report.hole(msg)
  msg.kind = "hole"
  send(msg)
end

--[[--------------------------------------------------------------------------
  Enlisting

  The one place this stops being one-way. A turtle running `wall join` says it
  is here and waits to be told which slice it owns, so the eight indices are
  assigned in one place instead of typed in eight times -- and the monitor can
  release them one at a time rather than having eight turtles trace the ring
  simultaneously.

  Everything else still works without it. `wall build` takes the numbers
  directly and needs no modem at all.
----------------------------------------------------------------------------]]

function report.id()
  if os and os.getComputerID then return os.getComputerID() end
  return 0
end

function report.enlist()
  send({ kind = "enlist", id = report.id(),
         label = os.getComputerLabel and os.getComputerLabel() or nil })
end

--[[--------------------------------------------------------------------------
  Wait until the monitor hands us a slot.

  Re-announces every few seconds, so a turtle started before the monitor -- or
  one whose first shout was missed -- still gets picked up. `onWait` is called
  each time round so the caller can show something.

  Returns the assignment table, or nil if the turtle was told to stand down.
----------------------------------------------------------------------------]]
function report.awaitAssignment(onWait)
  if not open then return nil, "no modem fitted" end

  local me = report.id()
  report.enlist()

  local timer = os.startTimer(3)

  while true do
    local event = { os.pullEvent() }

    if event[1] == "timer" and event[2] == timer then
      report.enlist()
      if onWait then onWait() end
      timer = os.startTimer(3)

    elseif event[1] == "rednet_message" then
      local msg = event[3]
      if type(msg) == "table" and msg.to == me then
        if msg.kind == "assign" then return msg end
        if msg.kind == "standdown" then return nil, "told to stand down" end
      end
    end
  end
end

return report
