# wall — a survival `//walls` for a quarry pit

CC:Tweaked turtles that line the inside edge of a quarry hole with a wall,
floor to rim, crafting each course out of cobbled deepslate as they go.

The wall follows a ring of marker blocks you lay round the pit, so it copes
with cave mouths in the pit face, pillars on the floor and bumpy bedrock — and
it follows whatever shape you mark, which need not be a rectangle. Nothing is
ever broken: anything already standing, including floating builds left in the
middle, is detected and left alone.

The work splits across as many turtles as you like. They need no network, no
GPS and no shared configuration — they all read the same marker ring, so they
all reach the same answer from wherever they happen to be standing.

Built for **Minecraft 1.21.1 / NeoForge**.

---

## What you need

| | |
|---|---|
| **Crafty Turtles** | Turtle + crafting table upgrade. Put a **modem** in the other slot if you want the monitor, or leave it empty — either way, **never a pickaxe**. With no tool fitted the turtle is physically incapable of breaking a block, whatever the code does. |
| **A supply chest** | Cobbled deepslate, and nothing else. The turtle checks and stops if it finds anything it did not ask for. |
| **A fuel chest** | Coal or coal blocks. See the numbers below — it is far less than you would think. |
| **A marker ring** | One block wide, laid round the pit edge one level below where the turtles stand, with one block swapped for a distinct anchor. |

---

## The station

Turtles stand around a stack of chests: supply at turtle level, fuel directly
on top. Each turtle reaches its fuel by stepping up one block, which keeps its
vertical exit clear.

```
        [fuel ][fuel ]        <- one block up
        [suppl][suppl]        <- turtle level
    . A B .
    H [][] C                  A..H = turtles, facing the stack
    G [][] D                  a 2x2 footprint has exactly 8
    . F E .                   orthogonally adjacent cells
```

A 2×2 chest footprint takes 8 turtles; a longer spine takes more. Turtles must
be **orthogonally** adjacent to a chest block, never diagonal, and facing it
when you start the program — whatever a turtle faces at launch becomes its
heading 0, and the station config assumes that is inward.

Put the whole station **inside the ring**, clear of the perimeter. It refuses
to start if it is standing on the ring.

### The marker ring

```
   ####################################   pit face
   #  o..............................o #  <- ring, one block wide
   #  .                              . #     one level below turtle height
   #  .          [station]           . #
   #  o..............................o #
   ####################################
```

One ring block is the **anchor** (`sea_lantern` by default). Every turtle
starts counting there and walks the loop the same way round, so they all
produce an identical cell list — which is what lets a resume land exactly where
it stopped. Pick an anchor you have not built anything else out of; glowstone
is a poor choice if your station floor is made of it.

The ring needs at least one block of air above it so turtles can read it
without breaking anything.

### The gap under the wall

`config.wall.aboveRing` sets how far above the ring the first course sits. The
default of 3 leaves two open blocks, which:

- gives you room to work under the wall, and
- keeps the ring readable, so a turtle can re-derive everything mid-run.

That gap is a deliberate opening round the whole perimeter. The pit face bounds
it, so it only leaks if the face has cave mouths at those levels. `wall seal`
closes it afterwards, filling only the actual gaps and leaving intact rock
alone.

---

## Installing

Everything is packed into a single `install.lua` so you fetch one file instead
of eleven. Regenerate it whenever you change the source:

```
py -3 tools/make_installer.py
```

Then put it somewhere the server can reach over HTTP and, on each turtle:

```
wget run https://raw.githubusercontent.com/Sylvezar/turtle-projects/main/quarry-wall/install.lua
```

That downloads and runs it in one step; it writes `wall/` and prints what it
did. Re-running is safe — it refreshes the program but **leaves an edited
`wall/config.lua` alone**, so your pattern survives an update.

Then check it landed:

```
wall/wall check
```

`monitor.lua` ships in the same folder, so a computer installed the same way
runs it as `wall/monitor`.

### Where to host it

CC:Tweaked's default HTTP rules **deny `$private`**, which covers RFC1918,
loopback *and* the `100.64.0.0/10` range Tailscale uses. So:

| Host | Works? |
|---|---|
| `raw.githubusercontent.com` (public repo or gist) | yes |
| `pastebin.com` via `pastebin get <code> install` | yes |
| Anything on a `*.ts.net` tailnet address | **no** — `Domain not permitted` |
| Anything on 192.168/10.x/127.x | **no** |

A self-hosted Git server on the tailnet needs one of:

- a publicly resolvable hostname, or
- an allow rule **above** the deny in `config/computercraft-server.toml`:

