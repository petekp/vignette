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
import { Recent } from "./recent.js";
import { Stitch, Drag } from "./stack.js";

// Every scene is laid out for a width W in its own points and scaled by k to its tile. Each has
// four states: reset() is the first frame, final() the last, play() runs the moment from one to
// the other, and rewind() goes back to the first frame with motion, so a replay never jumps.
const SCENES = {
  front: Front, flight: Flight, arrows: Arrows, later: Later, queue: Queue, agent: Agent,
  recent: Recent, quick: Quick, stitch: Stitch, drag: Drag,
};

// A tile is in view while this much of it is on screen.
const SEEN = 0.55;

class Tile {
  constructor(root) {
    this.root = root;
    this.slot = root.querySelector(".feature-pic");
    this.Scene = SCENES[root.dataset.scene];
    this.played = false;
    this.playing = false;
    this.inView = false;
    this.offScreen = true;
    this.unseen = false;
    this.fit();
    this.showReplay();
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
  // Reduce Motion turned on. A running play would run on to its end at zero duration, and springs
  // it started keep their speed, so the scene is replaced by a new one that shows the poster, and
  // the old one finishes off the page.
  still() {
    this.played = true;
    this.key = null;
    this.fit();
    this.showReplay();
  }
  // The pointer offers a replay where a click gives one: on a picture that has played, between plays.
  showReplay() { this.slot.classList.toggle("replays", motion() > 0 && this.played && !this.playing); }
  // `ratio` is how much of the tile is on screen. A play that ran while the tile was mostly off
  // screen went unseen, and the tile plays again when it comes back.
  view(ratio) {
    this.inView = ratio >= SEEN;
    this.offScreen = ratio === 0;
    if (this.playing && !this.inView) this.unseen = true;
    this.settle();
  }
  // An unseen play's result goes back to the first frame while no part of the tile is on screen,
  // where nobody sees it jump, so the tile comes back to play as it did on its first scroll-in.
  settle() {
    if (this.playing || !this.unseen || !this.offScreen) return;
    this.unseen = false;
    this.played = false;
    this.scene.reset();
    this.showReplay();
  }
  get due() { return this.inView && !this.playing && motion() > 0 && (!this.played || this.unseen); }
  start() { if (this.due) this.run(this.played); }
  async run(again) {
    if (this.playing || !motion()) return;
    this.playing = true;
    this.unseen = false;
    this.showReplay();
    const scene = this.scene;
    try {
      if (again) await scene.rewind();
      if (scene !== this.scene) return;
      await scene.play();
      this.played = true;
    } finally {
      this.playing = false;
      this.showReplay();
      this.settle();
      // Back in view before an unseen play ended: it plays again from its first frame.
      if (this.due) setTimeout(() => this.start(), 250);
    }
  }
}

export function buildFeatures(section) {
  const tiles = [...section.querySelectorAll(".feature")].map((root) => new Tile(root));
  // Reduce Motion turned on shows every result at once; turned off, the next scroll or point plays.
  if (!motion()) tiles.forEach((tile) => { tile.played = true; tile.showReplay(); });
  // A list of its own, read nowhere else: Chrome fired no "change" on the springs' list, which a
  // play reads on every step.
  matchMedia(reducedMotion.media).addEventListener("change", (e) => {
    tiles.forEach((tile) => {
      if (e.matches) { tile.still(); return; }
      // The poster can differ from the end, which a replay rewinds from, so the scene is rebuilt there.
      tile.key = null;
      tile.fit();
      tile.unseen = true;
      tile.settle();
      tile.showReplay();
    });
  });
  // Tiles that come into view together start a third of a second apart, in reading order, so the
  // eye can follow one before the next moves.
  const watch = new IntersectionObserver((entries) => {
    const changed = entries.map((e) => {
      const tile = tiles.find((t) => t.root === e.target);
      tile.view(e.isIntersecting ? e.intersectionRatio : 0);
      return tile;
    });
    changed.filter((tile) => tile.due)
      .sort((a, b) => tiles.indexOf(a) - tiles.indexOf(b))
      .forEach((tile, i) => setTimeout(() => tile.start(), 250 + i * 350));
  }, { threshold: [0, SEEN] });
  tiles.forEach((tile) => {
    watch.observe(tile.root);
    // Pointing at a tile that has played plays it again once the pointer has stayed still there for
    // 0.4 s, so a pointer passing across the grid, or moving within a tile, sets nothing off. A
    // pointer that arrives or moves during a play has watched it, so that visit replays nothing,
    // and a visit replays once; looking around the result afterwards leaves it alone.
    let rest = 0, armed = false;
    const settle = (e) => {
      if (e.pointerType !== "mouse" || !armed) return;
      clearTimeout(rest);
      if (tile.playing) { armed = false; return; }
      rest = setTimeout(() => { armed = false; if (tile.played && !tile.playing) tile.run(true); }, 400);
    };
    tile.root.addEventListener("pointerenter", (e) => { armed = true; settle(e); });
    tile.root.addEventListener("pointermove", settle);
    tile.root.addEventListener("pointerleave", () => { armed = false; clearTimeout(rest); });
    // A click or a tap on the picture plays it again. A scroll gesture cancels its pointer, and a
    // drag across the copy to select it ends on the words, so neither replays.
    tile.slot.addEventListener("pointerup", (e) => { if (e.button === 0 && tile.played) tile.run(true); });
  });
}
