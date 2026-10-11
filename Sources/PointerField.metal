#include <metal_stdlib>
using namespace metal;

// Live ink's pointer field, a ring round the pointer while the chord is held, and the wake that
// follows the pen (docs/live-ink-cursor-2026-10-10.md). Lengths are in the screen's points, y down
// from its top-left corner. `screen` is a live capture of the display without the overlay, the same
// size as the layer, or a blank texture when there is none, and then nothing reads it.

struct FieldUniforms {
    float4 color;        // the person's ink colour, lightened, in the layer's colour space
    float2 size;         // the layer, in points
    float wakeCount;     // how many points of the pen's path are in `trail`
    float wakeStrength;  // 0 to 1: how far the wake moves the picture
    float wakeSize;      // how far a ring spreads before it is gone
    float wakeLife;      // how long a ring lasts, in seconds
    float wakeLeft;      // the box the rings can reach; nothing moves outside it
    float wakeTop;
    float wakeRight;
    float wakeBottom;
    float fieldX;        // the ring round the pointer: its centre
    float fieldY;
    float fieldRadius;   // its radius now; nothing shows at 0
    float fieldBend;     // 0 to 2: how far it moves what is under it
    float fieldSplit;    // 0 to 1: how far red and blue part there
    float fieldGlow;     // 0 to 1: its light
    float fieldVX;       // how fast it moves, in points a second
    float fieldVY;
    float fieldStretch;  // 0 to 1: how far it stretches along the way it moves
    float fieldPress;    // 0 to 1: brighter while it is smaller than its size
};

struct Varyings {
    float4 position [[position]];
    float2 uv;
};

vertex Varyings fieldVertex(uint id [[vertex_id]]) {
    // One triangle that covers the layer.
    float2 corners[3] = { float2(-1, -1), float2(3, -1), float2(-1, 3) };
    Varyings out;
    out.position = float4(corners[id], 0, 1);
    out.uv = float2((corners[id].x + 1) * 0.5, 1 - (corners[id].y + 1) * 0.5);
    return out;
}

static float3 sampleScreen(texture2d<float> screen, float2 p, float2 size) {
    constexpr sampler linear(filter::linear, address::clamp_to_edge);
    return screen.sample(linear, p / size).rgb;
}


static float4 premultiplied(float3 color, float alpha) { return float4(min(color, 1.0) * alpha, alpha); }

// The wake: a ring spreads from each point the pen passed. A ring is a short packet of waves that
// moves the picture out and back as it passes, and it fades as it spreads. `trail` holds each
// point's place in xy, its age in seconds in z, and in w its weight, less where points crowd.
static float2 wakeShift(float2 p, constant FieldUniforms &u, constant float4 *trail) {
    int count = int(u.wakeCount + 0.5);
    if (count == 0 || u.wakeStrength <= 0.0) return float2(0);
    if (p.x < u.wakeLeft || p.x > u.wakeRight || p.y < u.wakeTop || p.y > u.wakeBottom) return float2(0);
    float life = max(u.wakeLife, 0.01);
    float speed = u.wakeSize / life;
    float2 shift = float2(0);
    for (int i = 0; i < count; i++) {
        float4 point = trail[i];
        float2 away = p - point.xy;
        float far = length(away);
        float g = far - point.z * speed;
        if (abs(g) > 24.0) continue;
        float age = point.z / life;
        float fade = smoothstep(0.0, 0.08, age) * (1.0 - age) * (1.0 - age);
        float packet = sin(g * 0.45) * exp(-g * g / 110.0);
        // A ring moves nothing near its centre. The direction away from the centre flips across it,
        // and a newborn ring there pinched lines into droplets.
        shift += away / max(far, 1.0) * packet * fade * point.w * smoothstep(0.0, 8.0, far);
    }
    return shift * u.wakeStrength * 4.0;
}

// The ring round the pointer: a soft ridge of glass on a circle `fieldRadius` out, with ink-coloured
// light on and round it. Inside the ridge nothing moves, so what the pointer is on stays put. A point
// on the ridge's slopes shows what lies k (R - r) h(r) further towards its crest, h the ridge's height,
// so the crest is magnified; the slope of that map is 1 + k h (2x^2 - 1), which stays positive for k
// under 1, so nothing folds back. Moving, it stretches along the way it goes and narrows across it,
// keeping its area. Premultiplied, and clear wherever it shows nothing.
static float4 pointerField(float2 p, texture2d<float> screen, constant FieldUniforms &u) {
    float big = u.fieldRadius;
    if (big < 0.5) return float4(0);
    float2 c = float2(u.fieldX, u.fieldY);
    float2 v = float2(u.fieldVX, u.fieldVY);
    float speed = length(v);
    float s = 1.0 + u.fieldStretch * min(speed / 1200.0, 1.5);
    float2 q = p - c;
    if (length(q) > (big * 1.8 + 24.0) * s) return float4(0);
    if (speed > 1.0) {
        float2 dir = v / speed;
        float along = dot(q, dir);
        q = (q - along * dir) * sqrt(s) + dir * along / s;
    }
    float r = length(q);
    float w = 0.3 * big;
    float x = (r - big) / w;
    float h = exp(-x * x);
    float2 n = r > 0.001 ? normalize(p - c) : float2(0.0, 1.0);

    float4 out = float4(0);
    if (u.fieldBend > 0.0 || u.fieldSplit > 0.0) {
        float reach = 0.5 * min(u.fieldBend, 2.0) * (big - r) * h;
        float apart = u.fieldSplit * h * w * 0.25;
        float3 color;
        color.r = sampleScreen(screen, p + n * (reach + apart), u.size).r;
        color.g = sampleScreen(screen, p + n * reach, u.size).g;
        color.b = sampleScreen(screen, p + n * (reach - apart), u.size).b;
        // Fades in with how far the picture moved, so it meets the screen without a seam.
        out = premultiplied(color, clamp(max(abs(reach), apart) * 4.0, 0.0, 1.0));
    }
    float glow = u.fieldGlow * (1.0 + 0.6 * u.fieldPress);
    float halo = clamp(glow * (0.55 * h + 0.25 * exp(-pow((r - big) / (2.5 * w), 2.0))), 0.0, 1.0);
    float3 light = mix(u.color.rgb, float3(1.0), 0.25);
    out = float4(light * halo, halo) + out * (1.0 - halo);
    // Light from the top left catching the crest where it faces it.
    float facing = max(dot(-n, normalize(float2(-0.6, -0.8))), 0.0);
    float shine = clamp(glow * 0.8 * facing * facing * smoothstep(0.3, 1.0, h), 0.0, 1.0);
    return float4(float3(shine), shine) + out * (1.0 - shine);
}

fragment float4 fieldFragment(Varyings in [[stage_in]],
                             texture2d<float> screen [[texture(0)]],
                             constant FieldUniforms &u [[buffer(0)]],
                             constant float4 *trail [[buffer(1)]]) {
    float2 p = in.uv * u.size;
    float4 field = pointerField(p, screen, u);
    float2 shift = wakeShift(p, u, trail);
    float moved = length(shift);
    if (moved < 0.01) return field;
    // The wake shows the picture moved, and fades in with how far it moved, so the layer is clear
    // wherever nothing moved and meets the screen without a seam.
    float4 wake = premultiplied(sampleScreen(screen, p - shift, u.size), clamp(moved * 4.0, 0.0, 1.0));
    return field + wake * (1.0 - field.a);
}
