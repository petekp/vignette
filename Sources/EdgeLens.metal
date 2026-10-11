#include <metal_stdlib>
using namespace metal;

// Live ink's edge looks, and the wake that follows the pen (docs/live-ink-edge-lab-2026-10-08.md).
// Lengths are in the screen's points, y down from its top-left corner. `screen` is a live capture
// of the display without the overlay, the same size as the layer.

struct EdgeUniforms {
    float4 color;       // the person's ink colour, lightened, in the layer's colour space
    float2 size;        // the layer, in points
    float2 pen;         // the pointer, in points
    float scale;        // pixels per point
    float style;        // EdgeLensLayer.Style's raw value; 0 and 7 draw nothing along the edges
    float width;        // how far the look reaches into the screen
    float bend;         // 0 to 2: how far the look moves what is under it
    float split;        // 0 to 1: how far red and blue part at the bend
    float shine;        // 0 to 1: the light along the rim
    float frost;        // 0 to 1: how much the look blurs what is under it
    float tint;         // 0 to 1: how much of the ink colour the look takes
    float speed;        // animation rate; 0 holds it still
    float focus;        // 0 to 1: how much the look gathers round the pen
    float time;         // seconds
    float light;        // 0 to 1: the coloured light on aurora ripple's waves
    float wakeCount;    // how many points of the pen's path are in `trail`
    float wakeStrength; // 0 to 1: how far the wake moves the picture
    float wakeSize;     // how far a ring spreads before it is gone
    float wakeLife;     // how long a ring lasts, in seconds
    float wakeLeft;     // the box the rings can reach; nothing moves outside it
    float wakeTop;
    float wakeRight;
    float wakeBottom;
    float colors;       // the aurora's colours: 0 the ink's, 1 a rainbow, 2 between color1 and color2
    float repeats;      // how many times the colours repeat round the screen
    float variation;    // 0 to 1: how far the ink colour's hue swings to either side
    float hue;          // 0 to 1: turns every colour round the colour wheel
    float saturation;   // 0 to 2
    float brightness;   // 0 to 3
    float drift;        // how fast the colours flow round, in repeats a second at speed 1
    float blend;        // how aurora ripple's light meets the screen, EdgeLensLayer.Blend's raw value
    float color1R;      // the two colours, in the layer's colour space
    float color1G;
    float color1B;
    float color2R;
    float color2G;
    float color2B;
    float radiusTopLeft;     // the display's corners, square at 0
    float radiusTopRight;
    float radiusBottomRight;
    float radiusBottomLeft;
    float notchLeft;         // the notch, which the band goes round; no notch at height 0
    float notchRight;
    float notchHeight;
    float notchRadius;       // the notch's bottom corners
    float fieldX;            // the ring round the pointer: its centre
    float fieldY;
    float fieldRadius;       // its radius now; nothing shows at 0
    float fieldBend;         // 0 to 2: how far it moves what is under it
    float fieldSplit;        // 0 to 1: how far red and blue part there
    float fieldGlow;         // 0 to 1: its light
    float fieldVX;           // how fast it moves, in points a second
    float fieldVY;
    float fieldStretch;      // 0 to 1: how far it stretches along the way it moves
    float fieldPress;        // 0 to 1: brighter while it is smaller than its size
};

struct Varyings {
    float4 position [[position]];
    float2 uv;
};

vertex Varyings edgeVertex(uint id [[vertex_id]]) {
    // One triangle that covers the layer.
    float2 corners[3] = { float2(-1, -1), float2(3, -1), float2(-1, 3) };
    Varyings out;
    out.position = float4(corners[id], 0, 1);
    out.uv = float2((corners[id].x + 1) * 0.5, 1 - (corners[id].y + 1) * 0.5);
    return out;
}

// Signed distance from `p` to a box round `center`, `half_` from it each way, positive outside.
// `radii` are its corners' radii: top left, top right, bottom right, bottom left, y down.
static float roundedBox(float2 p, float2 center, float2 half_, float4 radii) {
    float2 c = p - center;
    float r = c.x > 0.0 ? (c.y > 0.0 ? radii.z : radii.y) : (c.y > 0.0 ? radii.w : radii.x);
    float2 q = abs(c) - half_ + r;
    return min(max(q.x, q.y), 0.0) + length(max(q, 0.0)) - r;
}

