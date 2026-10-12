#include <metal_stdlib>
#include <SwiftUI/SwiftUI_Metal.h>
using namespace metal;

// The success check as a solid: a coin of tinted, glossy polymer with a glowing check mark inside it,
// ray marched and lit by what its surface reflects (docs/check-lab-2026-10-11.md). Lengths are in the
// view's points with the coin's centre at the origin, y down and z toward the viewer. The coin turns
// about the vertical axis by `turn` radians; at 0 its front face is square to the viewer and exactly
// the view's disc.

struct Coin {
    float radius;
    float rim;          // half the coin's thickness at its rim
    float edge;         // the radius its rim is rounded to
    float dome;         // how far the faces rise at the centre beyond `rim`
    float2 a, b, c;     // the mark's stroke: a to b, then b to c
    float weight;       // the radius of the mark's round stroke
};

static float segment(float2 p, float2 a, float2 b) {
    float2 pa = p - a, ba = b - a;
    return length(pa - ba * clamp(dot(pa, ba) / dot(ba, ba), 0.0, 1.0));
}

// A 2D distance `d` extruded between `low` and `high` along `z`, with its edges rounded to `r`.
static float extrude(float d, float z, float low, float high, float r) {
    float2 q = float2(d + r, abs(z - 0.5 * (low + high)) - 0.5 * (high - low) + r);
    return min(max(q.x, q.y), 0.0) + length(max(q, 0.0)) - r;
}

// The face's height above the middle plane at radius `r`: a slight dome.
static float face(float r, Coin c) {
    float u = min(r / c.radius, 1.0);
    return c.rim + c.dome * (1.0 - u * u);
}

static float coinDistance(float3 p, Coin c) {
    float r = length(p.xy);
    return extrude(r - c.radius, p.z, -face(r, c), face(r, c), c.edge);
}

// The mark: a round tube along the stroke in the coin's middle plane, so it shows through both
// faces, mirrored from the back as a real one would be.
static float markDistance(float3 p, Coin c) {
    float d = min(segment(p.xy, c.a, c.b), segment(p.xy, c.b, c.c));
    return length(float2(d, p.z)) - c.weight;
}

static float3 normalAt(float3 p, Coin c, float e) {
    float2 k = float2(1.0, -1.0);
    return normalize(k.xyy * coinDistance(p + k.xyy * e, c) + k.yyx * coinDistance(p + k.yyx * e, c)
                   + k.yxy * coinDistance(p + k.yxy * e, c) + k.xxx * coinDistance(p + k.xxx * e, c));
}

// The studio's walls as seen in the direction `R`: a bright ceiling, a soft horizon well below eye
// level and a dim floor.
static float room(float3 R, float roughness, float contrast) {
    float up = -R.y;
    float soft = 0.12 + 0.5 * roughness;
    float ceiling = mix(0.8, 1.0, smoothstep(-0.2, 0.8, up));
    float floor = 0.22 + 0.1 * smoothstep(-1.0, 0.0, up);
    float e = mix(floor, ceiling, smoothstep(-soft, soft, up + 0.45));
    return mix(0.6, e, contrast);
}

// The key light as seen in `R`: a soft box shaped like a window, its edges softened by roughness.
static float window(float3 R, float3 toLight, float key, float roughness) {
    // The box's own axes: across, level with the floor, and up, square to that and to the light.
    float3 across = normalize(cross(float3(0.0, -1.0, 0.0), toLight) + float3(1e-4, 0.0, 0.0));
    float3 up = cross(toLight, across);
    float2 q = abs(float2(dot(R, across), dot(R, up))) - float2(0.11, 0.05);
    float outside = length(max(q, 0.0)) + min(max(q.x, q.y), 0.0) - 0.02;
    float edge = 0.01 + 0.2 * roughness;
    return key * (1.0 - smoothstep(-edge, edge, outside)) * step(0.0, dot(R, toLight));
}

// The glint light as seen in `R`: a tall strip standing in `toStrip`'s direction. A turn sweeps the
// coin's reflections across it, so the face and the rim flash as they pass.
static float strip(float3 R, float3 toStrip, float strength, float roughness) {
    float3 across = normalize(float3(toStrip.z, 0.0, -toStrip.x));
    float width = 0.06 + 0.3 * roughness;
    float x = dot(R, across) / width;
    float tall = 1.0 - smoothstep(0.45, 0.75, abs(R.y));
    return strength * exp(-x * x) * tall * step(0.0, dot(R, toStrip));
}

// The polymer, its glow and the lights, as `checkCoin` takes them.
struct Studio {
    float3 tint, glowColour;
    float4 light, glint;
    float roughness, contrast, clarity, spread, glow;
};

