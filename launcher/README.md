# Couch Games launcher

Pick any of the couch co-op games from the sofa with a controller. Big
cover cards slide left and right over a starry night sky; the focused card
glows, shows the game's one-line pitch underneath, and A launches it with a
whoosh. When the game ends, you are back on the same card.

```
make launcher            # from the repo root: fullscreen, for the TV
make launcher-window     # a window, for development
make install-desktop     # add "Couch Games" to the desktop app menu
make covers              # recapture every game's cover.png
```

| Do | Pad (any pad) | Keyboard |
|---|---|---|
| Choose a game | d-pad or left stick left/right | arrows or A/D |
| Play it | A (or X, or the right trigger) | Enter or Space |
| Leave a game, back to the launcher | hold Back/Select + Start for 1.5 s | Ctrl+Q |
| Switch the launcher off | the "Turn off" card at the end: hold A for 2 s | same, hold Enter |

- **Who is here**: the coloured bubbles at the top right, one per connected
  pad and one per keyboard block that has been used. They hop when that
  player presses something. Plugging a pad in or out is fine at any time.
- **Last played** comes first, with a green badge.
- Greyed cards marked **Coming soon** are games that only have a plan so far.
- A game with no `cover.png` yet shows a coloured card with its initial.
  Run `make covers` at the root once the game is committed.
- The first launch of a game on a fresh clone shows a spinner while Godot
  imports it (a few seconds, once).

Autostart on login is not set up. If you want it, copy the desktop entry:
`cp ~/.local/share/applications/couch-games.desktop ~/.config/autostart/`.

How it is built: [CLAUDE.md](CLAUDE.md).