```toml
[[http.rules]]
	host = "gitea.example.ts.net"
	action = "allow"

[[http.rules]]
	host = "$private"
	action = "deny"
```

Rules are matched in order, first match wins, so the allow has to come first.
Needs a server restart to take effect.

## Running it

```
wall/wall check                    check config and turtle. Moves nothing.
wall/wall scan                     trace the ring and measure. Places nothing.
wall/wall build [n] [i] [courses]  build this turtle's share.
wall/wall resume                   carry on from an interrupted run.
wall/wall seal [courses]           fill the gap under the wall base.
```

Run `wall scan` on **one** turtle first. It traces the ring with the strict
check (verifying it is one block wide the whole way round), measures the
height, and prints the course count.

Then on each turtle:

```
> wall/wall build

  Tracing the marker ring... 156 cells, anchored at 12,-8

  How many turtles: 8
  Which one is this: 3
  How many courses tall [118]: 118

  Turtle 3 of 8 -- courses 30 to 44 of 118
     30-44   cobbled_deepslate        2340
     TOTAL                            2340  (2340 cobbled, 37 stacks)

  Start? (y/N)
```

Or pass them as arguments: `wall/wall build 8 3 118 -y`.

**Give every turtle the same course count.** It is the one number that must
match — if they disagree, their bands misalign and you get a doubled course and
a gap. The printed course range is your check: run through the turtles in order
and the ranges should tile 1…118 with no repeats and no gaps.

**Stagger the starts.** Several turtles tracing the ring at once will collide
near the station. Start them a minute apart.

### Watching it from one place (optional)

Fit each turtle with a **wireless or ender modem** in its second upgrade slot
and put one on an ordinary computer running `monitor`:

```
wall monitor    8 turtles    4 holes
--------------------------------------------------
 #  band      doing              done  skip miss
 1  1-14      done               2184     0    0
 2  15-29     c18 67/156         1580     2    0
 3  30-44     restock c31        1204     1    0
 4  45-59     quiet               890     0    0
--------------------------------------------------
coverage 1-118 complete
```

Turtles broadcast one-way; nothing waits for a reply. Starting or stopping the
monitor has no effect on a run, and a turtle with no modem behaves exactly as
before — **the wall does not need a network**, because the marker ring already
gives every turtle the same answer.

Two things it earns its keep for:

- **Every turtle's holes land in one `wall_holes.txt`** on the computer,
  stamped with which turtle found each one.
- **The coverage line checks the bands tile.** Eight indices typed by hand is
  the one place a typo does real damage — two turtles on index 3 means a
  doubled band and a gap elsewhere, which you would otherwise not find until
  you looked at the finished wall. It shows up in the first few seconds
  instead.

The crafting table takes one upgrade slot and the modem the other, so there is
still no room for a pickaxe — fitting a modem keeps the "cannot break anything"
guarantee intact.

**Range:** plain wireless modems reach ~64 blocks, and your turtles climb 118,
so they will drop out up high and reappear when they come home to restock
(showing as `quiet` in between). Ender modems have unlimited range if you want
continuous status.

`monitor.lua` goes on the computer, not the turtles. It needs no other files.

### Cables and anything else in the wall line

Nothing is ever broken. A cell that already contains something — a cable, a
machine, a block the quarry left — is detected and skipped, and with no
pickaxe fitted the turtle could not break it in any case.

That leaves **holes in the wall**, and each one is written to
`wall_holes.txt` as it happens:

```
wall holes -- turtle 3 of 8, courses 30 to 44
ring: 156 cells; cell 1 is the sea_lantern anchor, counting the way
the turtles walk it. Height is blocks above the marker ring.

course 34   ring+36   cell 92/156   occupied
course 35   ring+37   cell 92/156   occupied
```

Both coordinates are turtle-independent — every turtle traces the same
canonical loop, so `cell 92` is the same physical block whoever reported it.
To find one, stand at the sea lantern and count 91 cells round the ring, then
36 blocks up from the glass.

Two outcomes are distinguished, and the difference matters:

- **`occupied`** — something was already there. Expected around cables.
- **`UNREACHABLE`** — the turtle could not get to the cell from any side. Rare,
  and worth looking at: it means the cell is boxed in.

**Re-running patches the gaps.** Because occupied cells are skipped, running
`wall build` again with the same three numbers places only what is missing. So
you can build now, reroute cables afterwards, and re-run to close the holes —
no special mode needed.

One thing worth doing first: if a cable runs *vertically* through the wall
line, that is not a few scattered holes but a slot dozens of courses tall.
Cheaper to move that one before starting. Horizontal crossings cost a block or
two each and are not worth the effort.

### If a run is interrupted

