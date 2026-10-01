#include <metal_stdlib>
#include <SwiftUI/SwiftUI_Metal.h>
using namespace metal;

// The picture pouring into the menu bar icon (docs/intro-funnel-2026-09-30.md). All lengths are in
// the view's points, y down. A row `v` of the picture runs from 0 at its top edge to 1 at its
// bottom, and the top edge leads, since the menu bar is always above the window.

struct Shape {
    float4 card;        // the picture's rect: x, y, width, height
    float4 icon;        // the icon's rect
    float t;            // 0 to 1 over the flight
    float strength;     // 0 moves every row together, 1 is the full funnel
    float smoothing;    // 0 starts and stops each row abruptly, 1 eases both
};

struct Row { float y; float cx; float halfWidth; float s; };

static float progress(float v, Shape shape) {
    float stagger = 0.6 * shape.strength;
    float s = clamp((shape.t - stagger * v) / (1.0 - stagger), 0.0, 1.0);
    // Eased at both ends, a row leaves and joins its neighbours without a corner in the outline.
    return mix(s, s * s * (3.0 - 2.0 * s), shape.smoothing);
}

static Row row(float v, Shape shape) {
    float s = progress(v, shape);
    // Travel accelerates into the icon; the narrowing runs ahead of it as `strength` rises.
    float travel = s * s;
    float narrow = mix(travel, 1.0 - (1.0 - s) * (1.0 - s), shape.strength);
    float4 card = shape.card, icon = shape.icon;
    Row r;
    r.y = mix(card.y + v * card.w, icon.y + v * icon.w, travel);
    r.cx = mix(card.x + card.z * 0.5, icon.x + icon.z * 0.5, narrow);
    r.halfWidth = max(mix(card.z, icon.z, narrow) * 0.5, 0.0);
    r.s = s;
    return r;
}

// The row at height `y`: a row's place rises with v, so halving finds it.
static float rowAt(float y, Shape shape) {
    float low = 0.0, high = 1.0;
    for (int i = 0; i < 18; i++) {
        float mid = 0.5 * (low + high);
        if (row(mid, shape).y < y) low = mid; else high = mid;
    }
    return 0.5 * (low + high);
}

// How far `p` is inside the bent shape's edge, negative outside, with the corners rounded on screen
// whatever the rows have done to the picture's own: from the window's `cardRadius` to `corner` as
// their rows leave. `v` and `r` are the row at `p`'s height, or the nearest end row.
static float edgeDistance(float2 p, Shape shape, float cardRadius, float corner, thread float &v, thread Row &r) {
    Row first = row(0.0, shape), last = row(1.0, shape);
    v = rowAt(clamp(p.y, first.y, last.y), shape);
    r = row(v, shape);
    // Across the side's slant, measured from the rows just above and below.
    float dv = 1.0 / max(shape.card.w, 1.0);
    Row above = row(max(v - dv, 0.0), shape), below = row(min(v + dv, 1.0), shape);
    float dy = max(below.y - above.y, 1.0e-4);
    float side = p.x < r.cx ? -1.0 : 1.0;
    float slope = ((below.cx + side * below.halfWidth) - (above.cx + side * above.halfWidth)) / dy;
    float across = (r.halfWidth - abs(p.x - r.cx)) / sqrt(1.0 + slope * slope);
    float top = p.y - first.y, bottom = last.y - p.y;
    bool nearTop = top < bottom;
    float radius = min(mix(cardRadius, corner, nearTop ? first.s : last.s), max(r.halfWidth, 0.0));
    // A rounded box's distance: inside, the nearer of the side and the end; in a corner, from the
    // corner's circle; outside, from the shape.
    float2 k = radius - float2(across, nearTop ? top : bottom);
    return -(length(max(k, 0.0)) + min(max(k.x, k.y), 0.0) - radius);
}

// `fade` is the share of each row's travel over which it fades into the icon, so the pour drains
// into it rather than piling up there; the last row is gone as it arrives. `smear` averages the
// picture across the stretch a squeezed pixel covers, so squeezed text softens instead of breaking
// up. `rim` lights the bent edges. `shadow` is the window's shadow as (opacity, spread, drop), all
// but the opacity in points; the window server's is a soft edge, so it is drawn from the distance
// to the shape rather than by SwiftUI, whose shadow did not draw under this effect (take 17).
// `pixel` is a device pixel in points, the width over which an edge fades.
[[ stitchable ]] half4 funnel(float2 position, SwiftUI::Layer layer, float4 card, float4 icon, float t,
                              float strength, float smoothing, float corner, float cardRadius, float smear,
                              float rim, float fade, float3 shadow, float pixel) {
    Shape shape = { card, icon, t, strength, smoothing };
    Row first = row(0.0, shape), last = row(1.0, shape);
    float reach = 3.0 * shadow.y + shadow.z;
    if (position.y < first.y - reach || position.y > last.y + reach) return half4(0.0);

    // The shadow: the shape's distance from a point the drop above this one, through a soft edge.
    half4 under = half4(0.0);
    if (shadow.x > 0.0) {
        float sv; Row sr;
        float d = edgeDistance(position - float2(0.0, shadow.z), shape, cardRadius, corner, sv, sr);
        under = half4(0.0, 0.0, 0.0, shadow.x / (1.0 + exp(-1.702 * d / max(shadow.y, 1.0e-3))));
    }

    float v; Row r;
    float edge = edgeDistance(position, shape, cardRadius, corner, v, r);
    float alpha = clamp(edge / pixel + 0.5, 0.0, 1.0);
    if (alpha <= 0.0 || r.halfWidth <= 0.0) return under;

    // The point of the picture here, and how much picture one point of screen covers.
    float dv = 1.0 / max(card.w, 1.0);
    float dy = max(row(min(v + dv, 1.0), shape).y - row(max(v - dv, 0.0), shape).y, 1.0e-4);
    float u = clamp((position.x - (r.cx - r.halfWidth)) / (2.0 * r.halfWidth), 0.0, 1.0);
    float2 source = float2(card.x + u * card.z, card.y + v * card.w);
    float2 span = float2(card.z / max(2.0 * r.halfWidth, 1.0e-3), 2.0 * card.w * dv / dy);
    float2 spread = 0.5 * smear * max(span - 1.0, 0.0);
    half4 color = half4(0.0);
    for (int i = 0; i < 4; i++) {
        for (int j = 0; j < 4; j++) {
            float2 offset = (float2(i, j) + 0.5) / 4.0 * 2.0 - 1.0;
            color += layer.sample(source + offset * spread);
        }
    }
    color /= 16.0;

    // A thin light along the bent edges, only on rows that have left.
    float light = rim * r.s * (1.0 - smoothstep(0.0, 3.0, edge));
    color.rgb += half3(light) * color.a;
    float drain = 1.0 - smoothstep(1.0 - max(fade, 1.0e-3), 1.0, r.s);
    color *= half(alpha * drain);
    // The picture over its shadow.
    return color + under * (1.0h - color.a);
}