// Where a ray meets the coin, or, when it misses, where it passed nearest.
struct Trace {
    bool hit;
    float t;
    float closest;
};

// The ray from `eye` toward `through` on the face's plane, in the coin's own frame, which is the world
// turned back by `turn` about y. `world` is the same ray in the world's frame.
struct Ray {
    float3 o, d, world;
};

static Ray rayThrough(float2 p, float3 eye, Coin c, float ct, float st) {
    Ray r;
    r.world = normalize(float3(p, c.rim) - eye);
    r.o = float3(ct * eye.x - st * eye.z, eye.y, st * eye.x + ct * eye.z);
    r.d = float3(ct * r.world.x - st * r.world.z, r.world.y, st * r.world.x + ct * r.world.z);
    return r;
}

// Marches only within the sphere of radius `bound` that holds the coin.
static Trace march(Ray r, Coin c, float bound) {
    Trace tr;
    tr.hit = false;
    tr.closest = 1e9;
    float b = dot(r.o, r.d), disc = b * b - dot(r.o, r.o) + bound * bound;
    tr.t = 0.0;
    if (disc < 0.0) return tr;
    float t = -b - sqrt(disc), far = -b + sqrt(disc);
    tr.t = t;
    for (int i = 0; i < 80 && t < far; i++) {
        float dist = coinDistance(r.o + r.d * t, c);
        if (dist < tr.closest) { tr.closest = dist; tr.t = t; }
        if (dist < 0.002 * c.radius) { tr.hit = true; tr.t = t; break; }
        t += 0.9 * dist;
    }
    // A ray that skims a surface closes on it in ever smaller steps and can run out of them while
    // still inside the sphere. It met that surface, at its nearest point.
    if (!tr.hit && t < far) tr.hit = true;
    return tr;
}

// What a ray sees, as light added over what is behind the coin, and how much of that it hides.
struct Shade {
    float3 light;
    float cover;
    float facing;       // 1 where the surface faces the viewer, 0 at the outline
};

// The coin at `at`, where `r` met it. The surface reflects the studio as glossy plastic does: a
// little face on and nearly all of it at a grazing angle, the lights white. The rest of the ray bends
// into the polymer, which tints it the longer it travels, and gathers the mark's glow on the way: its
// core where it meets the mark, and the halo the mark lights in the polymer around it.
static Shade shade(float3 at, Ray r, Coin c, Studio s, float ct, float st, float pixel) {
    float3 n = normalAt(at, c, 0.25 * pixel);
    // Back to the world's frame, where the studio is.
    float3 N = float3(ct * n.x + st * n.z, n.y, -st * n.x + ct * n.z);
    float3 R = reflect(r.world, N);
    float facing = clamp(dot(N, -r.world), 0.0, 1.0);
    float grazing = pow(1.0 - facing, 5.0);
    // Schlick's Fresnel for a polymer, whose reflectance face on is 4%. The lights are strong enough
    // that 4% of them still shows, so the face flashes as it turns past the strip, not only the rim.
    float fresnel = 0.04 + 0.96 * grazing;
    float lights = window(R, s.light.xyz, s.light.w, s.roughness) + strip(R, s.glint.xyz, s.glint.w, s.roughness);
    float coat = mix(0.25, 1.0, grazing);
    float3 surface = float3(fresnel * room(R, s.roughness, s.contrast) + coat * lights);

    // Into the polymer, bent as by a refractive index of 1.5.
    float3 d = refract(r.d, n, 1.0 / 1.5);
    float3 p = at - n * 0.01 * c.radius;
    float travelled = 0.0, halo = 0.0, core = 0.0;
    for (int i = 0; i < 40; i++) {
        float m = markDistance(p, c);
        float inside = -coinDistance(p, c);
        if (m < 0.002 * c.radius) { core = 1.0; break; }
        if (inside < 0.0) break;
        float dt = clamp(min(m, inside), 0.015 * c.radius, 0.08 * c.radius);
        halo += exp(-m / s.spread) * dt;
        p += d * dt;
        travelled += dt;
    }
    // About 1 for a ray that passes through the mark's halo, and falling away from it.
    halo /= 2.0 * s.spread;
    // The tint, deeper the farther the ray went: once its colour through the coin's thickness.
    float3 through = pow(max(s.tint, 0.001), float3(travelled / (2.0 * c.rim)));
    float clear = (1.0 - core) * dot(through, float3(0.2126, 0.7152, 0.0722));
    // The polymer scatters a little of the studio's light, lit from where its surface faces.
    float3 body = s.tint * mix(0.12, 0.45, room(N, 1.0, s.contrast)) * (1.0 - s.clarity * clear);
    float3 glow = s.glowColour * s.glow * (2.0 * core + halo * mix(float3(1.0), through, 0.5));

    Shade out;
    out.light = surface + (1.0 - fresnel) * (body + glow);
    out.cover = 1.0 - (1.0 - fresnel) * s.clarity * clear;
    out.facing = facing;
    return out;
}

