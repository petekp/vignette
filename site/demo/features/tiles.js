// The feature tiles' pictures: each shows its feature in Vignette's own UI, built from the page's
// cards, marks and springs. A picture plays its moment once when its tile scrolls into view, then
// holds on the result; pointing at the tile, or tapping it, plays it again. With Reduce Motion on,
// each shows its result and never moves.
import { motion } from "../vignette.js";
import { Front } from "./front.js";
import { Flight } from "./flight.js";
import { Arrows, Later } from "./drawing.js";
import { Queue } from "./queue.js";
import { Agent } from "./agent.js";

// Every scene is laid out for a width W in its own points and scaled by k to its tile. Each has
// four states: reset() is the first frame, final() the last, play() runs the moment from one to
// the other, and rewind() goes back to the first frame with motion, so a replay never jumps.
const SCENES = { front: Front, flight: Flight, arrows: Arrows, later: Later, queue: Queue, agent: Agent };

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
      this.played && !this.playing ? this.scene.final() : this.scene.reset();
      if (!motion()) this.scene.final();
    }
    this.node.style.transform = `scale(${f.k})`;
    this.slot.style.minHeight = `${Math.round(f.rest * f.k)}px`;
  }
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
  if (!motion()) return;
  // Tiles that come into view together play a tenth of a second apart, in reading order.
  const seen = new IntersectionObserver((entries) => {
    entries.filter((e) => e.isIntersecting)
      .map((e) => tiles.find((t) => t.root === e.target))
      .sort((a, b) => tiles.indexOf(a) - tiles.indexOf(b))
      .forEach((tile, i) => {
        seen.unobserve(tile.root);
        setTimeout(() => tile.run(false), 250 + i * 110);
      });
  }, { threshold: 0.55 });
  tiles.forEach((tile) => {
    seen.observe(tile.root);
    // Pointing at a tile that has played plays it again, once the pointer rests there a moment, so
    // a pointer passing across the grid sets nothing off. A tap does the same on a touch screen.
    let rest = 0;
    tile.root.addEventListener("pointerenter", (e) => {
      if (e.pointerType !== "mouse") return;
      rest = setTimeout(() => { if (tile.played) tile.run(true); }, 150);
    });
    tile.root.addEventListener("pointerleave", () => clearTimeout(rest));
    tile.root.addEventListener("pointerup", (e) => { if (e.pointerType !== "mouse" && tile.played) tile.run(true); });
  });
}
