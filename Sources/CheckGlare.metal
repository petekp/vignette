#include <metal_stdlib>
#include <SwiftUI/SwiftUI_Metal.h>
using namespace metal;

// The band of light that crosses the success check, and its bloom (docs/check-lab-2026-10-11.md).
// Lengths are in the view's points. The view is a square with the check's disc at its centre and
// room around it for the bloom, which spills past the disc's edge.

struct Band {
    float2 centre;
    float radius;       // the disc's
    float2 across;      // unit vector across the band
    float place;        // the band's centre along `across`, from the disc's centre
    float halfWidth;
    float peak;
    float pixel;        // one pixel, in points
};

// The band's light at `p`: brightest along its centre line, nothing past its edges or the disc's.
static float light(float2 p, Band b) {
    float2 d = p - b.centre;
    float inside = clamp((b.radius - length(d)) / b.pixel + 0.5, 0.0, 1.0);
    float x = abs(dot(d, b.across) - b.place) / b.halfWidth;
    return b.peak * max(1.0 - x, 0.0) * inside;
}

// `sweep` runs from -1, the band wholly off the disc's leading side, to 1, wholly off its trailing
// side. The bloom is the band's light above `threshold`, blurred with a Gaussian of `bloomRadius`
// sampled on rings, and added to the band at `bloom` strength. The result is white, premultiplied.
[[ stitchable ]] half4 checkGlare(float2 position, half4 color, float side, float diameter, float sweep,
                                  float width, float angle, float peak, float bloom, float bloomRadius,
                                  float threshold, float pixel) {
    Band b;
    b.centre = float2(side * 0.5);
    b.radius = diameter * 0.5;
    b.across = float2(cos(angle), sin(angle));
    b.halfWidth = max(width * 0.5, pixel);
    b.place = sweep * (b.radius + b.halfWidth);
    b.peak = peak;
    b.pixel = pixel;

    float glow = 0.0;
    if (bloom > 0.0 && bloomRadius > 0.0) {
        const int rings = 6;
        const int spokes = 16;
        float scale = 1.0 / max(1.0 - threshold, 0.05);
        float total = 1.0;
        glow = max(light(position, b) - threshold, 0.0) * scale;
        for (int ring = 1; ring <= rings; ring++) {
            float r = float(ring) / float(rings);
            // A Gaussian whose tail reaches about 5% at the bloom's radius. Every ring has as many taps
            // as the first, so a ring's weight grows with its radius, as its area does.
            float weight = exp(-3.0 * r * r) * float(ring);
            // Alternate rings are turned half a spoke, so the taps do not line up into rays.
            float turn = (ring % 2 == 0) ? M_PI_F / float(spokes) : 0.0;
            for (int spoke = 0; spoke < spokes; spoke++) {
                float a = turn + 2.0 * M_PI_F * float(spoke) / float(spokes);
                float2 q = position + r * bloomRadius * float2(cos(a), sin(a));
                glow += weight * max(light(q, b) - threshold, 0.0) * scale;
                total += weight;
            }
        }
        glow /= total;
    }
    float a = clamp(light(position, b) + bloom * glow, 0.0, 1.0);
    return half4(a);
}
