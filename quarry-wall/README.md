# wall — a survival `//walls` for a quarry pit

CC:Tweaked turtles that line the inside edge of a quarry hole with a wall, base
to ceiling, crafting every course out of cobbled deepslate as they go.

The wall follows a ring of marker blocks you lay round the pit, so cave mouths
in the pit face, pillars on the floor and bumpy bedrock stop mattering — and
the wall follows whatever shape you mark, which need not be a rectangle.
**Nothing is ever broken.** Anything already standing, including floating
builds and cables crossing the wall line, is detected and left alone.

The work splits across as many turtles as you like. One walks the ring; the
rest work out where it is from a second, small ring round the launch pad. No
GPS, no shared coordinates, no per-turtle configuration.

Built for **Minecraft 1.21.1 / NeoForge**.

---

## What you need

| | |
|---|---|
| **Crafty Turtles** | Turtle + crafting table, and a **wireless modem** in the other slot. **Never a pickaxe** — with no tool fitted the turtle is physically incapable of breaking a block, whatever the code does. |
| **A computer** | With a wireless modem, to run `monitor`. |
| **Three chests per turtle** | Supply, fuel, overflow — see below. |
| **Two marker rings** | The wall line, and a small one round the launch pad. |

---

## The station

Turtles stand around a stack of chests. Supply at turtle level, fuel directly
above it, and **the floor under each turtle is its overflow chest**.

```
        [fuel ][fuel ]        one block up
        [suppl][suppl]        turtle level
    . A B .
    H [][] C                  A..H = turtles, facing the stack
    G [][] D                  each standing on its own overflow chest
    . F E .
```

- **Supply** — cobbled deepslate, **and nothing else**. The turtle checks and
  stops if it finds anything it did not ask for. Feed it from AE2 or similar;
  see the sizing table for the rate.
- **Fuel** — coal or coal blocks. Barely used: about 9 coal blocks per turtle
  for a whole job. Hand-fill it once.
- **Overflow** — the chest the turtle stands on. **Required.** `turtle.craft()`
  matches the recipe against the *whole* inventory, so a turtle has to be
  completely empty to craft anything; everything it carries goes in here
  meanwhile. Reaching it costs no movement at all.

Turtles must be **orthogonally** adjacent to a supply chest, never diagonal,
and **facing it** when you start the program — whatever a turtle faces at
launch becomes its heading 0.

**Put a coal block in each turtle before you start.** The fuel chest is one
block up, reaching it costs a move, and a turtle with an empty tank cannot pay.

### The two rings

**The wall ring** is laid round the pit edge, one block wide, one level below
turtle height. One block of it is the **anchor** (a sea lantern by default).
This is the line the wall follows.

```
   ####################################   pit face
   #  o..............................o #  <- wall ring, one block wide
   #  .                              . #     one level below turtle height
   #  .          [station]           . #
   #  o..............................o #
   ####################################
```

**The launch pad ring** is a second small ring round the station, same idea,
**different blocks** — glass panes with an ochre froglight anchor, against
glass with a sea lantern for the wall ring. Different blocks matter: a turtle
walks outward looking for one and must not find the other.

This is what lets the turtles agree on coordinates without GPS. See *How it
works* below.

Both rings need one block of air above them so turtles can read them without
breaking anything.

### The gap under the wall

`config.wall.aboveRing` sets how far above the ring the first course sits. The
default of 3 leaves two open blocks, which gives you room to work under the
wall and keeps the ring readable for a re-scan.

That gap is a deliberate opening round the whole perimeter. `wall seal` closes
it afterwards, filling only the actual gaps and leaving intact rock alone.

---

## Installing

Everything is packed into a single `install.lua`, so one line does it:

```
wget run https://raw.githubusercontent.com/Sylvezar/turtle-projects/main/quarry-wall/install.lua
```

Anything after the URL is handed straight to the program, so one line both
installs and starts a turtle:

