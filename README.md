# Coast Runner

An OutRun-style pseudo-3D arcade racer for the Playdate, in Lua. Original art,
code, and synth audio — no Sega assets. The road uses the classic segment-
projection technique (à la Lou's pseudo-3d road / jakesgordon's model), adapted
to the 400×240 1-bit display.

<img width="400" height="240" alt="meowta" src="https://github.com/user-attachments/assets/fda1f8c5-e87f-4fd2-8fc9-57fcfa574102" />

## Controls
- **Crank** — steer (spin to turn; faster spin = sharper turn, scaled by speed)
- **A** — gas
- **B** — brake
- **D-pad Up** — shift to HIGH gear
- **D-pad Down** — shift to LOW gear
- **D-pad Left/Right** — backup steering (for when the crank is docked)
- **B + Up** — bail back to the title screen
- D-pad on title: press **A** to start

Gearing has real depth: LOW accelerates hard but is capped at ~half top speed,
HIGH reaches max speed but bogs at low RPM. Launch in LOW, shift to HIGH on the
straights — just like the arcade.

## Build
Requires the [Playdate SDK](https://play.date/dev/) (`pdc` on your PATH).

```bash
pdc Source CoastRunner.pdx
# then open in the simulator:
open CoastRunner.pdx          # macOS
# or: Playdate Simulator > File > Open
```

To sideload to hardware, build the `.pdx`, zip it, and upload via the Playdate
account web sideload page, or use the simulator's "Upload to Device".

## Project layout
```
Source/
  main.lua      game states, physics, input, HUD, parallax bg, player car
  road.lua      track build + 3D projection + segment/sprite rendering
  audio.lua     synth engine (RPM-driven) + original title arpeggio
  pdxinfo       game metadata
  images/
    player-table-72-48.png   car imagetable: straight / lean-L / lean-R
    palm.png  sign.png  bg.png
gen_art.py      regenerates all PNG art (needs Python + Pillow)
```

## Tuning knobs
Feel lives in two clusters of constants:

`main.lua` (physics):
- `MAX_SPEED`, `LOW_CAP` — top speeds (overall / low gear)
- `ACCEL_LOW`, `ACCEL_HIGH`, `BRAKING`, `DECEL` — pedal response
- `CENTRIFUGAL` — how hard curves push you outward
- `STEER_K` — crank sensitivity; `DPAD_STEER` — d-pad fallback rate
- `OFF_CAP`, `OFF_DECEL` — off-road grip penalty

`road.lua` (look & camera):
- `ROAD_W`, `CAM_H`, `CAM_DEPTH` (FOV), `DRAW_DIST`
- `SEG_LEN`, `RUMBLE` — segment length / stripe band size
- `A_ROAD_*`, `A_GRASS_*` — dither "blackness" (0 = white, 1 = black). Road is
  kept near-white so the solid-black car reads against it; grass is mid-gray.
- `SPRITE_SCALE` — global roadside sprite size
