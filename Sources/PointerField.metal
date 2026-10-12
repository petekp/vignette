#include <metal_stdlib>
using namespace metal;

// Live ink's pointer field: the ring round the pointer while the chord is held, and the wake that
// follows the pen, each drawn into its own layer, in one of several styles
// (docs/live-ink-pointer-variants-2026-10-10.md). Lengths are in the screen's points, y down from
// its top-left corner. `screen` is a live capture of the display without the overlay, the same size
// as the screen, or a blank texture when there is none (`hasPicture` 0), and then nothing reads it.
// Every output is premultiplied and clear wherever it shows nothing, so it meets the screen without
// a seam.

struct FieldUniforms {
    float4 color;          // the person's ink colour, lightened, in the layer's colour space
    float4 wakeBox;        // left, top, right, bottom: the box the wake can reach; nothing moves outside it
    float4 ringGlass;      // zoom, clear, shine, shade
    float4 ringShape;      // squareness, break, spread, depth
    float4 wakeLook;       // swell, split, light (strength included), mist
    float2 size;           // the screen, in points
    float2 origin;         // the top-left corner of the layer being drawn, on the screen
    float2 area;           // that layer's size
    float2 ringCentre;
    float2 ringVelocity;   // in points a second
    float2 ringHotspot;    // the arrow's tip, which Lens magnifies about
    uint wakeCount;        // how many points are in the wake's buffers
    uint ringStyle;        // 0 Glass, 1 Lens, 2 Squircle, 3 Droplet, 4 Lamp, 5 Caustic
    uint wakeStyle;        // 0 Ribbon, 1 Silk, 2 Mist, 3 Frost, 4 Ripples
    uint hasPicture;       // 1 when `screen` is the display
    float wakeStrength;    // Ripples: 0 to 1, how far it moves the picture
    float wakeSize;        // Ripples: how far a ring spreads before it is gone
    float wakeLife;        // Ripples: how long a ring lasts, in seconds
    float wakeLift;        // the most the other wakes move the picture, in points, strength included
    float wakeMaskRadius;  // the wake leaves the screen still within this of the ring; 0 when there is none
    float wakeBlur;        // Frost: the most it blurs, in points, strength included
    float ringRadius;      // its radius now; nothing shows at 0
    float ringBend;        // 0 to 1.8: how far the glass moves what is under it
    float ringSplit;       // 0 to 2: how far red and blue part there
    float ringGlow;        // 0 to 1: its light
    float ringStretch;     // 0 to 1: how far it stretches along the way it moves
    float ringPress;       // 0 to 1: brighter while it is smaller than its size
    float ringReach;       // nothing is drawn further than this from the ring's centre
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

// Toward the light, top left, y down. Every style lights from here.
constant float2 lightDir = float2(-0.6, -0.8);

static float3 sampleScreen(texture2d<float> screen, float2 p, float2 size) {
    constexpr sampler linear(filter::linear, address::clamp_to_edge);
    return screen.sample(linear, p / size).rgb;
}

static float4 premultiplied(float3 color, float alpha) { return float4(color * alpha, alpha); }

static float4 over(float4 top, float4 bottom) { return top + bottom * (1.0 - top.a); }

/// A value from 0 to 1 that depends on the pixel alone, never on time, so grain and dither stay still.
static float hash(float2 p) { return fract(sin(dot(p, float2(12.9898, 78.233))) * 43758.5453); }

/// Interleaved gradient noise: a turn per pixel that spreads blur taps evenly.
static float ign(float2 p) { return fract(52.9829189 * fract(dot(p, float2(0.06711056, 0.00583715)))); }

/// Smooth value noise from 0 to 1, with a quintic fade so its clumps have no creases.
static float valueNoise(float2 p) {
    float2 i = floor(p), f = fract(p);
    float2 u = f * f * f * (f * (f * 6.0 - 15.0) + 10.0);
    float a = hash(i), b = hash(i + float2(1, 0)), c = hash(i + float2(0, 1)), d = hash(i + float2(1, 1));
    return mix(mix(a, b, u.x), mix(c, d, u.x), u.y);
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

/// The Droplet's tail behind its head: 0 at rest, growing with speed and the stretch.
/// `PointerField.ringReach` sizes the ring's layer for its longest.
static float dropletTail(constant FieldUniforms &u) {
    float speed = length(u.ringVelocity);
    return 2.4 * u.ringRadius * u.ringStretch * clamp(speed / 700.0, 0.0, 1.0) * smoothstep(30.0, 160.0, speed);
}

// MARK: The ring

// A soft ridge of glass on an outline `d` from it, with ink-coloured light on and round it, shared by
// Glass, Squircle and Droplet. A point on the ridge's slopes shows what lies k d h(d) further towards
// its crest, h the ridge's height, so the crest is magnified; the slope of that map is
// 1 + k h (2x^2 - 1), which stays positive for k under 1, so nothing folds. k is half the bend, capped
// at 0.9. `mask` fades the ridge along the outline, `inner` takes the bend out of a region, and
// `lightBias` brightens or dims the light there.
static float4 ridgeShade(float2 p, float d, float2 n, float w, float mask, float inner, float lightBias,
                         texture2d<float> screen, constant FieldUniforms &u) {
    float x = d / w;
    float h = exp(-x * x) * mask;
    float4 out = float4(0);
    if (u.hasPicture != 0 && (u.ringBend > 0.0 || u.ringSplit > 0.0)) {
        float k = min(0.5 * u.ringBend, 0.9);
        float reach = -k * d * h * inner;
        float apart = u.ringSplit * h * w * 0.25 * inner;
        float3 color;
        color.r = sampleScreen(screen, p + n * (reach + apart), u.size).r;
        color.g = sampleScreen(screen, p + n * reach, u.size).g;
        color.b = sampleScreen(screen, p + n * (reach - apart), u.size).b;
        // Fades in with how far the picture moved, so it meets the screen without a seam.
        out = premultiplied(color, clamp(max(abs(reach), apart) * 4.0, 0.0, 1.0));
    }
    float glow = u.ringGlow * (1.0 + 0.6 * u.ringPress);
    float halo = clamp(glow * (0.55 * h + 0.25 * mask * exp(-pow(d / (2.5 * w), 2.0))) * lightBias, 0.0, 1.0);
    float3 light = mix(u.color.rgb, float3(1.0), 0.25);
    out = float4(light * halo, halo) + out * (1.0 - halo);
    // Light from the top left catching the crest where it faces it.
    float facing = max(dot(-n, lightDir), 0.0);
    float shine = clamp(glow * 0.8 * facing * facing * smoothstep(0.3, 1.0, h) * lightBias, 0.0, 1.0);
    return float4(float3(shine), shine) + out * (1.0 - shine);
}

// Glass: the ridge on a circle. Inside it nothing moves, so what the pointer is on stays put. Moving,
// it stretches along the way it goes and narrows across it, keeping its area.
static float4 glassRing(float2 p, texture2d<float> screen, constant FieldUniforms &u) {
    float R = u.ringRadius;
    float2 pc = p - u.ringCentre;
    float r = length(stretched(pc, u.ringVelocity, stretchOf(u, 1.5)));
    float2 n = length(pc) > 0.001 ? normalize(pc) : float2(0.0, 1.0);
    return ridgeShade(p, r - R, n, 0.3 * R, 1.0, 1.0, 1.0, screen, u);
}

// Lens: a clear bead. Its middle is untouched; toward the rim the picture is drawn in from outside,
// as at the edge of a thick lens, with a thin colour fringe. A Fresnel rim, a highlight at the top
// left, a lit crescent inside the bottom right and a soft contact shadow let it read on any page.
// Zoom magnifies the middle about the arrow's tip, which stays put. With no picture it is an empty
// glass bead.
static float4 lens(float2 p, texture2d<float> screen, constant FieldUniforms &u) {
    float R = u.ringRadius;
    float2 c = u.ringCentre;
    float2 pc = p - c;
    float s = stretchOf(u, 1.5);
    float r = length(stretched(pc, u.ringVelocity, s));
    float t = r / R;
    float2 n = length(pc) > 0.001 ? normalize(pc) : float2(0.0, 1.0);
    float3 ink = u.color.rgb;
    float zoom = u.ringGlass.x, clear = u.ringGlass.y, shine = u.ringGlass.z, shade = u.ringGlass.w;
    float4 out = float4(0);
    if (u.hasPicture != 0) {
        float c0 = 0.15 + 0.6 * clear;
        // Narrow enough that the pull outside the rim is gone well before the layer's edge.
        float sigma = 0.35 * R;
        // Divided by the stretch, so a stretched rim never folds.
        float D = min(0.3 * R * u.ringBend, 0.8 * sigma / s);
        float dE = r <= R ? D * pow(smoothstep(c0, 1.0, t), 2.0) : D * exp(-pow((r - R) / sigma, 2.0));
        float a = 1.0 - 1.0 / max(zoom, 1.0);
        float sz = 1.0 - smoothstep(0.5, 1.0, t);
        float2 h = u.ringHotspot;
        float sp = min(u.ringSplit, 1.0);
        float3 color;
        float2 green = p;
        for (int k = 0; k < 3; k++) {
            float kappa = 1.0 - float(k);
            float ak = a * (1.0 + 0.15 * sp * kappa);
            float2 tap = h + (p - h) * (1.0 - ak * sz) + n * dE * (1.0 + 0.06 * sp * kappa);
            color[k] = sampleScreen(screen, tap, u.size)[k];
            if (k == 1) green = tap;
        }
        out = premultiplied(color, clamp(length(green - p) * 4.0, 0.0, 1.0));
    }
    float nz = sqrt(max(1.0 - t * t, 0.0));
    float3 N = float3(n * t, nz);
    float3 L3 = normalize(float3(lightDir * 0.8, 0.6));
    float3 H = normalize(L3 + float3(0, 0, 1));
    float glow = u.ringGlow * (1.0 + 0.6 * u.ringPress);
    float sd = length(p - (c - lightDir * 0.12 * R));
    float shadow = shade * 0.22 * (1.0 - smoothstep(0.95 * R, 1.35 * R, sd)) * smoothstep(R, R + 1.0, r);
    float halo = glow * 0.25 * exp(-pow((r - R) / (0.45 * R), 2.0)) * smoothstep(R - 1.0, R, r);
    float opposite = max(dot(n, -lightDir), 0.0);
    float crescent = shade * 0.45 * opposite * opposite * smoothstep(0.6, 0.95, t) * (1.0 - smoothstep(0.95, 1.0, t));
    float fresnel = shine * (0.04 + 0.96 * pow(1.0 - nz, 5.0)) * (1.0 - smoothstep(R, R + 0.9, r));
    float specular = shine * 0.8 * pow(max(dot(N, H), 0.0), 60.0) * (1.0 - smoothstep(R - 0.5, R, r));
    out = over(premultiplied(ink * 0.15, clamp(shadow, 0.0, 1.0)), out);
    out = over(premultiplied(mix(ink, float3(1), 0.25), clamp(halo, 0.0, 1.0)), out);
    out = over(premultiplied(mix(ink, float3(1), 0.2), clamp(crescent, 0.0, 1.0)), out);
    out = over(premultiplied(mix(ink, float3(1), 0.55), clamp(fresnel, 0.0, 1.0)), out);
    return over(premultiplied(float3(1), clamp(specular, 0.0, 1.0)), out);
}

// Squircle: the ridge on a rounded square with continuous corners, the shape of an app icon. Break
// fades the middle of each side, leaving four corner brackets. At squareness 2 and no break it is
// the Glass ring.
static float4 squircle(float2 p, texture2d<float> screen, constant FieldUniforms &u) {
    float R = u.ringRadius;
    float s = stretchOf(u, 1.5);
    float2 q = stretched(p - u.ringCentre, u.ringVelocity, s);
    float N = clamp(u.ringShape.x, 2.0, 8.0);
    float ax = max(abs(q.x) / R, 1e-4), ay = max(abs(q.y) / R, 1e-4);
    float f = pow(pow(ax, N) + pow(ay, N), 1.0 / N);
    float2 g = float2(pow(ax, N - 1.0), pow(ay, N - 1.0)) / pow(max(f, 1e-3), N - 1.0);
    // The superellipse's value over its gradient: a distance near the outline, which is all the ridge reads.
    float d = (f - 1.0) * R / max(length(g), 0.5);
    float2 nq = float2(q.x >= 0.0 ? 1.0 : -1.0, q.y >= 0.0 ? 1.0 : -1.0) * normalize(g);
    float2 n = normalize(stretched(nq, u.ringVelocity, s));
    float corner = min(ax, ay) / max(max(ax, ay), 1e-4);
    float mask = mix(1.0, smoothstep(0.12, 0.62, corner), clamp(u.ringShape.y, 0.0, 1.0));
    return ridgeShade(p, d, n, 0.3 * R, mask, 1.0, 1.0, screen, u);
}

// Droplet: at rest the Glass ring; moving, it pulls into a teardrop with a round head leading and a
// soft tail behind, which draws back as the pointer slows. The head holds more light than the tail.
static float4 droplet(float2 p, texture2d<float> screen, constant FieldUniforms &u) {
    float R = u.ringRadius;
    float2 pc = p - u.ringCentre;
    float speed = length(u.ringVelocity);
    float2 dir = speed > 1.0 ? u.ringVelocity / speed : float2(1, 0);
    float tail = dropletTail(u);
    float Rh = R / sqrt(1.0 + 0.15 * tail / R);
    float w = 0.3 * R;
    // A tip under 1.2 ridge widths would put the tail's middle line in the bend, which tears there.
    float r2 = min(1.2 * w, Rh);
    float hh = (Rh - r2) + tail + 1e-3;
    float2 ey = -dir, ex = float2(-dir.y, dir.x);
    float2 sp = float2(dot(pc, ex), dot(pc, ey));
    float2 ps = float2(abs(sp.x), sp.y);
    // The exact distance to a capsule with ends of two radii (Inigo Quilez's uneven capsule), so the
    // ridge is even all round.
    float b = (Rh - r2) / hh, a = sqrt(1.0 - b * b);
    float k = dot(ps, float2(-b, a));
    float d;
    float2 nl;
    if (k < 0.0) {
        d = length(ps) - Rh;
        nl = ps / max(length(ps), 1e-4);
    } else if (k > a * hh) {
        float2 e = ps - float2(0, hh);
        d = length(e) - r2;
        nl = e / max(length(e), 1e-4);
    } else {
        d = dot(ps, float2(a, b)) - Rh;
        nl = float2(a, b);
    }
    nl.x *= sp.x >= 0.0 ? 1.0 : -1.0;
    float2 n = ex * nl.x + ey * nl.y;
    float grown = smoothstep(0.0, 0.3 * Rh, tail);
    float lead = 0.5 + 0.5 * dot(n, dir);
    float lightBias = clamp(1.0 + (lead - 0.5) * grown, 0.7, 1.3);
    // The bend's direction flips across the tail's middle line, so the bend is taken out inside it.
    float inner = mix(1.0, smoothstep(-1.2 * w, -0.4 * w, d), grown);
    return ridgeShade(p, d, n, w, 1.0, inner, lightBias, screen, u);
}

// Lamp: no edge, only a soft pool of ink-coloured light round the arrow, clear in the middle. It
// never reads the screen. It is a tint: light added to what is behind a window does not reach the
// screen, since the window server keeps no colour where a window's pixel has no coverage.
static float4 lamp(float2 p, float2 pixel, constant FieldUniforms &u) {
    float R = u.ringRadius;
    float2 pc = p - u.ringCentre;
    float r = length(stretched(pc, u.ringVelocity, stretchOf(u, 0.5)));
    float S = u.ringShape.z * R * (1.0 - 0.25 * u.ringPress);
    float x = r / S;
    float fall = mix(exp(-x * x), exp(-1.5 * x), 0.35);
    float hollow = 1.0 - u.ringGlass.y * exp(-pow(length(pc) / (0.45 * R), 2.0));
    // Gone before the layer's edge, so there is no seam.
    float cut = 1.0 - smoothstep(0.75, 1.0, length(pc) / u.ringReach);
    float A = clamp(u.ringGlow * (1.0 + 0.6 * u.ringPress) * fall * hollow * cut, 0.0, 1.0);
    // Dither against 8-bit banding in so soft a gradient, only where there is light.
    float3 rgb = mix(u.color.rgb, float3(1), 0.25) * A + (hash(pixel) - 0.5) / 255.0 * min(A * 64.0, 1.0);
    return float4(max(rgb, 0.0), A);
}

// Caustic: mostly light. A faint glass edge circles the arrow, and on the side away from the light a
// bright crescent hugs the inside of the rim and gathers to a cusp, as light through a glass lands on
// a table, fringed red and blue by Split. A faint dark crescent inside the lit side lets it read on
// white. With a picture, what lies under the crescent bends by a point or two.
static float4 caustic(float2 p, texture2d<float> screen, constant FieldUniforms &u) {
    float R = u.ringRadius;
    float2 pc = p - u.ringCentre;
    float2 q = stretched(pc, u.ringVelocity, stretchOf(u, 1.5));
    float r = length(q);
    float2 n = length(pc) > 0.001 ? normalize(pc) : float2(0.0, 1.0);
    float2 away = -lightDir;
    float w = max(2.0, 0.1 * R);
    float off = u.ringShape.w * R;
    float glow = u.ringGlow * (1.0 + 0.6 * u.ringPress);
    float cusp = pow(max(dot(n, away), 0.0), 2.8);
    float3 I;
    float crescentG = 0.0;
    for (int k = 0; k < 3; k++) {
        float Rk = R * (1.0 + 0.05 * u.ringSplit * (1.0 - float(k)));
        float dB = length(q - lightDir * off) - (Rk - 0.5 * off);
        float inside = 1.0 - smoothstep(-w, w, r - Rk);
        float crescent = inside * smoothstep(-w, w, dB);
        float line = exp(-pow(dB / (0.6 * w), 2.0)) * inside;
        I[k] = clamp(glow * (0.35 * crescent * (0.35 + 0.65 * cusp) + 0.65 * line * cusp), 0.0, 1.0);
        if (k == 1) crescentG = crescent;
    }
    float3 ink = u.color.rgb;
    float4 out = float4(0);
    if (u.hasPicture != 0 && u.ringBend > 0.0) {
        float2 shift = n * min(u.ringBend, 1.0) * 2.0 * crescentG * (0.4 + 0.6 * cusp);
        out = premultiplied(sampleScreen(screen, p + shift, u.size), clamp(length(shift) * 4.0, 0.0, 1.0));
    }
    float dC = length(q - away * 0.8 * off) - (R - 0.4 * off);
    float dark = u.ringGlass.w * 0.30 * (1.0 - smoothstep(-w, w, r - R)) * smoothstep(-w, w, dC)
        * pow(max(dot(n, lightDir), 0.0), 1.5);
    out = over(premultiplied(ink * 0.2, clamp(dark, 0.0, 1.0)), out);
    float edge = u.ringGlass.z * 0.35 * exp(-pow((r - R) / 0.8, 2.0));
    out = over(premultiplied(mix(ink, float3(1), 0.5), clamp(edge, 0.0, 1.0)), out);
    float3 tint = mix(ink, float3(1), 0.3);
    return over(float4(I * tint, max(I.r, max(I.g, I.b))), out);
}

fragment float4 ringFragment(Varyings in [[stage_in]],
                             texture2d<float> screen [[texture(0)]],
                             constant FieldUniforms &u [[buffer(0)]]) {
    float2 p = u.origin + in.uv * u.area;
    if (u.ringRadius < 0.5 || length(p - u.ringCentre) > u.ringReach) return float4(0);
    switch (u.ringStyle) {
        case 1: return lens(p, screen, u);
        case 2: return squircle(p, screen, u);
        case 3: return droplet(p, screen, u);
        case 4: return lamp(p, in.position.xy, u);
        case 5: return caustic(p, screen, u);
        default: return glassRing(p, screen, u);
    }
}

// MARK: The wake

// How far `p` is from the ring, in the ring's own shape: stretched with it, or along the Droplet's
// tail. The wake leaves the screen still within `wakeMaskRadius` of it, because the ring's layer,
// drawn over the wake, samples the screen as it is, and the two would show the same content twice.
static float ringSpan(float2 p, constant FieldUniforms &u) {
    float2 pc = p - u.ringCentre;
    if (u.ringStyle == 3) {
        float speed = length(u.ringVelocity);
        float2 dir = speed > 1.0 ? u.ringVelocity / speed : float2(1, 0);
        float along = clamp(dot(pc, -dir), 0.0, dropletTail(u));
        return length(pc + dir * along);
    }
    return length(stretched(pc, u.ringVelocity, stretchOf(u, u.ringStyle == 4 ? 0.5 : 1.5)));
}

/// `v` softly limited to `cap` points, so overlapping strokes never stack past it.
static float2 limited(float2 v, float cap) {
    float m = length(v);
    if (m < 1e-5 || cap <= 0.0) return float2(0);
    return v * cap * tanh(m / cap) / m;
}

// Ripples: a ring spreads from each point the pen passed, a short packet of waves that moves the
// picture out and back as it passes. `trail` holds each point's place in xy, its age in seconds in
// z, and in w its weight, less where points crowd.
static float2 ripples(float2 p, constant FieldUniforms &u, constant float4 *trail) {
    float life = max(u.wakeLife, 0.01);
    float speed = u.wakeSize / life;
    float2 shift = float2(0);
    for (uint i = 0; i < u.wakeCount; i++) {
        float4 point = trail[i];
        float2 away = p - point.xy;
        // Only a pixel within 24 pt of a ring's edge moves, so the rest are passed over before the square root.
        float spread = point.z * speed;
        float near = max(spread - 24.0, 0.0);
        float d2 = dot(away, away);
        if (d2 > (spread + 24.0) * (spread + 24.0) || d2 < near * near) continue;
        float far = sqrt(d2);
        float g = far - spread;
        float age = point.z / life;
        float fade = smoothstep(0.0, 0.08, age) * (1.0 - age) * (1.0 - age);
        float packet = sin(g * 0.45) * exp(-g * g / 110.0);
        // A ring moves nothing near its centre. The direction away from the centre flips across it,
        // and a newborn ring there pinched lines into droplets.
        shift += away / max(far, 1.0) * packet * fade * point.w * smoothstep(0.0, 8.0, far);
    }
    return shift * u.wakeStrength * 4.0;
}

// The other wakes share one smooth field. Each point of the pen's path is a bump (1 - q)^3, q its
// distance over its radius, squared, which is exactly 0 at the radius, so the loop needs no exp or
// root. A point widens as the square root of its age and flattens as it widens, as a drop of honey
// spreads, so the field has one sign and never oscillates. `kernels` holds each point's place, 1 over
// its radius, and its height; `motion` holds the pen's direction there scaled by its speed, and the
// point's age as a fraction of its life.
static float4 smoothWake(float2 p, float2 pixel, texture2d<float> screen, constant FieldUniforms &u,
                         constant float4 *kernels, constant float4 *motion) {
    float f = 0.0, fa = 0.0;
    float2 g = float2(0), drag = float2(0);
    for (uint i = 0; i < u.wakeCount; i++) {
        float4 A = kernels[i];
        float2 d = p - A.xy;
        float q = dot(d, d) * A.z * A.z;
        if (q >= 1.0) continue;
        float s = 1.0 - q;
        float k = A.w * s * s * s;
        f += k;
        // The radius times the field's gradient, pointing uphill, toward the stroke.
        g -= A.w * 6.0 * A.z * s * s * d;
        drag += k * motion[i].xy;
        fa += k * motion[i].z;
    }
    if (f < 1e-4) return float4(0);
    // exp(-f) keeps overlapping strokes from stacking; 1.1887 is the peak across one dense line.
    float2 G = g * exp(-f) / 1.1887;
    float slope = min(length(G), 1.0);
    float mask = u.wakeMaskRadius > 0.0 ? smoothstep(u.wakeMaskRadius, u.wakeMaskRadius + 24.0, ringSpan(p, u)) : 1.0;
    float L = u.wakeLift;
    float swell = u.wakeLook.x, split = u.wakeLook.y, light = u.wakeLook.z, mist = u.wakeLook.w;
    float3 ink = u.color.rgb;
    float haze = light * 0.25 * (1.0 - exp(-f)) * mask;
    switch (u.wakeStyle) {
        case 1: {
            // Silk: the surface leans the way the pen went, a shear rather than a magnification.
            if (u.hasPicture == 0) return float4(0);
            float m = length(drag);
            float2 sh = m > 1e-5 ? L * drag * (1.0 - exp(-1.5 * m)) / (m * 0.7769) : L * drag * 1.931;
            sh *= mask;
            return premultiplied(sampleScreen(screen, p - sh, u.size), clamp(length(sh) * 4.0, 0.0, 1.0));
        }
        case 2: {
            // Mist: a plume of ink-coloured light in slow clumps that rise a little as it ages, over a
            // very slight swell.
            float age = fa / max(f, 1e-4);
            float noise = valueNoise((p + float2(0.0, 12.0 * age)) / 70.0);
            float density = 0.65 + 0.35 * mist * (2.0 * noise - 1.0);
            float Lm = (1.0 - exp(-light * 1.6 * f * density)) * mask;
            float3 col = mix(mix(ink, float3(1), 0.25), float3(1), 0.35 * Lm);
            float3 rgb = col * Lm + (hash(pixel) - 0.5) / 255.0 * min(Lm * 64.0, 1.0);
            float4 glow = float4(max(rgb, 0.0), Lm);
            float4 pic = float4(0);
            float2 sh = limited(0.35 * L * swell * G, 1.2 * 0.35 * L) * mask;
            if (u.hasPicture != 0) {
                pic = premultiplied(sampleScreen(screen, p + sh, u.size), clamp(length(sh) * 4.0, 0.0, 1.0));
            }
            return over(glow, pic);
        }
        case 3: {
            // Frost: the band goes soft behind the pen, with a faint milky lift, and clears from its edges.
            float frost = 1.0 - exp(-1.5 * f);
            float radius = u.wakeBlur * frost * mix(1.0, slope, 0.6) * mask;
            float2 sh = limited(0.35 * L * swell * G, 1.2 * 0.35 * L) * mask;
            float4 pic = float4(0);
            if (u.hasPicture != 0) {
                float3 col;
                if (radius < 0.4) {
                    col = sampleScreen(screen, p + sh, u.size);
                } else {
                    // 24 taps on a Vogel spiral, turned per pixel so the pattern becomes fine grain.
                    float turn = 6.2831853 * ign(pixel);
                    float2x2 rotate = float2x2(cos(turn), sin(turn), -sin(turn), cos(turn));
                    col = float3(0);
                    for (int j = 0; j < 24; j++) {
                        float a = float(j) * 2.39996;
                        float2 vogel = sqrt((float(j) + 0.5) / 24.0) * float2(cos(a), sin(a));
                        col += sampleScreen(screen, p + sh + radius * (rotate * vogel), u.size);
                    }
                    col /= 24.0;
                }
                col = mix(col, float3(1), 0.12 * light * frost * mask);
                pic = premultiplied(col, clamp(max(length(sh), radius) * 4.0, 0.0, 1.0));
            }
            return over(premultiplied(mix(ink, float3(1), 0.5), clamp(haze, 0.0, 1.0)), pic);
        }
        default: {
            // Ribbon: a beat behind the pen, content near the stroke spreads outward, one smooth bump
            // that grows wider and flatter as it ages. Below 0, Swell pulls it in.
            float2 sh = limited(L * swell * G, 1.2 * L) * mask;
            float4 pic = float4(0);
            if (u.hasPicture != 0) {
                float3 col;
                if (split > 0.0) {
                    col.r = sampleScreen(screen, p + sh * (1.0 + 0.25 * split), u.size).r;
                    col.g = sampleScreen(screen, p + sh, u.size).g;
                    col.b = sampleScreen(screen, p + sh * (1.0 - 0.25 * split), u.size).b;
                } else {
                    col = sampleScreen(screen, p + sh, u.size);
                }
                pic = premultiplied(col, clamp(length(sh) * 4.0, 0.0, 1.0));
            }
            float2 uphill = normalize(G + 1e-6);
            float sheen = clamp(light * 0.5 * pow(max(dot(-uphill, lightDir), 0.0), 2.0) * slope * mask, 0.0, 1.0);
            float4 out = over(premultiplied(mix(ink, float3(1), 0.5), clamp(haze, 0.0, 1.0)), pic);
            return over(premultiplied(float3(1), sheen), out);
        }
    }
}

fragment float4 wakeFragment(Varyings in [[stage_in]],
                             texture2d<float> screen [[texture(0)]],
                             constant FieldUniforms &u [[buffer(0)]],
                             constant float4 *first [[buffer(1)]],
                             constant float4 *second [[buffer(2)]]) {
    float2 p = u.origin + in.uv * u.area;
    if (u.wakeCount == 0 || p.x < u.wakeBox.x || p.x > u.wakeBox.z || p.y < u.wakeBox.y || p.y > u.wakeBox.w) {
        return float4(0);
    }
    if (u.wakeStyle != 4) return smoothWake(p, in.position.xy, screen, u, first, second);
    if (u.hasPicture == 0) return float4(0);
    // Ripples show the picture moved, and fade in with how far it moved, so the layer is clear
    // wherever nothing moved and meets the screen without a seam.
    float2 shift = ripples(p, u, first);
    float moved = length(shift);
    if (moved < 0.01) return float4(0);
    return premultiplied(sampleScreen(screen, p - shift, u.size), clamp(moved * 4.0, 0.0, 1.0));
}
