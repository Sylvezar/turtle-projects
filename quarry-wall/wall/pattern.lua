--[[--------------------------------------------------------------------------
  pattern.lua -- deciding which block each course is made of.
----------------------------------------------------------------------------]]

local pattern = {}

--- Turn { {block=, height=}, ... } into a flat bottom-up list of block names.
local function expand(courses)
  local out = {}
  for _, c in ipairs(courses or {}) do
    local name = c.block
    if not name:find(":") then name = "minecraft:" .. name end
    for _ = 1, (c.height or 1) do out[#out + 1] = name end
  end
  return out
end

pattern.expand = expand

--[[--------------------------------------------------------------------------
  layers -- resolve the whole wall, bottom-up, for a pit `height` courses tall.

  When the pit is too shallow for `bottom` + `top` to both fit, `bottom` loses
  its upper courses first and `top` its lower ones, so the floor band and the
  cap -- the two you actually see -- are the last things to go.
----------------------------------------------------------------------------]]
function pattern.layers(cfg, height)
  local bottom = expand(cfg.bottom)
  local top    = expand(cfg.top)
  local rep    = expand(cfg.repeating)

  while #bottom + #top > height and #bottom > 0 do table.remove(bottom) end
  while #bottom + #top > height and #top    > 0 do table.remove(top, 1) end

  local out = {}
  for _, b in ipairs(bottom) do out[#out + 1] = b end

  local middle = height - #bottom - #top
  if middle > 0 then
    if #rep == 0 then
      return nil, ("pattern.repeating is empty, but %d middle courses need filling")
                  :format(middle)
    end
    for i = 1, middle do out[#out + 1] = rep[((i - 1) % #rep) + 1] end
  end

  for _, t in ipairs(top) do out[#out + 1] = t end
  return out
end

--- Collapse a layer list into readable "courses 1-6: cobbled deepslate" bands.
function pattern.bands(layers)
  local out = {}
  local i = 1
  while i <= #layers do
    local j = i
    while j < #layers and layers[j + 1] == layers[i] do j = j + 1 end
    out[#out + 1] = { from = i, to = j, block = layers[i], count = j - i + 1 }
    i = j + 1
  end
  return out
end

--- Distinct block names used, with a total count of each.
function pattern.tally(layers, perLayer)
  local t, order = {}, {}
  for _, name in ipairs(layers) do
    if not t[name] then t[name] = 0 ; order[#order + 1] = name end
    t[name] = t[name] + perLayer
  end
  return t, order
end

return pattern