Chunk unloads, server restarts and running out of fuel all leave a
`wall_state.txt`. Put the turtle back **at its station, facing the way it
started**, and run `wall/wall resume`. It re-traces the ring, checks it still
has the same number of cells, and picks up exactly where it stopped.

---

## The pattern

At the top of `config.lua`:

```lua
config.pattern = {
  bottom = {
    { block = "deepslate_tiles",     height = 4 },
  },
  repeating = {
    { block = "cobbled_deepslate",   height = 6 },
    { block = "polished_deepslate",  height = 1 },
  },
  top = {
    { block = "deepslate_bricks",    height = 2 },
    { block = "chiseled_deepslate",  height = 1 },
  },
}
```

- **`bottom`** is anchored to the wall's base, listed bottom-up.
- **`repeating`** tiles the middle as many times as it takes.
- **`top`** is anchored to the rim, bottom-up — the last entry is the cap.

The middle stretches or shrinks to whatever depth the pit turns out to be, so
you never count courses. If the wall is too short for `bottom` and `top` to
both fit, the bottom band loses courses first and the cap is the last thing to
go.

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
blocks will be placed, but their orientation follows the direction the turtle
placed from, and `_wall` blocks are fence-shaped rather than solid.

`wall check` verifies every block in your pattern is craftable before a turtle
leaves the station.

---

## Sizing a job

For a 40 × 40 pit, 120 courses tall, split across 8 turtles:

| | |
|---|---|
| Perimeter | 156 cells per course |
| Total blocks | 18,720 (~293 stacks, 5.4 double chests) |
| Runtime | ~55 min (about 6 h on one turtle) |
| Fuel | ~49 coal blocks, or ~494 coal, **across all 8** |
| Deepslate rate | ~0.65 items/sec per turtle |

**Fuel is not the constraint.** A whole band costs about 6,600 fuel, which is
under the turtle's ~20,000 cap — so each turtle could in principle carry its
entire job's fuel from the start. Treat the fuel chest as insurance.

**The deepslate supply is.** Each double chest feeding 4 turtles needs about
2.6 items/sec sustained. An ME export bus wants an acceleration card at that
rate; the 3,456-item buffer absorbs bursts but not a slow average.

**Chunk loading is what will actually bite you.** An hour is far longer than
you will stand there, and a turtle stops dead when its chunk unloads. The pit
spans about 3×3 chunks:

```
/forceload add <x1> <z1> <x2> <z2>
```

---

## How it works

**Finding the wall line.** A turtle walks out from the station until
`inspectDown()` finds a ring block, then follows the ring, trying straight
ahead before either turn — so a straight run costs one move per cell and only
corners cost extra. The loop is then wound to a fixed direction (by the
shoelace formula, which survives the turtle's own rotation) and rotated to
start at the anchor. One 156-move lap and it has the exact wall path in its own
coordinate frame.

**Splitting the work.** Courses are divided into contiguous bands, one per
turtle, flooring both ends so they tile with no gap or overlap. Turtles stay
tens of courses apart and essentially never meet.

**Building.** Bottom-up, one course at a time. The turtle flies one level
*above* the course and places downwards, riding over the wall it has built. If
the space above a cell is occupied it stands beside the cell and places
sideways instead — which is how a wall gets threaded past an obstruction
without breaking it.

**Crafting.** `turtle.craft()` reads the top-left 3×3, so the grid must hold
the recipe and nothing else. That leaves seven slots for materials, which is
why a crafted course carries 384 blocks per trip and plain cobbled deepslate
carries 1024. Chains craft a stage at a time: cobbled → polished → bricks →
tiles.

---

## Limits worth knowing

- **The ring must be one block wide and a closed loop.** `wall scan` checks
  this and reports the coordinates of any ambiguity rather than guessing.
- **Every turtle needs the same course count**, and a different index.
- **The supply chest must hold only cobbled deepslate.**
- **The station must be inside the ring**, not on it.
- Fuel and the supply chest are each waited on for up to 10 minutes before a
  turtle gives up and saves its state.

---

## Tests

The program runs against a simulated pit on a PC, with no Minecraft involved —
a mock world, a mock turtle, and a crafting mock that matches recipes by shape
independently of how the program stages them.

```
py -3 -m pip install lupa
py -3 test/drive.py
```

530 checks, covering recipe costs and crafting chains, pattern resolution, band
tiling across many turtle counts, the point-in-polygon test, ring tracing,
**four turtles at different positions and facings producing byte-identical cell
lists**, height measurement, a full eight-turtle build on a pit containing a
floating structure and pre-existing blocks in the wall line, the hole log,
rednet reporting (including that a turtle with no modem broadcasts nothing),
sealing the gap, resuming mid-course, and the guards.
