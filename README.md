# turtle-projects

CC:Tweaked programs for the syl-and-joeiis server (Minecraft 1.21.1 / NeoForge).

## [quarry-wall](quarry-wall/) — a survival `//walls` for a quarry pit

Turtles that line the inside edge of a quarry hole with a wall, floor to rim,
crafting each course out of cobbled deepslate as they go. The wall follows a
ring of marker blocks you lay round the pit, so it copes with cave mouths,
pillars and bumpy bedrock — and follows whatever shape you mark. Nothing is
ever broken; anything already standing is detected and left alone. The work
splits across any number of turtles with no network and no shared config.

Install on a turtle:

```
wget run https://raw.githubusercontent.com/Sylvezar/turtle-projects/main/quarry-wall/install.lua
```