// How far `p` is inside the display's shape: its corners, less the notch. The top edge turns into
// the notch along a curve, from a smooth minimum, rather than at a crease.
static float inside(float2 p, constant EdgeUniforms &u) {
    float4 corners = float4(u.radiusTopLeft, u.radiusTopRight, u.radiusBottomRight, u.radiusBottomLeft);
    float screenIn = -roundedBox(p, u.size * 0.5, u.size * 0.5, corners);
    if (u.notchHeight <= 0.0) return screenIn;
    // The notch's box reaches as far above the screen as below its top, so only its bottom corners show.
    float half_ = (u.notchRight - u.notchLeft) * 0.5;
    float notchOut = roundedBox(p, float2(u.notchLeft + half_, 0.0), float2(half_, u.notchHeight), float4(u.notchRadius));
    float k = 8.0;
    float h = max(k - abs(screenIn - notchOut), 0.0) / k;
    return min(screenIn, notchOut) - h * h * k * 0.25;
}

// The unit normal pointing further inside the shape, from its gradient.
static float2 inward(float2 p, constant EdgeUniforms &u) {
    float2 e = float2(0.5, 0.0);
    float2 g = float2(inside(p + e.xy, u) - inside(p - e.xy, u), inside(p + e.yx, u) - inside(p - e.yx, u));
    return length(g) > 1e-5 ? normalize(g) : float2(0.0, 1.0);
}

static float3 sampleScreen(texture2d<float> screen, float2 p, float2 size) {
    constexpr sampler linear(filter::linear, address::clamp_to_edge);
    return screen.sample(linear, p / size).rgb;
}

// The picture blurred round `p`: a spiral of taps, turned by `turn` (0 to 1), which differs at each
// pixel, so a wide blur reads as frosted grain rather than as copies of the picture.
static float3 blurred(texture2d<float> screen, float2 p, float2 size, float radius, float turn) {
    if (radius < 0.5) return sampleScreen(screen, p, size);
    const int count = 24;
    float3 sum = float3(0);
    for (int i = 0; i < count; i++) {
        float r = radius * sqrt((float(i) + 0.5) / float(count));
        float a = float(i) * 2.39996323 + turn * 2.0 * M_PI_F;
        sum += sampleScreen(screen, p + r * float2(cos(a), sin(a)), size);
    }
    return sum / float(count);
}

// How strongly the look shows at `p`: full at the pen, falling to a floor far from it.
static float gathered(float2 p, constant EdgeUniforms &u) {
    float spread = 0.55 * u.size.y;
    float near = exp(-pow(distance(p, u.pen) / spread, 2.0));
    return mix(1.0, near, u.focus);
}

// Where `p` lies round the screen, 0 to 1, continuous all the way round: a look whose pattern
// repeats a whole number of times round it has no seam.
static float around(float2 p, float2 size) {
    float2 c = p - size * 0.5;
    return atan2(c.y * size.x / size.y, c.x) / (2.0 * M_PI_F) + 0.5;
}

// `c` turned `turns` of the way round the colour wheel, about the grey axis.
static float3 hueTurned(float3 c, float turns) {
    float a = 2.0 * M_PI_F * turns;
    float3 k = float3(0.57735027);
    return c * cos(a) + cross(k, c) * sin(a) + k * dot(k, c) * (1.0 - cos(a));
}

// The aurora's colour at `x` round the screen. A whole number of repeats meets itself where `x`
// wraps, so the colours have no seam.
static float3 auroraColor(float x, float t, constant EdgeUniforms &u) {
    float phase = round(max(u.repeats, 1.0)) * x + u.drift * t;
    float3 c;
    int colors = int(u.colors + 0.5);
    if (colors == 1) {
        c = 0.5 + 0.5 * cos(2.0 * M_PI_F * (phase + float3(0.0, 0.33, 0.67)));
    } else if (colors == 2) {
        c = mix(float3(u.color1R, u.color1G, u.color1B), float3(u.color2R, u.color2G, u.color2B), 0.5 + 0.5 * sin(2.0 * M_PI_F * phase));
    } else {
        c = hueTurned(u.color.rgb, u.variation * 0.25 * sin(2.0 * M_PI_F * phase));
    }
    c = hueTurned(c, u.hue);
    float grey = dot(c, float3(0.2126, 0.7152, 0.0722));
    return max(mix(float3(grey), c, u.saturation), 0.0) * u.brightness;
}

