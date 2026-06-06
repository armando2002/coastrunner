# Meowta Racer

A pseudo-3D arcade racer for the Playdate, written in Lua — an homage to the
coastal cruisers of the late-'80s/early-'90s arcades, relocated to the misty
Pacific Northwest. You drive the **Meowta** (a silver Miata, naturally) with a
black tuxedo cat riding shotgun, carving a forest highway past evergreen ridges
with Mt. Rainier on the horizon. All original art, code, and synth audio — no
third-party assets. The road uses the classic segment-projection technique (à la
Lou's pseudo-3D road / jakesgordon's model), adapted to the 400×240 1-bit display.

<img width="400" height="240" alt="meowtaracerdemo" src="https://github.com/user-attachments/assets/a9b85adb-056a-4bee-b89a-7ee220a428fc" />

## Play
Title screen → **A** to start → a short *How To Drive* card → **A** to go.

- **Crank** — steer (faster spin = sharper turn, scaled by speed)
- **D-pad ◄ ►** — steer (fallback when the crank is docked)
- **A** — gas  ·  **B** — brake
- **D-pad ▲ / ▼** — shift HIGH / LOW gear
- **B + ▲** — bail back to the title screen

Gearing has real depth: **LOW** accelerates hard but tops out around half speed;
**HIGH** reaches full speed but bogs at low RPM. Launch in LOW, shift to HIGH on
the straights — just like the arcade.

Mind the scenery: clip a roadside fir or a chevron sign and the Meowta cartwheels
into a crash (tracked on the `DMG` counter). There's a free grass shoulder, so
running a little wide only scrubs speed — you only wreck if you actually hit
something. The course runs through varied movements — a launch straight, long
sweepers, a steep crest, tight chicanes, descents, and a run to the finish.

## Build
Requires the [Playdate SDK](https://play.date/dev/). Point `pdc` at the source:

```bash
pdc Source MeowtaRacer.pdx
```

Then run it in the simulator (`PlaydateSimulator MeowtaRacer.pdx`, or
**File → Open** in the Simulator). If `pdc` can't find `CoreLibs`, set the SDK
path first:

```bash
export PLAYDATE_SDK_PATH="$HOME/Downloads/PlaydateSDK-<version>"
```

To sideload to hardware: build the `.pdx`, then use the Simulator's
**Device → Upload Game to Device**, or zip the `.pdx` and upload via the
Playdate web sideload page.

## Art pipeline
Most art is generated procedurally in Python (needs `Pillow` + `numpy`); each
script writes straight into `Source/images/`:

| Script | Output | Notes |
| --- | --- | --- |
| `draw_title.py`  | `title.png` | PNW attract screen (Rainier, ridges, firs, wordmark). `TITLE` constant renames the logo. |
| `draw_bg.py`     | `bg.png`    | Tiling in-game horizon (ridges + Rainier + treeline). |
| `draw_meowta.py` | `meowta-table-72-48.png` | Player car + driver + tuxedo cat. `SHOW_CAT` toggles the cat. |
| `convert_meowta.py` | `meowta-table-72-48.png` | Legacy: converts a hand-drawn `meowta.png` sheet into the 1-bit table. Superseded by `draw_meowta.py`. |
| `gen_art.py`     | `bg/sign/...` | Original base-art generator. |

> **Heads-up:** `palm.png` (the fir trees) is hand-pixeled in Aseprite, *not*
> generated. Don't run `gen_art.py` expecting to keep it — that script would
> overwrite `palm.png`. Edit firs in Aseprite; re-run `draw_title.py` /
> `draw_bg.py` afterward so the title and horizon pick up the new tree.

## Project layout
```
Source/
  main.lua      game states, physics, input, HUD, parallax bg, player car + crash
  road.lua      track build + 3D projection + segment/sprite rendering + collision
  audio.lua     RPM-driven synth engine + original title arpeggio
  pdxinfo       game metadata
  images/
    title.png                 attract-screen background
    bg.png                    tiling in-game horizon
    meowta-table-72-48.png    player car (straight / lean-L / lean-R)
    palm.png                  roadside fir (hand-drawn)
    sign.png                  chevron hazard sign
draw_title.py  draw_bg.py  draw_meowta.py  convert_meowta.py  gen_art.py
```
