# Mew

A browser game about a cat on the rooftops at night.

## How it is built

- Each level is an SVG scene, 1600 wide and 1000 tall. `scene.js` has the pieces, and `levels.js`
  puts them together.
- Level 4's layout is data, in `level4.json`. Change the level by editing that file. The page in
  the browser reloads by itself.
  - `moon`: `[x, y, radius]`, or `null` for no moon.
  - `city`: `true` draws the distant city behind the roofs.
  - `waterTower`: `{"x": <centre>}` stands a water tower on the roof under that x, or `null`.
- The roofs are fixed. The cat's roof runs from x -10 to 520 with its top at y 720. The middle roof
  runs from 706 to 1080 with its top at 700. The right roof's flat top runs from 1120 to 1570 at 550.
  A water tower on the middle roof has its top at y 420.
- A screenshot of the game shows the whole scene. A point in the image is a point in the scene,
  scaled by 1600 over the image's width.

## The cat's first jump

The cat starts on its roof and jumps across the gap. It lands on the middle roof between x 706 and
840. Anything standing on the middle roof whose legs or base reach into that stretch blocks the
jump. A water tower's legs spread 68 either side of its centre.

## Check the jump after every change

After you change the level, check whether anything now blocks the cat's first jump. Where things
stand is the designer's decision, so do not move what blocks it. Show the designer and ask:

1. Run `./screenshot sketch.png` to render the level as it is now.
2. On that image, draw an arrow from the cat to what blocks it, and beside the arrow a text mark
   saying what is wrong in at most five words, such as "the tower blocks the jump". Then draw one
   box where you would move it, the size of what you would move, with the text mark "move it here?"
   beside it. Add no other marks: the designer reads the sketch at a glance. Write the marks as the
   vignette skill describes, to `sketch.json` in this folder.
3. Run `./push sketch.png sketch.json`, which shows the sketch in Vignette as yours. Use it instead
   of the skill's `open` command.
4. Stop, and say in one line that the sketch is in Vignette.

This folder allows those two shell commands and no others, and only exactly as written above: one
command per call, with nothing added before or after it, no `;`, `&&` or `echo`. Each prints what
it did, and exits non-zero if it failed.

When the sketch comes back, the box is where the designer wants the thing moved. Move it so its
centre is the box's centre, even where you would have placed it differently.
