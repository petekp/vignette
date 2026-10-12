#include <metal_stdlib>
using namespace metal;

// The person's live ink as opal gel (docs/live-ink-gel-2026-10-12.md): a rod of milky material lit
// from the top left, its normal turning with the line, under a thin film whose pale colours change
// with the view and with the line's direction to the light. A halo pass under it draws the glow and
// the shadow.

struct GelVertex {
    packed_float2 pos;      // px from the layer's top-left, y down
    float u;                // across: -1 to 1 on a line; 0 at a head's middle to 1 at its edge
    float s;                // px along the line from its start
    float halfw;            // the line's half width here, px; a head's halo: its own share of the fan
    packed_float2 tangent;  // a line: unit, along it; a head: its middle, px
    float extent;           // the strip's half width, px: the line's own, or the halo's
    float kind;             // 0 a line, 1 a head
    float pass;             // 0 the halo, 1 the body
};

struct GelUniforms {
    float2 size;     // the layer, px
    float scale;     // px a point
    float time;      // the material's clock, s
    float4 body;     // rgb, and a: whether the colour is an override (the done state)
    float4 look;     // iridescence, film thickness in nm, sheen, rim darkening
    float4 glow;     // glow, bloom, glow radius in px, shadow
    float4 more;     // head opacity, light wander in radians, shimmer, 0
};

struct GelVaryings {
    float4 position [[position]];
    float u, s, halfw, extent, kind, pass;
    float2 tangent, pixel;
};

vertex GelVaryings gelVertex(uint id [[vertex_id]], const device GelVertex *vertices [[buffer(0)]],
                             constant GelUniforms &uni [[buffer(1)]]) {
    GelVertex v = vertices[id];
    GelVaryings out;
    out.position = float4(v.pos.x / uni.size.x * 2 - 1, 1 - v.pos.y / uni.size.y * 2, 0, 1);
    out.u = v.u; out.s = v.s; out.halfw = v.halfw; out.extent = v.extent; out.kind = v.kind; out.pass = v.pass;
    out.tangent = v.tangent; out.pixel = v.pos;
    return out;
}

static float bell(float x, float m, float w) { float t = (x - m) / w; return exp(-t * t); }

/// The pale colour a film `d` nm thick reflects at `cosT` inside it, as a tint about white:
/// sin^2 of the phase summed over the visible wavelengths through rough colour matching curves.
static float3 filmTint(float d, float cosT, float amount) {
    float3 sum = 0, weights = 0;
    for (int i = 0; i < 14; i++) {
        float l = 400.0 + float(i) * 21.0;
        float r = sin(2.0 * M_PI_F * 1.33 * d * cosT / l);
        float3 w = float3(bell(l, 600, 45) + 0.25 * bell(l, 445, 25), bell(l, 545, 45), bell(l, 450, 30));
        sum += r * r * w;
        weights += w;
    }
    float3 f = sum / weights;
    float mean = (f.r + f.g + f.b) / 3;
    // A real film is paler than this; stretched about its mean so a thin line still shows it, and
    // held short of the colours a screen cannot show, which clipped to neon.
    return clamp(1.0 + (f - mean) * 1.6 * amount, 0.55, 1.45);
}

struct Lit {
    float3 n;
    float h;
    float facing;
    float3 L;
};

/// The rod's normal here, its height, how squarely its line faces the light, and the light.
static Lit light(GelVaryings in, constant GelUniforms &uni) {
    Lit lit;
    // A line's strip reaches past its edge, so its place across is its distance over its half width.
    float a = in.kind < 0.5 ? clamp(abs(in.u) * in.extent / max(in.halfw, 1e-3), 0.0, 1.0) : clamp(abs(in.u), 0.0, 1.0);
    float phi = -2.15 + uni.more.y * sin(uni.time * 0.45);
    lit.L = normalize(float3(cos(phi), sin(phi), 1.1));
    float2 side;
    if (in.kind < 0.5) {
        float2 t = normalize(in.tangent);
        side = float2(-t.y, t.x);
        lit.h = sqrt(max(1 - a * a, 0.0));
        lit.n = normalize(float3(side * sign(in.u) * a, lit.h));
    } else {
        // A head is a low dome over its middle.
        float2 out = in.pixel - in.tangent;
        float r = length(out);
        side = r > 0 ? out / r : float2(0, 1);
        lit.h = sqrt(max(1 - 0.3 * a * a, 0.0));
        lit.n = normalize(float3(side * a * 0.35, 1.0));
    }
    // A head takes one colour, as the end of its line does, rather than one per side of its middle.
    lit.facing = in.kind < 0.5 ? abs(dot(side, normalize(lit.L.xy))) : 0.5;
    return lit;
}

