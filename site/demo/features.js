// The tiles' pictures, in the feature grid and under the first stage, are built only once their
// section comes within 1200 px of the viewport, so the page's first load never waits for them.
for (const section of document.querySelectorAll("#features, #screenshots .also")) {
  const near = new IntersectionObserver(([entry]) => {
    if (!entry.isIntersecting) return;
    near.disconnect();
    import("./features/tiles.js").then(({ buildFeatures }) => buildFeatures(section));
  }, { rootMargin: "1200px" });
  near.observe(section);
}