static float luminance(float3 c) { return dot(c, float3(0.3, 0.59, 0.11)); }

// `c` with the luminance `l`, its hue and saturation kept as far as the gamut allows, as CSS's
// colour blend mode defines it.
static float3 withLuminance(float3 c, float l) {
    c += l - luminance(c);
    float lum = luminance(c);
    float low = min(min(c.r, c.g), c.b);
    float high = max(max(c.r, c.g), c.b);
    if (low < 0.0) c = lum + (c - lum) * lum / max(lum - low, 1e-5);
    if (high > 1.0) c = lum + (c - lum) * (1.0 - lum) / max(high - lum, 1e-5);
    return c;
}

// The light `l` blended onto the screen `b`, by EdgeLensLayer.Blend's raw value, as CSS defines each.
static float3 blended(int mode, float3 b, float3 l) {
    switch (mode) {
        case 1: return min(b + l, 1.0);
        case 2: return 1.0 - (1.0 - b) * (1.0 - l);
        case 3: return select(1.0 - 2.0 * (1.0 - b) * (1.0 - l), 2.0 * b * l, b < 0.5);
        case 4: {
            float3 d = select(sqrt(b), ((16.0 * b - 12.0) * b + 4.0) * b, b <= 0.25);
            return select(b + (2.0 * l - 1.0) * (d - b), b - (1.0 - 2.0 * l) * b * (1.0 - b), l <= 0.5);
        }
        case 5: return min(b / max(1.0 - l, 1e-3), 1.0);
        case 6: return b * l;
        case 7: return withLuminance(l, luminance(b));
        case 8: return abs(b - l);
        default: return l;
    }
}

// The screen moved `reach` along the normal, red and blue moved `apart` more and less, blurred by `blur`.
static float3 bent(texture2d<float> screen, float2 p, float2 n, float reach, float apart, float blur, float turn, float2 size) {
    if (apart <= 0.0) return blurred(screen, p + n * reach, size, blur, turn);
    float3 color;
    color.r = blurred(screen, p + n * reach * (1.0 + apart), size, blur, turn).r;
    color.g = blurred(screen, p + n * reach, size, blur, turn).g;
    color.b = blurred(screen, p + n * reach * (1.0 - apart), size, blur, turn).b;
    return color;
}

// Light from the top left catching the rim where it faces it, strongest at the very edge.
static float rimLight(float2 n, float s, float from) {
    float facing = 0.5 + 0.5 * dot(-n, normalize(float2(-0.6, -0.8)));
    return smoothstep(from, 1.0, s) * facing;
}

// Aurora's swell round the edges, 0.3 to 1: two slow waves of different lengths drifting apart.
static float swellAt(float x, float t) {
    return 0.65 + 0.35 * sin(2.0 * M_PI_F * (3.0 * x - 0.15 * t)) * sin(2.0 * M_PI_F * (5.0 * x + 0.11 * t));
}

// Ripple's waves running round the edges, -1 to 1.
static float waveAt(float x, float t) { return sin(2.0 * M_PI_F * (24.0 * x - 0.6 * t)); }

// Rings spreading from the pointer, -1 to 1, fading with distance from it.
static float ringsAt(float2 p, float2 pen, float w, float t) {
    float far = distance(p, pen);
    return sin(far / 14.0 - 3.0 * t) * exp(-pow(far / (w * 4.0), 2.0));
}