```
wget run <url> join
wget run <url> resume -y
wget run <url> build 8 4 122 -y
```

The installer prints a **build id** when it finishes:

```
14 files written, 1 kept.
build fe96e19f  (2026-09-15 20:01 UTC)
```

`raw.githubusercontent.com` caches for several minutes, so **check that id**
after an update. A commit-pinned URL
(`.../turtle-projects/<commit sha>/quarry-wall/install.lua`) is never cached and
always fresh.

`wall/wall check` reports the build a turtle is running without reinstalling.

### Your config is kept

`wall/config.lua` is never overwritten, so your pattern survives an update. The
cost is that a new *required* setting would not arrive either — so the config
carries a schema version and the installer says plainly when the one on disk is
behind:

```
Your wall/config.lua is older than this build and is missing
settings the program needs. It was kept so your edits survive.

  rm wall/config.lua   then install again
```

Regenerate `install.lua` after changing any source:

```
py -3 tools/make_installer.py
```

---

## Running it

```
wall/wall check                    config and turtle. Moves nothing.
wall/wall scan [--strict]          trace the ring and measure. Places nothing.
wall/wall join                     take a slice from the monitor.
wall/wall build [n] [i] [courses]  build a slice given directly.
wall/wall resume [-y]              carry on from an interrupted run.
wall/wall patrol [n] [i] [courses] go back over the wall and fill gaps.
wall/wall seal [courses]           fill the gap under the wall base.
wall/wall clear                    show what it holds and put it away.
```

### A normal launch

**On the computer:**

```
wall/monitor
```

**On each turtle:**

```
wget run <url> join
```

They check into a lobby in any order. Press **ENTER**, confirm the count, and
it runs itself:

```
wall monitor -- scanning
--------------------------------------------------
  1   id 0    walking the wall ring
  2   id 1    pad ring done
  3   id 2    tracing the pad ring
  4   id 3    waiting
--------------------------------------------------
2 of 8 have the ring -- W to give up and just watch
```

One turtle walks the wall ring and measures the height while it is out there.
The rest trace the launch pad ring, one at a time. The scout's answer is passed
round, everyone translates it into their own coordinates without leaving the
pad, and they all launch together.

Then it asks you to confirm the course count it measured:

```
All 8 turtles have the ring, 162 cells.

The scout measured 122 courses.

Courses to build [122]:
```

### Watching it

```
wall monitor -- 8 turtles    4 holes
--------------------------------------------------
 #  band      doing            done  skip miss
 1  1-15      done             2430     0    0
 2  16-30     c18 67/162       1580     2    0
 3  31-45     restock c31      1204     1    0
 4  46-61     quiet             890     0    0
--------------------------------------------------
coverage 1-122 complete
```

`coverage … complete` is the check that the bands tiled. Every turtle's holes
collect into one `wall_holes.txt` on the computer.

A turtle restarted by hand with `build` or `resume` never goes through the
lobby, but the monitor picks it up as soon as it reports.

### Finishing up

A course is built in one pass, so anything in the way at that moment — a mob
standing in the cell, another turtle, a cable — leaves a hole. Two passes clean
that up, run on each turtle once its band is done:

```
wall/wall patrol      go back over the wall and fill what is missing
wall/wall seal        close the gap under the wall base
```

`patrol` flies up the column just *inside* each wall cell and looks sideways,
carrying a stack of every block its band uses. With no arguments it reads its
own band from the saved run, so it needs no telling.

It skips corners. A corner has no interior cell to fly up beside, so there is
nowhere to look from — and you cannot see a corner from inside the pit anyway.

```
Checked 2430 cells. Filled 19 holes.
Skipped 4 corners -- no way to see them from inside.
```

### Without a monitor

`build` and `resume` need no network at all:

```
wall/wall build 8 4 122 -y     turtle 4 of 8, 122 courses
wall/wall resume -y            carry on from wherever it stopped
```