// `shape`: radius, half thickness, rim rounding, dome, in points. `mark`: the stroke's first two
// points, x and y as fractions of the radius; `markEnd`: its last point, then its stroke's radius in
// points and the glow's strength. `light`: the direction to the key light and its strength; `glint`:
// the direction to the glint's strip and its strength. `surface`: roughness, studio contrast,
// clarity, and the glow's spread in points. `view`: the turn in radians, one pixel in points, and
// the view's side.
[[ stitchable ]] half4 checkCoin(float2 position, half4 colour, float4 shape, float4 mark, float4 markEnd,
                                 float3 tint, float3 glowColour, float4 light, float4 glint, float4 surface, float3 view) {
    Coin c;
    c.radius = shape.x;
    c.rim = shape.y;
    c.edge = min(shape.z, shape.y);
    c.dome = shape.w;
    c.a = mark.xy * c.radius;
    c.b = mark.zw * c.radius;
    c.c = markEnd.xy * c.radius;
    // The mark stays inside the coin, clear of both faces.
    c.weight = min(markEnd.z, 0.7 * c.rim);
    Studio s = { tint, glowColour, light, glint, surface.x, surface.y, surface.z, max(surface.w, 0.01), markEnd.w };
    float turn = view.x, pixel = view.y;
    float2 p = position - 0.5 * view.z;
    float ct = cos(turn), st = sin(turn);

    // A camera eight radii in front of the face, looking through the face's plane, so the front face
    // at rest fills the disc exactly and a turn foreshortens as a real coin does.
    float top = c.rim + c.dome;
    float3 eye = float3(0.0, 0.0, c.rim + 8.0 * c.radius);
    float bound = sqrt(c.radius * c.radius + top * top) + pixel;

    // One ray a pixel, except at the outline: the glow is soft, and four rays a pixel looked the
    // same at 15 and 22 pt everywhere else.
    Ray r = rayThrough(p, eye, c, ct, st);
    Trace tr = march(r, c, bound);
    // A ray that passes within a pixel of the coin's outline covers part of that pixel.
    float alpha = tr.hit ? 1.0 : clamp(1.0 - tr.closest / pixel, 0.0, 1.0);
    if (alpha <= 0.0) return half4(0.0);
    Shade sh = shade(r.o + r.d * tr.t, r, c, s, ct, st, pixel);
    if (tr.hit && sh.facing > 0.35) {
        return half4(half3(clamp(sh.light, 0.0, 1.0)), half(sh.cover));
    }
    // At the outline the rim turns from facing the viewer to grazing within a pixel, and a grazing
    // surface reflects nearly all of the bright studio. One ray there coloured the whole pixel with
    // its brightest point, a white ring round the coin, so the pixel averages four rays across it.
    const float2 offsets[4] = { float2(-0.125, -0.375), float2(0.375, -0.125), float2(0.125, 0.375), float2(-0.375, 0.125) };
    float3 sum = float3(0.0);
    float covered = 0.0;
    for (int k = 0; k < 4; k++) {
        Ray sub = rayThrough(p + offsets[k] * pixel, eye, c, ct, st);
        Trace subTrace = march(sub, c, bound);
        // Only a ray that meets the coin counts: one that passes it is coloured by the rim's most
        // grazing point, and brightened the outline again.
        if (!subTrace.hit) continue;
        Shade subShade = shade(sub.o + sub.d * subTrace.t, sub, c, s, ct, st, pixel);
        sum += clamp(subShade.light, 0.0, 1.0);
        covered += subShade.cover;
    }
    return half4(half3(0.25 * sum), half(0.25 * covered));
}

// The bloom's bright pass: what is brighter than `threshold`, scaled by `strength`. It is blurred
// and added over the check, so it spills past the coin's edge.
[[ stitchable ]] half4 checkBright(float2 position, half4 colour, float strength, float threshold) {
    float3 c = float3(colour.rgb);
    float k = strength * max(dot(c, float3(0.2126, 0.7152, 0.0722)) - threshold, 0.0) / max(1.0 - threshold, 0.05);
    return half4(half3(c * k), half(min(1.0, k * max(c.r, max(c.g, c.b)))));
}
