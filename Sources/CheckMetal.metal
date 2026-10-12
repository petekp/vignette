#include <metal_stdlib>
#include <SwiftUI/SwiftUI_Metal.h>
using namespace metal;

// The success check as a solid: a green coin with a chrome check mark standing on each face, ray
// marched and lit by what it reflects (docs/check-lab-2026-10-11.md). Lengths are in the view's
// points with the coin's centre at the origin, y down and z toward the viewer. The coin turns about
// the vertical axis by `turn` radians; at 0 its front face is square to the viewer and exactly the
// view's disc.

struct Coin {
    float radius;
    float rim;          // half the coin's thickness at its rim
    float edge;         // the radius its rim is rounded to
    float dome;         // how far the faces rise at the centre beyond `half`
    float2 a, b, c;     // the mark's stroke: a to b, then b to c
    float weight;       // half the stroke's width
    float height;       // how far the mark stands off the face
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

// The mark on whichever face `p` is nearer. The back's is mirrored, so it reads the right way round
// when the back is toward the viewer.
static float markDistance(float3 p, Coin c) {
    float side = p.z >= 0.0 ? 1.0 : -1.0;
    float2 q = float2(p.x * side, p.y);
    float d = min(segment(q, c.a, c.b), segment(q, c.b, c.c)) - c.weight;
    float base = face(length(p.xy), c);
    // Rounded right across the stroke where it is no taller than wide, so its top is a bead that
    // carries reflections rather than a flat that shows one grey.
    return extrude(d, abs(p.z), base - c.height, base + c.height, 0.95 * min(c.weight, c.height));
}

// The scene's distance at `p`, and in `mark` whether the mark is the nearer surface.
static float scene(float3 p, Coin c, thread bool &mark) {
    float coin = coinDistance(p, c);
    float m = markDistance(p, c);
    mark = m < coin;
    return min(coin, m);
}

static float scene(float3 p, Coin c) {
    bool mark;
    return scene(p, c, mark);
}

static float3 normalAt(float3 p, Coin c, float e) {
    float2 k = float2(1.0, -1.0);
    return normalize(k.xyy * scene(p + k.xyy * e, c) + k.yyx * scene(p + k.yyx * e, c)
                   + k.yxy * scene(p + k.yxy * e, c) + k.xxx * scene(p + k.xxx * e, c));
}

// How much of the light reaches `p`: a soft shadow, darker the nearer the ray toward the light
// passes to the mark or the rim.
static float shadow(float3 p, float3 toLight, Coin c, float reach) {
    float lit = 1.0, t = 0.02 * c.radius;
    for (int i = 0; i < 24 && t < reach; i++) {
        float d = scene(p + toLight * t, c);
        lit = min(lit, 10.0 * d / t);
        if (lit < 0.01) break;
        t += clamp(d, 0.01 * c.radius, 0.1 * c.radius);
    }
    return clamp(lit, 0.0, 1.0);
}

// How open the surface at `p` is to the room: less where the mark meets the face.
static float openness(float3 p, float3 n, Coin c) {
    float closed = 0.0;
    for (int i = 1; i <= 4; i++) {
        float h = 0.03 * c.radius * float(i);
        closed += (h - scene(p + n * h, c)) / exp2(float(i));
    }
    return clamp(1.0 - 12.0 * closed / c.radius, 0.0, 1.0);
}

// The studio's walls as seen in the reflected direction `R`: a bright ceiling, a soft horizon well
// below eye level and a dim floor. Metal reflects them in its own colour.
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

// What the studio looks like: the metals, the lights and the surface, as `checkCoin` takes them.
struct Studio {
    float3 metal, markColour;
    float4 light, glint;
    float3 surface;
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
        float dist = scene(r.o + r.d * t, c);
        if (dist < tr.closest) { tr.closest = dist; tr.t = t; }
        if (dist < 0.002 * c.radius) { tr.hit = true; tr.t = t; break; }
        t += 0.9 * dist;
    }
    // A ray that skims a surface closes on it in ever smaller steps and can run out of them while
    // still inside the sphere. It met that surface, at its nearest point.
    if (!tr.hit && t < far) tr.hit = true;
    return tr;
}