// The wake: a ring spreads from each point the pen passed. A ring is a short packet of waves that
// moves the picture out and back as it passes, and it fades as it spreads. `trail` holds each
// point's place in xy, its age in seconds in z, and in w its weight, less where points crowd.
static float2 wakeShift(float2 p, constant EdgeUniforms &u, constant float4 *trail) {
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

// One pixel of the band along the edges.
struct Band {
    float2 p;          // the pixel, in points
    float2 at;         // where the picture is read for it, once the wake has moved it
    float2 n;          // the inward normal of the nearest edge
    float d;           // how far in from the edge
    float w;           // the band's width
    float s;           // 1 at the edge, 0 at the band's inner edge
    float strength;    // how strongly the look shows here, from the pointer's focus
    float turn;        // the blur's turn at this pixel
};

static float4 premultiplied(float3 color, float alpha) { return float4(min(color, 1.0) * alpha, alpha); }

// The ring round the pointer: a soft ridge of glass on a circle `fieldRadius` out, with ink-coloured
// light on and round it. Inside the ridge nothing moves, so what the pointer is on stays put. A point
// on the ridge's slopes shows what lies k (R - r) h(r) further towards its crest, h the ridge's height,
// so the crest is magnified; the slope of that map is 1 + k h (2x^2 - 1), which stays positive for k
// under 1, so nothing folds back. Moving, it stretches along the way it goes and narrows across it,
// keeping its area. Premultiplied, and clear wherever it shows nothing.
static float4 pointerField(float2 p, texture2d<float> screen, constant EdgeUniforms &u) {
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

// Light in the aurora's colours flowing round the edges, swelling and thinning, `amount` as strong:
// its colour, not premultiplied, and how much it covers.
static float4 auroraLight(Band b, constant EdgeUniforms &u, float x, float t, float swell, float amount) {
    float glow = exp(-b.d / max(b.w * 0.35 * swell, 1.0)) * (0.55 + 0.45 * b.strength) * amount;
    float line = u.shine * exp(-max(b.d, 0.0) / 1.6);
    float3 color = mix(auroraColor(x, t, u), float3(1), line * 0.6);
    float alpha = clamp(glow * 0.85 + line, 0.0, 1.0) * smoothstep(0.0, 0.15, b.s);
    return float4(min(color, 1.0), alpha);
}

static float4 aurora(Band b, constant EdgeUniforms &u) {
    float x = around(b.p, u.size);
    float t = u.time * u.speed;
    float4 light = auroraLight(b, u, x, t, swellAt(x, t), 1.0);
    return premultiplied(light.rgb, light.a);
}

// Lens: the band packs in more of the screen than its width, as the rim of a wide lens does, and
// darkens a little where it squeezes most. A point `d` in shows what lies at d + k d (1 - d/w)^2,
// which keeps its order for k under 3, so nothing folds back. The slider's 0 to 2 is k from 0 to 2.9.
static float4 lens(Band b, texture2d<float> screen, constant EdgeUniforms &u) {
    float x = b.d / b.w;
    float reach = min(1.45 * u.bend, 2.9) * b.strength * max(b.d, 0.0) * (1.0 - x) * (1.0 - x);
    float3 color = bent(screen, b.at, b.n, reach, u.split * 0.6 * b.s, 0.0, b.turn, u.size);
    color *= 1.0 - 0.18 * b.s * b.s * b.s;
    color = mix(color, u.color.rgb, u.tint * b.strength * b.s * b.s * 0.6);
    color += rimLight(b.n, b.s, 0.85) * u.shine * 0.6;
    return premultiplied(color, smoothstep(0.0, 0.3, b.s));
}

// Ripple: waves running round the edges, and rings round the pointer.
static float4 ripple(Band b, texture2d<float> screen, constant EdgeUniforms &u) {
    float x = around(b.p, u.size);
    float t = u.time * u.speed;
    float height = (waveAt(x, t) * 0.6 + ringsAt(b.p, u.pen, b.w, t) * 0.8) * b.s * b.s;
    float reach = u.bend * b.strength * b.w * 0.25 * height;
    float3 color = bent(screen, b.at, b.n, reach, u.split * 0.5, 0.0, b.turn, u.size);
    color += u.shine * 0.25 * max(height, 0.0) * b.strength;
    return premultiplied(color, smoothstep(0.0, 0.3, b.s));
}

// Aurora ripple: ripple's waves bend the screen, and aurora's light rides on them. The waves rise
// where the light swells, and the light is brightest on their crests.
static float4 auroraRipple(Band b, texture2d<float> screen, constant EdgeUniforms &u) {
    float x = around(b.p, u.size);
    float t = u.time * u.speed;
    float swell = swellAt(x, t);
    float wave = waveAt(x, t);
    float height = (wave * 0.6 * swell + ringsAt(b.p, u.pen, b.w, t) * 0.8) * b.s * b.s;
    float reach = u.bend * b.strength * b.w * 0.25 * height;
    float bending = smoothstep(0.0, 0.3, b.s);
    // Under the light: the bent screen, and the screen as it is where the band fades out, so a
    // blend mode has a picture to work on across the whole band.
    float3 water = mix(sampleScreen(screen, b.at, u.size), bent(screen, b.at, b.n, reach, u.split * 0.5, 0.0, b.turn, u.size), bending);
    float4 light = auroraLight(b, u, x, t, swell, u.light * (0.5 + max(wave, 0.0)));
    float3 color = mix(water, blended(int(u.blend + 0.5), water, light.rgb), light.a);
    return premultiplied(color, max(bending, light.a));
}

// Frost: a band of frosted glass with a bright rim, and no bend.
static float4 frost(Band b, texture2d<float> screen, constant EdgeUniforms &u) {
    float blur = u.frost * b.w * 0.5 * smoothstep(0.0, 0.7, b.s) * (0.5 + 0.5 * b.strength);
    float3 color = blurred(screen, b.at, u.size, blur, b.turn);
    color = mix(color, float3(1), 0.12 * smoothstep(0.0, 0.6, b.s));
    color = mix(color, u.color.rgb, u.tint * 0.5 * b.s);
    color += rimLight(b.n, b.s, 0.8) * u.shine * 0.8;
    return premultiplied(color, smoothstep(0.0, 0.4, b.s));
}

// Glass: a slab whose rim curves down to the edge, a quarter circle across the band. It shows what
// lies further in, more so towards the edge, and moves nothing at the inner edge. A point `d` in
// shows what lies at d + k w lift(s), which keeps its order while k lift'(s) stays under 1. The
// circle's slope has no limit at the edge, so from where k lift' reaches 0.8 the rim goes on
// straight: the picture magnifies at most five times and never folds back.
static float4 glass(Band b, texture2d<float> screen, constant EdgeUniforms &u) {
    float k = 1.5 * u.bend * b.strength;
    float m = 0.8 / max(k, 1e-4);
    float sc = m / sqrt(1.0 + m * m);
    float lift = b.s <= sc ? 1.0 - sqrt(max(0.0, 1.0 - b.s * b.s)) : 1.0 - sqrt(1.0 - sc * sc) + m * (b.s - sc);
    float reach = k * b.w * lift;
    float blur = u.frost * b.strength * b.w * 0.4 * b.s;
    float3 color = bent(screen, b.at, b.n, reach, u.split * 0.5, blur, b.turn, u.size);
    color = mix(color, u.color.rgb, u.tint * b.strength * b.s * b.s);
    color += rimLight(b.n, b.s, 0.55) * u.shine * (0.4 + 0.6 * b.strength) * 0.9;
    // Fades out over the band's inner quarter, where nothing has moved yet.
    return premultiplied(color, smoothstep(0.0, 0.25, b.s));
}

fragment float4 edgeFragment(Varyings in [[stage_in]],
                             texture2d<float> screen [[texture(0)]],
                             constant EdgeUniforms &u [[buffer(0)]],
                             constant float4 *trail [[buffer(1)]]) {
    float2 p = in.uv * u.size;
    float2 shift = wakeShift(p, u, trail);
    float moved = length(shift);
    float d = inside(p, u);
    float w = max(u.width, 1.0);
    int style = int(u.style + 0.5);
    // Glow is drawn by EdgeGlow, so with it this layer draws only the wake and the pointer's ring.
    bool inBand = style != 0 && style != 7 && d <= w && d >= -1.0;
    float4 field = pointerField(p, screen, u);
    if (!inBand && moved < 0.01) return field;

    // The wake shows the picture moved, and fades in with how far it moved, so the layer is clear
    // wherever nothing moved and meets the screen without a seam.
    float4 wake = premultiplied(sampleScreen(screen, p - shift, u.size), clamp(moved * 4.0, 0.0, 1.0));
    if (!inBand) return field + wake * (1.0 - field.a);

    Band b;
    b.p = p;
    b.at = p - shift;
    b.n = inward(p, u);
    b.d = d;
    b.w = w;
    b.s = clamp(1.0 - d / w, 0.0, 1.0);
    b.strength = gathered(p, u);
    // Interleaved gradient noise: a different turn for the blur at each pixel, the same every frame.
    b.turn = fract(52.9829189 * fract(dot(in.position.xy, float2(0.06711056, 0.00583715))));
    float4 look;
    switch (style) {
        case 2: look = lens(b, screen, u); break;
        case 3: look = aurora(b, u); break;
        case 4: look = ripple(b, screen, u); break;
        case 5: look = frost(b, screen, u); break;
        case 6: look = auroraRipple(b, screen, u); break;
        default: look = glass(b, screen, u); break;
    }
    return field + (look + wake * (1.0 - look.a)) * (1.0 - field.a);
}