`resume` reads the saved state, so it knows its own slice — it prints which
turtle it is rather than needing to be told:

```
Resuming turtle 4 of 8, courses 46 to 61.
Stopped at course 52, cell 88.
```

---

## When something goes wrong

**A turtle has stopped.** Run `wall/wall resume -y`. It empties itself, picks up
the ring from its cache, and carries on at the exact cell it stopped at.

**`the overflow chest is full`.** Empty it. A turtle that died mid-craft leaves
a parked load behind, and 27 slots fills after about six of those.

**`slot N still holds X after clearing out`.** `wall/wall clear` lists what it
is carrying and puts it away.

**`the supply chest holds <something>`.** The supply chest must contain cobbled
deepslate only — `suck` takes whatever is in the first slot and cannot be asked
for a particular item.

**`the ring dead-ends at x,z`.** Something is standing on the marker ring,
usually another turtle from an earlier attempt. The trace refuses rather than
guessing, which is what stops a wall going up on a wrong line.

**Turtles colliding.** They retry, detour, and come back to blocked cells at the
end of each course. Getting home retries four times, three seconds apart.

**Mobs blocking placements.** A mob is not a block, so the cell reads empty and
simply refuses. Those cells are retried at the end of the course, by which time
it has wandered off. If it gets bad, light the pit or turn spawning off.

**The height comes out wrong.** Once any of the wall is standing, the climb runs
into that rather than the ceiling. It detects this — anything the turtles can
craft was not put there by the world — and falls back on
`config.height.suggest`. **Set that to your measured height**, or use
`height.stopAt = "given"` to skip the climb entirely.

---

## The pattern

At the top of `config.lua`:

```lua
config.pattern = {
  bottom = {},
  repeating = {
    { block = "chiseled_deepslate",  height = 1 },
    { block = "polished_deepslate",  height = 3 },
    { block = "chiseled_deepslate",  height = 1 },
    { block = "deepslate_tiles",     height = 2 },
    { block = "deepslate_bricks",    height = 2 },
    -- ... eight alternating pairs in all, 21 courses per cycle
  },
  top = {},
}
```

- **`bottom`** is anchored to the wall's base, listed bottom-up.
- **`repeating`** tiles the middle as many times as it takes.
- **`top`** is anchored to the rim, bottom-up — the last entry is the cap.

The middle stretches or shrinks to whatever depth the pit turns out to be. If
the wall is too short for `bottom` and `top` to both fit, the bottom band loses
courses first and the cap is the last thing to go.

### Blocks you can use

Anything reachable from cobbled deepslate:

| Block | Cobbled deepslate each |
|---|---|
| `cobbled_deepslate` | 1 |
| `polished_deepslate` | 1 |
| `deepslate_bricks` | 1 |
| `deepslate_tiles` | 1 |
| `chiseled_deepslate` | 1 |
| `*_slab` (all four) | 0.5 |
| `*_stairs` (all four) | 1.5 |
| `*_wall` (all four) | 1 |

Full blocks are what you want for an actual wall. Slabs, stairs and `_wall`
blocks are placed, but their orientation follows the direction the turtle placed
from.

`wall check` verifies every block in your pattern is craftable before a turtle
leaves the station.

---

## Sizing a job

For a 40 × 40 pit, 122 courses, across 8 turtles:

| | |
|---|---|
| Perimeter | 162 cells per course |
| Total | **19,764 blocks** (~309 stacks, 5.7 double chests) |
| Runtime | **~65 min** for the slowest turtle |
| Fuel | ~9 coal blocks each |
| Deepslate draw | ~2.5 items/sec per supply chest shared by 4 turtles |

Everything in the default pattern is 1:1 from cobbled deepslate, so blocks and
cobbled deepslate are the same number.

**Chunk loading is what will actually bite you.** An hour is far longer than you
will stand there, and a turtle stops dead when its chunk unloads:

