#include <metal_stdlib>
using namespace metal;

// Live ink's pointer field: the lamp, a soft pool of the ink's colour round the pointer while the
// chord is held. Lengths are in the screen's points, y down from its top-left corner. Every output is
// premultiplied and clear wherever it shows nothing, so it meets the screen without a seam.

struct FieldUniforms {
    float4 color;          // the person's ink colour, lightened, in the layer's colour space
    float2 origin;         // the top-left corner of the layer being drawn, on the screen
    float2 area;           // that layer's size
    float2 ringCentre;
    float2 ringVelocity;   // in points a second
    float ringRadius;      // its radius now; nothing shows at 0
    float ringGlow;        // 0 to 1: its light
    float ringStretch;     // 0 to 1: how far it stretches along the way it moves
    float ringPress;       // 0 to 1: brighter while it is smaller than its size
    float ringReach;       // nothing is drawn further than this from the ring's centre
    float ringClear;       // 0 to 1: how much of the middle is left alone
    float ringSpread;      // how far its light reaches, in ring sizes
    float time;            // seconds, for the lamp's breath and drift
    float ringEnergy;      // 0 to 1: how fast the pointer has moved lately
    float4 lampLife;       // breath depth, breath length in seconds, energy gain, drift
};

struct Varyings {
    float4 position [[position]];
    float2 uv;
};

vertex Varyings fieldVertex(uint id [[vertex_id]]) {
    // One triangle that covers the layer. `uv` runs from its top-left corner, y down.
    float2 corners[3] = { float2(-1, -1), float2(3, -1), float2(-1, 3) };
    Varyings out;
    out.position = float4(corners[id], 0, 1);
    out.uv = float2((corners[id].x + 1) * 0.5, 1 - (corners[id].y + 1) * 0.5);
    return out;
}

/// A value from 0 to 1 that depends on the pixel alone, never on time, so grain and dither stay still.
static float hash(float2 p) { return fract(sin(dot(p, float2(12.9898, 78.233))) * 43758.5453); }

/// Smooth value noise from 0 to 1, with a quintic fade so its clumps have no creases.
static float valueNoise(float2 p) {
    float2 i = floor(p), f = fract(p);
    float2 w = f * f * f * (f * (f * 6.0 - 15.0) + 10.0);
    float a = hash(i), b = hash(i + float2(1, 0)), c = hash(i + float2(0, 1)), d = hash(i + float2(1, 1));
    return mix(mix(a, b, w.x), mix(c, d, w.x), w.y);
}

/// How far the ring stretches along its motion: 1 at rest, up to 1 + stretch * most when fast.
/// `PointerField.ringReach` sizes the ring's layer with the same numbers.
static float stretchOf(constant FieldUniforms &u, float most) {
    return 1.0 + u.ringStretch * min(length(u.ringVelocity) / 1200.0, most);
}

/// `q` in the ring's stretched space: longer along its motion and narrower across, keeping its area.
/// The map is symmetric, so it carries a normal the same way it carries a point.
static float2 stretched(float2 q, float2 v, float s) {
    float speed = length(v);
    if (speed <= 1.0) return q;
    float2 dir = v / speed;
    float along = dot(q, dir);
    return (q - along * dir) * sqrt(s) + dir * along / s;
}

// Lamp: no edge, only a soft pool of light in the ink's colour round the arrow, clear in the middle.
// It never reads the screen. It is a tint: light added to what is behind a window does not reach the
// screen, since the window server keeps no colour where a window's pixel has no coverage, so over
// light content it takes the deep blue and darkens what is there. It lives: it breathes, grows
// brighter and wider with the pointer's speed, and light drifts slowly round inside it.
static float4 lamp(float2 p, float2 pixel, constant FieldUniforms &u) {
    float R = u.ringRadius;
    float2 pc = p - u.ringCentre;
    float breath = u.lampLife.x * sin(6.2831853 * u.time / u.lampLife.y);
    float energy = u.lampLife.z * u.ringEnergy;
    float r = length(stretched(pc, u.ringVelocity, stretchOf(u, 0.5)));
    float S = u.ringSpread * R * (1.0 - 0.25 * u.ringPress) * (1.0 + 0.5 * breath + 0.35 * energy);
    float x = r / S;
    float fall = mix(exp(-x * x), exp(-1.5 * x), 0.35);
    // Light drifting round the pool: slow noise over the angle and the distance, turning with time.
    float angle = atan2(pc.y, pc.x);
    float2 around = float2(cos(angle), sin(angle)) * 1.6 + float2(x * 1.2, 0.0);
    float drift = 1.0 + u.lampLife.w * (valueNoise(around + float2(0.11 * u.time, 0.07 * u.time)) - 0.5) * 1.4;
    float hollow = 1.0 - u.ringClear * exp(-pow(length(pc) / (0.45 * R), 2.0));
    // Gone before the layer's edge, so there is no seam.
    float cut = 1.0 - smoothstep(0.75, 1.0, length(pc) / u.ringReach);
    float A = clamp(u.ringGlow * (1.0 + 0.6 * u.ringPress) * (1.0 + breath + 0.6 * energy) * fall * drift * hollow * cut, 0.0, 1.0);
    // Dither against 8-bit banding in so soft a gradient, only where there is light.
    float3 rgb = u.color.rgb * A + (hash(pixel) - 0.5) / 255.0 * min(A * 64.0, 1.0);
    return float4(max(rgb, 0.0), A);
}


fragment float4 ringFragment(Varyings in [[stage_in]],
                             constant FieldUniforms &u [[buffer(0)]]) {
    float2 p = u.origin + in.uv * u.area;
    if (u.ringRadius < 0.5 || length(p - u.ringCentre) > u.ringReach) return float4(0);
    return lamp(p, in.position.xy, u);
}
