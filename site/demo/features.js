// The tiles' pictures, in the feature grid and under the first stage, are built once the page has
// loaded and the browser is idle, so the page's first load never waits for them, and a jump to a
// tile finds its picture already there. A section that comes within 1200 px sooner is built then.
const built = new Set();
function build(section) {
  if (built.has(section)) return;
  built.add(section);
  import("./features/tiles.js").then(({ buildFeatures }) => buildFeatures(section));
}
const sections = [...document.querySelectorAll("#features, #screenshots .also")];
for (const section of sections) {
  const near = new IntersectionObserver(([entry]) => {
    if (!entry.isIntersecting) return;
    near.disconnect();
    build(section);
  }, { rootMargin: "1200px" });
  near.observe(section);
}
const idle = (f) => ("requestIdleCallback" in window ? requestIdleCallback(f, { timeout: 2000 }) : setTimeout(f, 200));
const whenLoaded = (f) => (document.readyState === "complete" ? f() : addEventListener("load", f, { once: true }));
whenLoaded(() => idle(() => sections.forEach(build)));
