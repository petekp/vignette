#include <metal_stdlib>
#include <SwiftUI/SwiftUI_Metal.h>
using namespace metal;

// The success check, lit as polished metal (docs/check-lab-2026-10-11.md). The layer holds the check
// mark in white on clear, blurred over its bevel, so its alpha rises smoothly across the edge.
// `checkMetal` turns it into a raised mark on a domed disc and lights both by reflecting a studio,
// and `checkBright` picks out the brightest of the result for the bloom. Lengths are in the view's
// points, y down; a direction's z points at the viewer.

struct Shape {
    float2 centre;
    float radius;
    float pixel;
    float dome;         // how far the disc's middle rises, a fraction of its radius
    float rim;          // the width of the rounded rim, a fraction of the radius
    float markHeight;   // in points
    float markBevel;    // in points
};

// The disc's height at `p`, in points: a shallow dome with a rounded rim.
static float discHeight(float2 p, Shape s) {
    float r = length(p - s.centre) / s.radius;
    float dome = s.dome * s.radius * (1.0 - r * r);
    float b = max(s.rim, 0.01);
    float u = clamp((r - (1.0 - b)) / b, 0.0, 1.0);
    // A quarter round, so the rim turns to face sideways at the edge and catches grazing light.
    return dome + b * s.radius * sqrt(max(1.0 - u * u, 0.0));
}

// The mark's height at `p`, in points, from its blurred alpha.
static float markHeight(SwiftUI::Layer layer, float2 p, Shape s) {
    return s.markHeight * smoothstep(0.1, 0.9, float(layer.sample(p).a));
}

// The studio's walls as seen in the reflected direction `R`: a bright ceiling, a soft horizon well
// below eye level and a dim floor. The metal reflects them in its own colour.
static float room(float3 R, float roughness, float contrast) {
    float up = -R.y;
    float soft = 0.12 + 0.5 * roughness;
    float ceiling = mix(0.8, 1.0, smoothstep(-0.2, 0.8, up));
    float floor = 0.22 + 0.1 * smoothstep(-1.0, 0.0, up);
    float e = mix(floor, ceiling, smoothstep(-soft, soft, up + 0.45));
    return mix(0.6, e, contrast);
}

// The studio's lights as seen in `R`: the key light, a soft box as wide as a window whose edges
// soften with roughness, and the glare, a strip light swept across. They are reflected white, by a
// clear coat over the metal.
static float lights(float3 R, float3 toLight, float key, float roughness,
                    float glare, float glareWidth, float glareTilt, float glarePlace) {
    // The box's own axes: across, level with the floor, and up, square to that and to the light.
    float3 across = normalize(cross(float3(0.0, -1.0, 0.0), toLight) + float3(1e-4, 0.0, 0.0));
    float3 up = cross(toLight, across);
    float2 q = abs(float2(dot(R, across), dot(R, up))) - float2(0.11, 0.05);
    float outside = length(max(q, 0.0)) + min(max(q.x, q.y), 0.0) - 0.02;
    float edge = 0.01 + 0.2 * roughness;
    float e = key * (1.0 - smoothstep(-edge, edge, outside)) * step(0.0, dot(R, toLight));
    float3 strip = float3(cos(glareTilt), sin(glareTilt), 0.0);
    float width = sqrt(glareWidth * glareWidth + 0.1 * roughness * roughness);
    float d = (dot(R, strip) - glarePlace) / max(width, 0.005);
    return e + glare * exp(-d * d) * smoothstep(0.0, 0.3, R.z);
}

// `disc`: centre x, y, radius, one pixel. `form`: dome, rim, mark height, mark bevel, in points.
// `light`: the direction to the key light and its strength. `surface`: roughness, studio contrast,
// the mark's shadow strength and its reach in points. `glare`: strength, width, tilt in radians,
// place.
[[ stitchable ]] half4 checkMetal(float2 position, SwiftUI::Layer layer, float4 disc, float3 metal, float3 markColour,
                                  float4 form, float4 light, float4 surface, float4 glare) {
    Shape s;
    s.centre = disc.xy;
    s.radius = disc.z;
    s.pixel = disc.w;
    s.dome = form.x;
    s.rim = form.y;
    s.markHeight = form.z;
    s.markBevel = max(form.w, disc.w);

    float alpha = clamp((s.radius - length(position - s.centre)) / s.pixel + 0.5, 0.0, 1.0);
    if (alpha <= 0.0) return half4(0.0);

    // The disc's slope over a pixel; the mark's over half its bevel, since its alpha comes in 8-bit
    // steps that a pixel's difference turns into ridges.
    float e = s.pixel, m = 0.5 * s.markBevel;
    float dx = (discHeight(position + float2(e, 0), s) - discHeight(position - float2(e, 0), s)) / (2.0 * e)
             + (markHeight(layer, position + float2(m, 0), s) - markHeight(layer, position - float2(m, 0), s)) / (2.0 * m);
    float dy = (discHeight(position + float2(0, e), s) - discHeight(position - float2(0, e), s)) / (2.0 * e)
             + (markHeight(layer, position + float2(0, m), s) - markHeight(layer, position - float2(0, m), s)) / (2.0 * m);
    float3 N = normalize(float3(-dx, -dy, 1.0));
    float3 R = float3(2.0 * N.z * N.x, 2.0 * N.z * N.y, 2.0 * N.z * N.z - 1.0);

    float onMark = smoothstep(0.4, 0.6, float(layer.sample(position).a));
    float3 f0 = mix(metal, markColour, onMark);
    // Schlick's Fresnel: metal reflects its own colour face on and white at a grazing angle, and the
    // clear coat reflects more at a grazing angle too.
    float grazing = pow(1.0 - max(N.z, 0.0), 5.0);
    float3 fresnel = f0 + (1.0 - f0) * grazing;
    float coat = mix(0.4, 1.0, grazing);
    float3 colour = fresnel * room(R, surface.x, surface.y)
                  + coat * lights(R, light.xyz, light.w, surface.x, glare.x, glare.y, glare.z, glare.w);

    // The raised mark shades the disc on its far side from the light.
    float2 toLight = normalize(light.xy + float2(1e-4, 0.0));
    float shade = float(layer.sample(position + toLight * surface.w).a);
    colour *= 1.0 - surface.z * shade * (1.0 - onMark);

    colour = clamp(colour, 0.0, 1.0);
    return half4(half3(colour * alpha), half(alpha));
}

// The bloom's bright pass: what is brighter than `threshold`, scaled by `strength`. It is blurred
// and added over the check, so it spills past the disc's edge.
[[ stitchable ]] half4 checkBright(float2 position, half4 colour, float strength, float threshold) {
    float3 c = float3(colour.rgb);
    float k = strength * max(dot(c, float3(0.2126, 0.7152, 0.0722)) - threshold, 0.0) / max(1.0 - threshold, 0.05);
    return half4(half3(c * k), half(min(1.0, k * max(c.r, max(c.g, c.b)))));
}
