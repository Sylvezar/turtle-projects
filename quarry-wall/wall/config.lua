--[[--------------------------------------------------------------------------
  config.lua -- everything you are meant to edit lives in this file.

  The same file goes on every turtle. How many turtles there are, which one
  this is, and how tall the wall should be are all asked at launch, so nothing
  in here needs changing between turtles.

  Block names are given WITHOUT the "minecraft:" prefix; it is added for you.
----------------------------------------------------------------------------]]

local config = {}

--[[--------------------------------------------------------------------------
  THE PATTERN

  The wall is built from its base upwards. Courses are assigned like so:

    bottom     anchored to the base, listed bottom-up
    repeating  tiles the middle, as many times as it takes
    top        anchored to the rim, listed bottom-up (last entry = the cap)

  If the wall is too short to fit `bottom` + `top`, `bottom` is trimmed from
  its top down, then `top` from its bottom up. The cap always survives.

  `height` is a course count, i.e. how many blocks tall that band is.
----------------------------------------------------------------------------]]
config.pattern = {
  bottom = {},

  -- A 21 course cycle: a five course chiseled and polished header, then eight
  -- alternating pairs of tiles and bricks, then round again.
  repeating = {
    { block = "chiseled_deepslate",  height = 1 },
    { block = "polished_deepslate",  height = 3 },
    { block = "chiseled_deepslate",  height = 1 },

    { block = "deepslate_tiles",     height = 2 },
    { block = "deepslate_bricks",    height = 2 },
    { block = "deepslate_tiles",     height = 2 },
    { block = "deepslate_bricks",    height = 2 },
    { block = "deepslate_tiles",     height = 2 },
    { block = "deepslate_bricks",    height = 2 },
    { block = "deepslate_tiles",     height = 2 },
    { block = "deepslate_bricks",    height = 2 },
  },

  top = {},
}

--[[--------------------------------------------------------------------------
  THE MARKER RING

  The wall follows a ring of marker blocks you lay round the pit, one block
  wide, one level below where the turtles stand. The turtles trace it rather
  than measuring the hole, so pillars, cave mouths in the pit face and bumpy
  bedrock stop mattering -- and the wall follows whatever shape you mark,
  which need not be a rectangle.

  One block of the ring is swapped for `anchor`. That is where every turtle
  starts counting, so they all produce the same cell list and a run can be
  resumed exactly where it stopped.

  The ring needs at least one block of air above it so the turtles can read it
  without breaking anything.

  Pick an `anchor` you have not built anything else out of. Glowstone would be
  a poor choice here because the station platform is made of it -- a sea
  lantern appears nowhere else, so there is nothing for the trace to confuse
  it with.
----------------------------------------------------------------------------]]
config.ring = {
  block  = "glass",
  anchor = "sea_lantern",

  -- How far to search outwards from the station before giving up.
  searchDistance = 128,
}

--[[--------------------------------------------------------------------------
  THE WALL

  aboveRing   how far above the marker ring the first course sits. 1 puts the
              wall straight onto the ring and buries it; 3 leaves a two block
              gap you can work in and keeps the ring readable for a re-scan.

  NOTE: that gap is a deliberate opening all the way round the perimeter. The
  pit face bounds it, so it only leaks if the face has cave mouths at those
  levels. `wall seal` fills it in afterwards.
----------------------------------------------------------------------------]]
config.wall = {
  aboveRing = 3,
}

--[[--------------------------------------------------------------------------
  THE STATION

  Each entry says where the turtle stands to reach a container and which way
  it looks. `offset` is relative to where the turtle started, so {0,1,0} means
  "go up one block first" -- which is how it reaches a fuel chest stacked on
  top of the supply chest.

  side     "front", "up" or "down"
  heading  only used by "front". 0 = the way the turtle faced at launch,
           1 = its right, 2 = behind it, 3 = its left.

  Set `overflow` to nil to keep leftovers on board. With the courses split
  between turtles each one only sees two or three block types, so leftovers
  rarely need anywhere to go.
----------------------------------------------------------------------------]]
config.station = {
  supply   = { offset = {0, 0, 0}, side = "front", heading = 0 },
  fuel     = { offset = {0, 1, 0}, side = "front", heading = 0 },
  overflow = nil,
}

--[[--------------------------------------------------------------------------
  HOW TALL

  Asked at launch. `suggest` is only used to prefill the prompt when the
  turtle cannot work it out by looking.

  Every turtle must be given the SAME number, or their slices will not line
  up and you will get a doubled course and a gap. Run `wall scan` once, note
  what it reports, and type that number into all of them.

  stopAt    what stops the climb.
              "roof"  something overhead. For a pit dug underground. Caves in
                      the pit face cannot fool it, so prefer this when it
                      applies.
              "rim"   the pit face running out beside you. For a pit open to
                      the sky, where nothing overhead can stop the climb. A
                      cave mouth in the face looks just like the top, which is
                      what `confirm` is trying to cover for.
  confirm   "rim" only: levels of open air needed before calling it.
  max       hard ceiling on the climb (safety stop).
----------------------------------------------------------------------------]]
config.height = {
  suggest = 118,
  stopAt  = "roof",
  confirm = 2,
  max     = 384,
}

--[[--------------------------------------------------------------------------
  BUILD BEHAVIOUR

  maxCarryCrafted  blocks per trip when the course needs crafting. Capped by
                   the 7 turtle slots that are not part of the crafting grid.
  maxCarryRaw      blocks per trip for plain cobbled deepslate (no grid
                   needed, so all 16 slots are usable).
  carryAcross      let one load cover several courses when they are the same
                   block. Saves a lot of climbing on a deep pit.
  skipOccupied     leave any block already standing in a wall cell alone.
                   Keep this true; it is what protects your existing builds.
  saveEvery        write the resume file every N placed blocks.
----------------------------------------------------------------------------]]
config.build = {
  maxCarryCrafted = 384,
  maxCarryRaw     = 1024,
  carryAcross     = true,
  skipOccupied    = true,
  saveEvery       = 8,
}

--[[--------------------------------------------------------------------------
  PROGRESS REPORTING

  Optional. With a wireless modem fitted, turtles broadcast what they are doing
  so a computer running `monitor` can show every turtle on one screen and
  collect all their hole logs in one place.

  Entirely one-way: nothing waits for a reply, and a turtle with no modem (or
  with this turned off) behaves exactly the same. The wall does not need a
  network -- the marker ring already gives every turtle the same answer.

  every   send a progress update at most once per this many blocks placed.
          State changes are always sent immediately regardless.
----------------------------------------------------------------------------]]
config.report = {
  enabled  = true,
  protocol = "wall",
  every    = 16,
}

--[[--------------------------------------------------------------------------
  FUEL

  reserve     do not leave the station below this (1 fuel = 1 move). It has to
              cover a whole round trip: out to the ring, all the way around,
              and back.
  refuelTo    top up to at least this much.
  pullAtOnce  items to take from the fuel chest per grab. Keep it modest --
              a whole stack of coal blocks is 51,200 fuel against a cap of
              about 20,000, and the excess is gone.
  Ignored entirely on servers with turtle fuel disabled.
----------------------------------------------------------------------------]]
config.fuel = {
  reserve    = 3000,
  refuelTo   = 8000,
  pullAtOnce = 16,
}

return config