// The colour at `at`, where `r` met the coin. `onMark` says which surface it is.
static float3 shade(float3 at, bool onMark, Ray r, Coin c, Studio s, float ct, float st, float pixel) {
    float3 n = normalAt(at, c, 0.25 * pixel);
    // Back to the world's frame, where the studio is.
    float3 N = float3(ct * n.x + st * n.z, n.y, -st * n.x + ct * n.z);
    float3 R = reflect(r.world, N);
    float3 toLight = s.light.xyz;
    float3 toLightHere = float3(ct * toLight.x - st * toLight.z, toLight.y, st * toLight.x + ct * toLight.z);

    float3 f0 = onMark ? s.markColour : s.metal;
    // Schlick's Fresnel: metal reflects its own colour face on and white at a grazing angle. The
    // green has a clear coat, which reflects the light white, more so at a grazing angle.
    float grazing = pow(1.0 - clamp(dot(N, -r.world), 0.0, 1.0), 5.0);
    float3 fresnel = f0 + (1.0 - f0) * grazing;
    float3 coat = onMark ? fresnel : float3(mix(0.4, 1.0, grazing));
    float lit = mix(1.0, shadow(at + n * 0.01 * c.radius, toLightHere, c, 2.0 * c.radius), s.surface.z);
    float open = openness(at, n, c);
    float3 result = fresnel * room(R, s.surface.x, s.surface.y) * mix(0.55, 1.0, open)
                  + coat * (window(R, toLight, s.light.w, s.surface.x) * lit
                            + strip(R, s.glint.xyz, s.glint.w, s.surface.x));
    return clamp(result, 0.0, 1.0);
}

// `shape`: radius, half thickness, rim rounding, dome, in points. `mark`: the stroke's first two
// points, x and y as fractions of the radius; `markEnd`: its last point, then its half width and its
// height in points. `light`: the direction to the key light and its strength; `glint`: the
// direction to the glint's strip and its strength. `surface`: roughness,
// studio contrast, the mark's shadow strength. `view`: the turn in radians, one pixel in points, and
// the view's side.
[[ stitchable ]] half4 checkCoin(float2 position, half4 colour, float4 shape, float4 mark, float4 markEnd,
                                 float3 metal, float3 markColour, float4 light, float4 glint, float3 surface, float3 view) {
    Coin c;
    c.radius = shape.x;
    c.rim = shape.y;
    c.edge = min(shape.z, shape.y);
    c.dome = shape.w;
    c.a = mark.xy * c.radius;
    c.b = mark.zw * c.radius;
    c.c = markEnd.xy * c.radius;
    c.weight = markEnd.z;
    c.height = markEnd.w;
    Studio s = { metal, markColour, light, glint, surface };
    float turn = view.x, pixel = view.y;
    float2 p = position - 0.5 * view.z;
    float ct = cos(turn), st = sin(turn);

    // A camera eight radii in front of the face, looking through the face's plane, so the front face
    // at rest fills the disc exactly and a turn foreshortens as a real coin does.
    float top = c.rim + c.dome + c.height;
    float3 eye = float3(0.0, 0.0, c.rim + 8.0 * c.radius);
    float bound = sqrt(c.radius * c.radius + top * top) + pixel;

    // Four rays a pixel, on a rotated grid, since the mark's outline crosses the face inside the
    // coin, where no near miss says how much of a pixel each side covers.
    const float2 offsets[4] = { float2(-0.125, -0.375), float2(0.375, -0.125), float2(0.125, 0.375), float2(-0.375, 0.125) };
    float3 sum = float3(0.0);
    float covered = 0.0;
    for (int k = 0; k < 4; k++) {
        Ray r = rayThrough(p + offsets[k] * pixel, eye, c, ct, st);
        Trace tr = march(r, c, bound);
        // A ray that passes within half a pixel of the coin's outline covers part of its share.
        float alpha = tr.hit ? 1.0 : clamp(1.0 - 2.0 * tr.closest / pixel, 0.0, 1.0);
        if (alpha <= 0.0) continue;
        float3 at = r.o + r.d * tr.t;
        bool onMark;
        scene(at, c, onMark);
        sum += shade(at, onMark, r, c, s, ct, st, pixel) * alpha;
        covered += alpha;
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
