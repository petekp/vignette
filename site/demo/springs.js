// Springs, and whether the page may move at all (the system's Reduce Motion).
export const reducedMotion = matchMedia("(prefers-reduced-motion: reduce)");
export const motion = () => (reducedMotion.matches ? 0 : 1);

// Springs. SwiftUI's spring(duration:bounce:): stiffness (2π/d)², damping 4π(1-bounce)/d, mass 1.
// A spring sent to a new target keeps its velocity, so an interrupted motion blends instead of
// jumping, as the app's Tween does.

const active = new Set();
let frame = 0, last = 0;
function tick(now) {
  const dt = Math.min(0.05, last ? (now - last) / 1000 : 1 / 60);
  last = now;
  for (const m of [...active]) m.step(dt);
  frame = active.size ? requestAnimationFrame(tick) : ((last = 0), 0);
}
function wake(m) {
  active.add(m);
  if (!frame) frame = requestAnimationFrame(tick);
}

export class Spring {
  constructor(value, eps = 0.01) {
    this.x = value; this.v = 0; this.target = value; this.eps = eps;
    this.k = 0; this.c = 0; this.moving = false; this.waiters = [];
  }
  to(target, duration, bounce = 0) {
    this.target = target;
    const d = duration * motion();
    if (d <= 0) return this.jump(target);
    const w = (2 * Math.PI) / d;
    this.k = w * w; this.c = (4 * Math.PI * (1 - bounce)) / d; this.moving = true;
    return this;
  }
  jump(value) {
    this.x = value; this.target = value; this.v = 0; this.moving = false; this.settle();
    return this;
  }
  step(dt) {
    if (!this.moving) return;
    const n = Math.ceil(dt / 0.002), h = dt / n;
    for (let i = 0; i < n; i++) {
      const a = -this.k * (this.x - this.target) - this.c * this.v;
      this.v += a * h; this.x += this.v * h;
    }
    if (Math.abs(this.x - this.target) < this.eps && Math.abs(this.v) < this.eps * 20) {
      this.x = this.target; this.v = 0; this.moving = false; this.settle();
    }
  }
  settle() { const w = this.waiters; this.waiters = []; w.forEach((f) => f()); }
  arrived() { return this.moving ? new Promise((r) => this.waiters.push(r)) : Promise.resolve(); }
}

// A set of springs and the one function that draws them, called once a frame while any moves.
export class Motion {
  constructor(render) { this.render = render; this.springs = {}; }
  add(name, value, eps) { this.springs[name] = new Spring(value, eps); return this; }
  get(name) { return this.springs[name].x; }
  to(name, target, duration, bounce = 0) {
    const s = this.springs[name];
    if (!s.moving && s.x === target) return Promise.resolve();
    s.to(target, duration, bounce);
    this.springs[name].moving ? wake(this) : this.render(this);
    return this.springs[name].arrived();
  }
  jump(name, value) { this.springs[name].jump(value); this.render(this); }
  step(dt) {
    let moving = false;
    for (const s of Object.values(this.springs)) { s.step(dt); moving ||= s.moving; }
    this.render(this);
    if (!moving) active.delete(this);
  }
}

// A CSS linear() easing sampled from the same spring, for small state changes such as a hover.
function springEasing(duration, bounce = 0) {
  const s = new Spring(0, 0.0005).to(1, duration, bounce);
  const pts = [];
  for (let i = 0; i <= 40; i++) { pts.push(+s.x.toFixed(4)); s.step(duration / 40); }
  pts[40] = 1;
  return `linear(${pts.join(", ")})`;
}
document.documentElement.style.setProperty("--spring-fast", springEasing(0.15, 0.15));
document.documentElement.style.setProperty("--spring", springEasing(0.3, 0.15));
document.documentElement.style.setProperty("--spring-bouncy", springEasing(0.4, 0.45));
