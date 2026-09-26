# Paint Party

Paint one big picture together, with brush strokes, stamps and splats, then
frame it and print it for the fridge. A couch co-op game for a grown-up and
two small kids (5 and 2), for 1 to 3 players, on pads or one keyboard.

```
make setup     # once: Godot, GUT, the Python venv (repo root)
make start     # play
make demo      # watch it paint by itself
```

## How to play

1. **Join:** every player presses a button on their pad or keyboard block.
   The first one is the Brush. The Brush holds "a" (or presses Start) to go on.
2. **Pick riders:** left/right, "a" = ready. The Splatter's any button
   changes rider and it is ready by itself after 3 s.
3. **Paint** together. When the picture is done, the Brush presses Start and
   picks the gold frame. After 5 minutes the frame icon sparkles as a hint.
4. **The gallery** hangs the new picture next to the last two. It goes back to
   rider select for the next picture.

| Seat | Role | Pad | Keyboard |
|---|---|---|---|
| 1 | **Brush** (grown-up) | stick / d-pad moves, **A** held paints, **B** brush size (3), **Start** menu | kb:0: **WASD** moves, **Shift** or **Tab** paints, **Q** size, **Esc** menu |
| 2 | **Colourist** (5-year-old) | d-pad: each direction picks a pot, **A** stamps at the brush, **B** next palette page | kb:1: **arrows** pick a pot, **Enter** stamps, **Backspace** page |
| 3 | **Splatter** (2-year-old) | any button: a paint splat | kb:2: **Space** or any other key |

The Brush's menu (Start): undo (again and again, the last 10 actions), frame
it (save), keep painting, surprise splats (only without a Splatter), back to
join. Left/right chooses, A picks, Start closes, B goes back to join.

Fewer players:

- **Brush alone:** B changes the colour instead of the size; a quick tap of A
  (without moving) stamps; holding A paints. Surprise splats every 20 s can be
  turned on in the menu.
- **Brush + Colourist:** as above, without splats unless turned on in the menu.
- **Brush + Splatter:** Space always takes the Splatter seat; the Brush then
  picks colours and stamps like when alone.

The stamps come in order: star, heart, flower, fish, sun, cat, car, house.
The middle of the pot cross shows the next one. Splats land on the empty
parts of the picture, and every 5th is a rainbow.

## Where the pictures go

Every framed picture is saved as a 1920x1080 PNG in
`~/.local/share/godot/app_userdata/Paint Party/paintings/` and copied to
`~/Pictures/PaintParty/`. The picture in progress autosaves every 30 s there
too (`wip-*.png`), so a crash never loses it.