```
/forceload add <x1> <z1> <x2> <z2>
```

**Put an acceleration card in the export buses.** A bare one is marginal at 2.5
items/sec sustained, and turtles queueing at the chest stretch the run out.

---

## How it works

**The wall line.** A turtle walks out until `inspectDown()` finds a marker
block, then follows the ring, trying straight ahead before either turn. The loop
is wound to a fixed direction (by the shoelace formula, which survives the
turtle's own rotation) and rotated to start at the anchor. The result is a cell
list that is **identical on every turtle and on every re-trace**, which is what
makes a resume land exactly where it stopped.

**Sharing it.** Because a trace is anchored and wound the same way, two turtles
walking the *same* ring come back with the same cells in the same order — cell 3
of mine is cell 3 of yours, the same physical block in two coordinate systems.
Two such cells pin down the rotation and offset between those systems exactly.
So everyone traces the little launch pad ring, one turtle walks the big one, and
its answer is translated into everyone else's numbers. The transform is verified
against *every* cell before it is used.

**Remembering it.** A traced or derived ring is saved to disk. It is in the
turtle's own frame, so a turtle back on its station reuses it after a short hop
to confirm the froglight is still where the list says — a few blocks, rather
than a lap of the perimeter.

**Splitting the work.** Courses divide into contiguous bands, one per turtle,
flooring both ends so they tile with no gap or overlap. Turtles stay tens of
courses apart.

**Building.** Bottom-up, one course at a time, flying one level *above* the
course and placing downwards. If the space above a cell is occupied it stands
beside the cell and places sideways instead — which is how a wall gets threaded
past an obstruction without breaking it.

**Crafting.** `turtle.craft()` matches against the **whole inventory**, so the
turtle must hold the recipe and nothing else. Everything goes into the overflow
chest first, and batches are *planned* so every stage of a chain divides
exactly, leaving no remainder to spoil the next craft. Blocks already sitting in
the overflow are counted before anything is crafted, so the pattern coming back
round to a type built earlier costs nothing.

**Nothing is ever dug.** There is no `turtle.dig()` call anywhere. Occupied cells
are skipped, counted, and written to `wall_holes.txt` with a course number and a
cell index counted from the anchor.

---

## Limits worth knowing

- **Both rings must be one block wide and closed loops.** The trace checks and
  refuses rather than guessing.
- **The supply chest must hold only cobbled deepslate.**
- **The station must be inside the wall ring**, not on it.
- **Every turtle needs the same course count.** The monitor handles this; if you
  use `build` by hand, give them all the same number.
- Corners blocked from above and from both sides cannot be filled and are
  reported as `UNREACHABLE`.

---

## Tests

The program runs against a simulated pit on a PC, with no Minecraft involved — a
mock world, a mock turtle, and a crafting mock that matches recipes by shape.

```
py -3 -m pip install lupa
py -3 test/drive.py
```

679 checks: recipe costs and crafting chains, batch planning, pattern
resolution, band tiling, the point-in-polygon test, ring tracing, **frame
transforms lining two turtles up**, the ring cache, height measurement in both
modes, a full eight-turtle build on a pit with a floating structure and
obstructions in the wall line, the hole log, rednet reporting, sealing, resume,
the installer round-trip, and the guards.

**The mock is deliberately pessimistic**, because three separate bugs got past a
friendlier earlier version:

- `turtle.craft()` matches the **whole** inventory, not the top-left 3×3.
- `turtle.transferTo()` reports **failure** when it moved only part of a stack.
- `turtle.drop()` reports **success** when it moved only part of a stack.

All three were assumptions the simulation happily agreed with, so the tests were
measuring self-consistency rather than correctness. It now behaves like the real
thing in each case. There is also a lint banning Lua 5.3+ syntax, because the
harness runs a much newer Lua than CC:Tweaked's 5.2 and `//` compiled cleanly
right up until it reached a turtle.
