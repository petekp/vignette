// The feature tiles' pictures: each shows its feature in Vignette's own UI, built from the page's
// cards, marks and springs. A picture plays its moment once when its tile scrolls into view, then
// holds on the result; pointing at the tile, or tapping it, plays it again. With Reduce Motion on,
// each shows its result and never moves.
import { motion } from "../vignette.js";
import { reducedMotion } from "../springs.js";
import { Front } from "./front.js";
import { Flight } from "./flight.js";
import { Arrows, Later, Quick } from "./drawing.js";
import { Queue } from "./queue.js";
import { Agent } from "./agent.js";
import { Recent, Stitch, Drag } from "./stack.js";

// Every scene is laid out for a width W in its own points and scaled by k to its tile. Each has
// four states: reset() is the first frame, final() the last, play() runs the moment from one to
// the other, and rewind() goes back to the first frame with motion, so a replay never jumps.
const SCENES = {
  front: Front, flight: Flight, arrows: Arrows, later: Later, queue: Queue, agent: Agent,
  recent: Recent, quick: Quick, stitch: Stitch, drag: Drag,
};

class Tile {
  constructor(root) {
    this.root = root;
    this.slot = root.querySelector(".feature-pic");
    this.Scene = SCENES[root.dataset.scene];
    this.played = false;
    this.playing = false;
    this.fit();
    new ResizeObserver(() => this.fit()).observe(this.slot);
  }
  // A new layout only when the tile's width asks for one; otherwise the scene is only rescaled.
  fit() {
    const width = this.slot.clientWidth;
    if (!width) return;
    const f = this.Scene.fit(width, this.slot.clientHeight);
    if (f.key !== this.key) {
      this.key = f.key;
      this.scene = new this.Scene();
      this.node?.remove();
      this.node = this.scene.build(f);
      this.slot.append(this.node);
      // A scene rebuilt after its play began shows the result, which the play would have reached.
      if (!motion()) this.poster();
      else this.played || this.playing ? this.scene.final() : this.scene.reset();
    }
    this.node.style.transform = `scale(${f.k})`;
    this.slot.style.minHeight = `${Math.round(f.rest * f.k)}px`;
  }
  // With Reduce Motion, the one frame that tells the story, which is the end unless a scene says.
  poster() { this.scene.poster ? this.scene.poster() : this.scene.final(); }
  async run(again) {
    if (this.playing || !motion()) return;
    this.playing = true;
    const scene = this.scene;
    try {
      if (again) await scene.rewind();
      if (scene !== this.scene) return;
      await scene.play();
      this.played = true;
    } finally { this.playing = false; }
  }
}

export function buildFeatures(section) {
  const tiles = [...section.querySelectorAll(".feature")].map((root) => new Tile(root));
  // Reduce Motion turned on shows every result at once; turned off, the next scroll or point plays.
  if (!motion()) tiles.forEach((tile) => { tile.played = true; });
  reducedMotion.addEventListener("change", () => {
    if (motion()) return;
    tiles.forEach((tile) => { tile.played = true; tile.poster(); });
  });
  // Tiles that come into view together start a third of a second apart, in reading order, so the
  // eye can follow one before the next moves.
  const seen = new IntersectionObserver((entries) => {
    entries.filter((e) => e.isIntersecting)
      .map((e) => tiles.find((t) => t.root === e.target))
      .sort((a, b) => tiles.indexOf(a) - tiles.indexOf(b))
      .forEach((tile, i) => {
        seen.unobserve(tile.root);
        setTimeout(() => tile.run(tile.played), 250 + i * 350);
      });
  }, { threshold: 0.55 });
  tiles.forEach((tile) => {
    seen.observe(tile.root);
    // Pointing at a tile that has played plays it again once the pointer has stayed still there for
    // 0.4 s, so a pointer passing across the grid, or moving within a tile, sets nothing off. It
    // plays once per visit; looking around the result afterwards leaves it alone.
    let rest = 0, armed = false;
    const settle = (e) => {
      if (e.pointerType !== "mouse" || !armed) return;
      clearTimeout(rest);
      rest = setTimeout(() => { if (tile.played && !tile.playing) { armed = false; tile.run(true); } }, 400);
    };
    tile.root.addEventListener("pointerenter", (e) => { armed = true; settle(e); });
    tile.root.addEventListener("pointermove", settle);
    tile.root.addEventListener("pointerleave", () => { armed = false; clearTimeout(rest); });
    // A click or a tap on the picture plays it again. A scroll gesture cancels its pointer, and a
    // drag across the copy to select it ends on the words, so neither replays.
    tile.slot.addEventListener("pointerup", (e) => { if (e.button === 0 && tile.played) tile.run(true); });
  });
}
