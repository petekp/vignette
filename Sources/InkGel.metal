#include <metal_stdlib>
using namespace metal;

// The person's live ink as adaptive ice (docs/live-ink-gel-2026-10-12.md): a rod lit from the top
// left, its normal turning with the line. Over dark content it is luminous ice, a white core falling
// to a cool blue. Over light content a deep blue sheath grows in from its edge, so it keeps its
// contrast on any window. A halo pass under it draws the glow and the shadow.

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
    float2 size;       // the layer, px
    float scale;       // px a point
    float time;        // the material's clock, s
    float4 light;      // rgb the ice's hue, and a: how white its middle is
    float4 deep;       // rgb the deep blue at the middle of the line
    float4 glow;       // glow, bloom, glow radius in px, shadow
    float4 more;       // head opacity, light wander in radians, shimmer, highlight
    float4 behind;     // the switch's low and high brightness, how far the newest map has faded in, the sheath's depth
    float4 mapNow;     // the newest brightness map's rect, in px of the layer
    float4 mapBefore;  // the map it fades in from
    float4 offset;     // xy: px taken off every vertex's place, so a line laid out once is drawn as its layer moves
    float4 material;   // the highlight's sharpness, the glow's falloff, the deep blue's edge, the ice's edge opacity
    float4 lightPlace; // the shimmer's wavelength in pt and its speed, the light's angle in radians and its height
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
    float2 pos = float2(v.pos) - uni.offset.xy;
    out.position = float4(pos.x / uni.size.x * 2 - 1, 1 - pos.y / uni.size.y * 2, 0, 1);
    out.u = v.u; out.s = v.s; out.halfw = v.halfw; out.extent = v.extent; out.kind = v.kind; out.pass = v.pass;
    // A head's tangent is its middle, a place like the vertex's own.
    out.tangent = v.kind > 0.5 ? float2(v.tangent) - uni.offset.xy : float2(v.tangent); out.pixel = pos;
    return out;
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
    float phi = uni.lightPlace.z + uni.more.y * sin(uni.time * 0.45);
    lit.L = normalize(float3(cos(phi), sin(phi), uni.lightPlace.w));
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

/// How light the screen is behind this pixel, 0 to 1, from the brightness maps: the one fading in
/// over the one before it. A map is a grid of 8 pt cells, so this follows windows and regions, not
/// the letters of a text.
static float brightness(float2 pixel, constant GelUniforms &uni, texture2d<float> now, texture2d<float> before) {
    constexpr sampler cells(filter::linear, address::clamp_to_edge);
    float b = before.sample(cells, (pixel - uni.mapBefore.xy) / uni.mapBefore.zw).r;
    float n = now.sample(cells, (pixel - uni.mapNow.xy) / uni.mapNow.zw).r;
    return mix(b, n, uni.behind.z);
}

fragment float4 gelFragment(GelVaryings in [[stage_in]], constant GelUniforms &uni [[buffer(1)]],
                            texture2d<float> mapNow [[texture(0)]], texture2d<float> mapBefore [[texture(1)]]) {
    Lit lit = light(in, uni);
    float a = clamp(abs(in.u), 0.0, 1.0);
    float across = in.kind < 0.5 ? clamp(abs(in.u) * in.extent / max(in.halfw, 1e-3), 0.0, 1.0) : a;
    float lightBehind = smoothstep(uni.behind.x, uni.behind.y, brightness(in.pixel, uni, mapNow, mapBefore));
    float3 hue = uni.light.rgb;
    float shimmer = 1 + 0.25 * uni.more.z * sin(in.s / (max(uni.lightPlace.x, 1.0) * uni.scale) - uni.time * uni.lightPlace.y);

    if (in.pass < 0.5) {
        // The halo: a glow in the ice's colour, brightest where the line faces the light, and a
        // shadow. Drawn with max blending, so a loop that crosses itself is not brighter there,
        // and over a light window the shadow wins. Over light content the glow mostly goes, since
        // it can only tint what is there.
        // A line's distance from its middle; a head's from its centre, so its glow is round.
        float dist = in.kind < 0.5 ? a * in.extent : length(in.pixel - in.tangent);
        float core = in.kind < 0.5 ? in.halfw * 0.6 : in.halfw * 0.4;
        float edge = in.halfw;
        float reach = max(uni.glow.z, 1.0);
        float fall = exp(-uni.material.y * pow(max(dist - core, 0.0) / reach, 2.0));
        // The shadow starts past the line's soft edge, so it never reads as a dark outline.
        float shadowFall = exp(-2.0 * pow(max(dist - edge - 1.5, 0.0) / reach, 2.0));
        float strength = (uni.glow.x + uni.glow.y * lit.facing * lit.facing) * shimmer * (in.kind < 0.5 ? 1.0 : 0.6)
                         * (1 - 0.7 * lightBehind);
        float3 glow = clamp(hue, 0.0, 1.0) * fall * strength * 0.7;
        // Light of its own: over black it adds its colour, so its opacity is its brightness.
        // A head's round halo would cast a disc, so only the line casts a shadow.
        float alpha = max(dot(glow, float3(0.333)), in.kind < 0.5 ? uni.glow.w * shadowFall : 0.0);
        // A head's halo comes in with its head.
        return float4(min(glow, float3(alpha)), alpha) * (in.kind > 0.5 ? uni.more.x : 1.0);
    }

    float3 H = normalize(lit.L + float3(0, 0, 1));
    float nh = max(dot(lit.n, H), 0.0);
    float spec = pow(nh, max(uni.material.x, 1.0)) * uni.more.w;
    float soft = pow(nh, 12.0) * shimmer;
    float core = pow(lit.h, 3.0);
    // The ice: a white middle falling to its hue at the edge, its highlight running with the light.
    float3 ice = mix(hue * 0.8, float3(1.0), uni.light.a * core) + spec + 0.08 * soft * hue;
    // The deep blue: darker at the edge, with a paler highlight.
    float3 deep = mix(uni.deep.rgb * uni.material.z, uni.deep.rgb, core) + spec * 1.5;
    // Between the two, the deep sheath grows in from the edge rather than the colours mixing: a mid
    // colour stands out from nothing, and a light middle in a dark sheath stands out from anything.
    float sheath = smoothstep(1.12 - uni.behind.w * lightBehind, 1.28 - uni.behind.w * lightBehind, across);
    float3 colour = mix(ice, deep, sheath);
    // Coverage in screen pixels: a line's edge is its half width, a pixel soft, inside a strip that
    // reaches past it; a head's is its outline, from how fast its place across changes per pixel.
    float edge = in.kind < 0.5 ? clamp(in.halfw - abs(in.u) * in.extent + 0.5, 0.0, 1.0)
                               : clamp((1.0 - a) / max(fwidth(in.u), 1e-4) + 0.5, 0.0, 1.0);
    float alpha = mix(uni.material.w + (1 - uni.material.w) * core, 0.95, sheath) * edge * (in.kind > 0.5 ? uni.more.x : 1.0);
    return float4(clamp(colour, 0.0, 1.0) * alpha, alpha);
}
