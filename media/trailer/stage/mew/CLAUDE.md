# Mew

A browser game about a cat on the rooftops at night. In every level, the goal is to catch the moon.

## How it is built

- Each level is an SVG scene, 1600 wide and 1000 tall. `scene.js` has the pieces, and `levels.js`
  puts them together.
- Level 4's layout is data, in `level4.json`. Change the level by editing that file. The page in
  the browser reloads by itself.
  - `moon`: `[x, y, radius]`, or `null` for no moon.
  - `city`: `true` draws the distant city behind the roofs.
  - `waterTower`: `{"x": <centre>}` stands a water tower on the roof under that x, or `null`.
  - `ledges`: a list of `[x, y, width]`, each a ledge the cat can stand on, with its top at `y`.
- The roofs are fixed. The cat's roof runs from x -10 to 520 with its top at y 720. The middle roof
  runs from 706 to 1080 with its top at 700. The right roof's flat top runs from 1120 to 1570 at 550.
  A water tower on the middle roof has its top at y 420.
- A screenshot of the game shows the whole scene. A point in the image is a point in the scene,
  scaled by 1600 over the image's width.

## Catching the moon

The cat starts on its roof. It can jump 150 up and 220 across, from a roof, the top of a water tower,
or a ledge. It catches the moon from anything it can stand on whose top is at most 150 below the
moon's lowest point.

## Sketch a route before you build one

Where the cat's way up goes is the designer's decision. When a change leaves the moon out of the
cat's reach, do not build a route. Sketch one and ask:

1. Run `./screenshot sketch.png` to render the level as it is now.
2. Propose the ledges as boxes on that image, with a short note on what they are for. Write the
   marks as the vignette skill describes, to `sketch.json` in this folder.
3. Run `./push sketch.png sketch.json`, which shows the sketch in Vignette as yours. Use it instead
   of the skill's `open` command.

This folder allows those two shell commands and no others, and only exactly as written above: one
command per call, with nothing added before or after it, no `;`, `&&` or `echo`. Each prints what
it did, and exits non-zero if it failed.
4. Stop, and say in one line that the sketch is in Vignette.

When the sketch comes back, its boxes are where the designer wants the ledges. Build one ledge per
box, with the ledge's top at the box's top edge, even where you would have placed it differently.