static float filmThickness(GelVaryings in, constant GelUniforms &uni, float facing) {
    return uni.look.y + 170 * facing + 40 * uni.more.z * sin(in.s / (160 * uni.scale) - uni.time * 0.35);
}

static float3 bodyColour(constant GelUniforms &uni) {
    return uni.body.a > 0.5 ? mix(uni.body.rgb, float3(1), 0.25) : uni.body.rgb;
}

fragment float4 gelFragment(GelVaryings in [[stage_in]], constant GelUniforms &uni [[buffer(1)]]) {
    Lit lit = light(in, uni);
    float a = clamp(abs(in.u), 0.0, 1.0);
    float across = in.kind < 0.5 ? clamp(abs(in.u) * in.extent / max(in.halfw, 1e-3), 0.0, 1.0) : a;
    float d = filmThickness(in, uni, lit.facing);
    // The view through the film steepens fast at the rod's edge; held short of grazing, so the colour does
    // not cycle from pixel to pixel there.
    float3 tint = filmTint(d, mix(1.0, max(lit.n.z, 0.6), 0.8), uni.look.x);
    float3 base = bodyColour(uni);

    if (in.pass < 0.5) {
        // The halo: a glow in the film's colour, brightest where the line faces the light, and a
        // shadow. Drawn with max blending, so a loop that crosses itself is not brighter there,
        // and over a light window the shadow wins.
        // A line's distance from its middle; a head's from its centre, so its glow is round.
        float dist = in.kind < 0.5 ? a * in.extent : length(in.pixel - in.tangent);
        float core = in.kind < 0.5 ? in.halfw * 0.6 : in.halfw * 0.4;
        float edge = in.halfw;
        float reach = max(uni.glow.z, 1.0);
        float fall = exp(-2.2 * pow(max(dist - core, 0.0) / reach, 2.0));
        // The shadow starts past the line's soft edge, so it never reads as a dark outline.
        float shadowFall = exp(-2.0 * pow(max(dist - edge - 1.5, 0.0) / reach, 2.0));
        float shimmer = 1 + 0.25 * uni.more.z * sin(in.s / (90 * uni.scale) - uni.time * 1.1);
        float strength = (uni.glow.x + uni.glow.y * lit.facing * lit.facing) * shimmer * (in.kind < 0.5 ? 1.0 : 0.6);
        // The glow is mostly the body's own colour, touched by the film's.
        float3 hue = clamp(base * mix(float3(1), tint, 0.5), 0.0, 1.0);
        float3 glow = hue * fall * strength * 0.7;
        // Light of its own: over black it adds its colour, so its opacity is its brightness.
        // A head's round halo would cast a disc, so only the line casts a shadow.
        float alpha = max(dot(glow, float3(0.333)), in.kind < 0.5 ? uni.glow.w * shadowFall : 0.0);
        // A head's halo comes in with its head.
        return float4(min(glow, float3(alpha)), alpha) * (in.kind > 0.5 ? uni.more.x : 1.0);
    }

    float3 H = normalize(lit.L + float3(0, 0, 1));
    float nh = max(dot(lit.n, H), 0.0);
    float spec = pow(nh, 90.0);
    float soft = pow(nh, 10.0) * (1 + 0.25 * uni.more.z * sin(in.s / (90 * uni.scale) - uni.time * 1.1));
    float diffuse = max(dot(lit.n, lit.L), 0.0);
    float rim = pow(1 - lit.n.z, 3.0);
    float3 colour = base * (0.84 + 0.16 * diffuse) * mix(float3(1), tint, 0.35 + 0.45 * rim);
    colour = mix(colour, tint, 0.25 * soft) + spec * uni.look.z;
    colour *= mix(1.0, 1.0 - uni.look.w, across * across * across);
    // Gel thins at its edge: it pales and lets what is behind through, rather than darkening into an
    // outline that steps along a curve.
    float thin = smoothstep(0.55, 1.0, across);
    colour = mix(colour, mix(float3(1), tint, 0.5), 0.45 * thin);
    // Coverage in screen pixels: a line's edge is its half width, a pixel soft, inside a strip that
    // reaches past it; a head's is its outline, from how fast its place across changes per pixel.
    float edge = in.kind < 0.5 ? clamp(in.halfw - abs(in.u) * in.extent + 0.5, 0.0, 1.0)
                               : clamp((1.0 - a) / max(fwidth(in.u), 1e-4) + 0.5, 0.0, 1.0);
    float alpha = 0.92 * mix(1.0, 0.45, thin) * edge * (in.kind > 0.5 ? uni.more.x : 1.0);
    return float4(clamp(colour, 0.0, 1.0) * alpha, alpha);
}
