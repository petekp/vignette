#include <metal_stdlib>
using namespace metal;

// The person's live ink as adaptive ice (docs/live-ink-gel-2026-10-12.md): one soft rod lit from the
// top left. Over dark content it is luminous ice, a white core falling to a cool blue. Over light
// content a deep blue sheath grows in from its edge, so it keeps its contrast on any window.
//
// A mark is drawn in two passes (docs/live-ink-one-material-2026-10-13.md). The field pass writes, for
// every pixel near the mark, its signed distance to the mark's edge: each segment of the line as a
// capsule, the arrowhead as a rounded triangle, and the depth test keeps the nearest, so the line, its
// joins and its head are one shape. The light pass lights that shape as one surface, and draws its
// glow and shadow from the same distance.

struct GelVertex {
    packed_float2 pos;  // px from the layer's top-left, y down
    packed_float2 a;    // a segment's start, px; unused for the head
    packed_float2 b;    // its end
    float ra, rb;       // its half width at each end, px
    float s;            // px along the line at its start
    float kind;         // 0 a segment, 1 the head
};

struct GelUniforms {
    float2 size;       // the layer, px
    float scale;       // px a point
    float time;        // the material's clock, s
    float4 light;      // rgb the ice's hue, and a: how white its middle is
    float4 deep;       // rgb the deep blue at the middle of the line
    float4 glow;       // glow, bloom, glow radius in px, shadow
    float4 more;       // unused, light wander in radians, shimmer, highlight
    float4 behind;     // x: the stroke's colour, 0 the ice and 1 the deep blue; w: the sheath's depth
    float4 offset;     // xy: px taken off every vertex's place, so a line laid out once is drawn as its layer moves
    float4 material;   // the highlight's sharpness, the glow's falloff, the deep blue's edge, the ice's edge opacity
    float4 lightPlace; // the shimmer's wavelength in pt and its speed, the light's angle in radians and its height
    float4 head[4];    // the head's corners, px, two to a float4, already moved in by its rounding
    float4 headShape;  // the corner count, the rounding, how far it is shrunk, px along the line at it
    float4 headMore;   // x: the line's half width where it meets the head, px
};

struct FieldVaryings {
    float4 position [[position]];
    float2 pixel, a, b;
    float ra, rb, s, kind;
};

struct FieldOut {
    float4 field [[color(0)]];  // the signed distance to the edge in px, the half width there, the shimmer's phase
    float depth [[depth(any)]];
};

vertex FieldVaryings gelFieldVertex(uint id [[vertex_id]], const device GelVertex *vertices [[buffer(0)]],
                                    constant GelUniforms &uni [[buffer(1)]]) {
    GelVertex v = vertices[id];
    FieldVaryings out;
    float2 shift = uni.offset.xy;
    float2 pos = float2(v.pos) - shift;
    out.position = float4(pos.x / uni.size.x * 2 - 1, 1 - pos.y / uni.size.y * 2, 0, 1);
    out.pixel = pos;
    out.a = float2(v.a) - shift; out.b = float2(v.b) - shift;
    out.ra = v.ra; out.rb = v.rb; out.s = v.s; out.kind = v.kind;
    return out;
}

/// The signed distance from `p` to a convex polygon's edge, negative inside.
static float polygon(float2 p, constant GelUniforms &uni, float2 shift) {
    int count = int(uni.headShape.x);
    float2 first = uni.head[0].xy - shift;
    float d = dot(p - first, p - first);
    float inside = 1;
    for (int i = 0, j = count - 1; i < count; j = i, i++) {
        float2 vi = (i % 2 == 0 ? uni.head[i / 2].xy : uni.head[i / 2].zw) - shift;
        float2 vj = (j % 2 == 0 ? uni.head[j / 2].xy : uni.head[j / 2].zw) - shift;
        float2 e = vj - vi, w = p - vi;
        float2 q = w - e * clamp(dot(w, e) / max(dot(e, e), 1e-6), 0.0, 1.0);
        d = min(d, dot(q, q));
        bool3 c = bool3(p.y >= vi.y, p.y < vj.y, e.x * w.y > e.y * w.x);
        if (all(c) || all(!c)) inside = -inside;
    }
    return inside * sqrt(d);
}

fragment FieldOut gelField(FieldVaryings in [[stage_in]], constant GelUniforms &uni [[buffer(1)]]) {
    float sd, r, s;
    if (in.kind < 0.5) {
        // A capsule whose half width runs from `ra` to `rb`.
        float2 ba = in.b - in.a;
        float t = clamp(dot(in.pixel - in.a, ba) / max(dot(ba, ba), 1e-6), 0.0, 1.0);
        r = mix(in.ra, in.rb, t);
        sd = length(in.pixel - in.a - ba * t) - r;
        s = in.s + t * length(ba);
    } else {
        // The head, its corners rounded, shrunk toward its middle while it comes in.
        sd = polygon(in.pixel, uni, uni.offset.xy) - uni.headShape.y + uni.headShape.z;
        r = uni.headMore.x;
        s = uni.headShape.w;
    }
    // The shimmer only needs the phase, and a half float keeps a phase where it could not keep a length.
    float period = 2 * M_PI_F * max(uni.lightPlace.x, 1.0) * uni.scale;
    FieldOut out;
    out.field = float4(sd, r, fmod(s, period), 0);
    out.depth = clamp((sd + 1024) / 4096, 0.0, 1.0);
    return out;
}

/// How the distance grows at `at`, from the field `span` px either side: a unit vector where one part
/// of the mark is nearest, and shorter across a line where two are equally near, so it blends between
/// their directions rather than pointing between them. A pixel past the field's reach reads as far
/// away; held near this one, it leaves the slope sound.
static float2 slope(texture2d<float, access::read> field, uint2 at, float sd, int span) {
    int2 most = int2(field.get_width() - 1, field.get_height() - 1);
    float limit = sd + 2.0 * float(span);
    float right = min(field.read(uint2(clamp(int2(at) + int2(span, 0), int2(0), most))).x, limit);
    float left = min(field.read(uint2(clamp(int2(at) - int2(span, 0), int2(0), most))).x, limit);
    float down = min(field.read(uint2(clamp(int2(at) + int2(0, span), int2(0), most))).x, limit);
    float up = min(field.read(uint2(clamp(int2(at) - int2(0, span), int2(0), most))).x, limit);
    return float2(right - left, down - up) / (2.0 * float(span));
}

// The light pass draws the field pass's triangles again, so it shades only the pixels near the mark.
// Where they overlap, each draws the same colour from the same field.
fragment float4 gelLight(FieldVaryings in [[stage_in]], texture2d<float, access::read> field [[texture(0)]],
                         constant GelUniforms &uni [[buffer(1)]]) {
    uint2 at = uint2(in.position.xy);
    float4 here = field.read(at);
    float sd = here.x;
    float reach = max(uni.glow.z, 1.0);
    if (sd > reach * 3) return float4(0);
    // The slope of the distance, read `span` px either side: a few pixels wide, so a turn as tight as
    // a rectangle's corner bends the light smoothly, and the glow's direction blends across the line
    // where two parts are equally near instead of flipping there.
    float2 side = slope(field, at, sd, 2);
    side = length(side) > 1e-4 ? normalize(side) : float2(0);
    float2 glowSide = slope(field, at, sd, 8);
    float r = max(here.y, 0.5);

    float phi = uni.lightPlace.z + uni.more.y * sin(uni.time * 0.45);
    float3 L = normalize(float3(cos(phi), sin(phi), uni.lightPlace.w));
    // A rod's place across, 0 at its middle and 1 at its edge, from how deep in the shape it is; past
    // its half width, as inside the head, the shape is flat on top.
    float across = clamp(1 + sd / r, 0.0, 1.0);
    float h = sqrt(max(1 - across * across, 0.0));
    float3 n = normalize(float3(side * across, h));
    float facing = abs(dot(glowSide, normalize(L.xy)));
    float lightBehind = uni.behind.x;
    float3 hue = uni.light.rgb;
    float shimmer = 1 + 0.25 * uni.more.z * sin(here.z / (max(uni.lightPlace.x, 1.0) * uni.scale) - uni.time * uni.lightPlace.y);

    // The glow in the ice's colour, brightest where the edge faces the light, and the shadow, which
    // starts past the soft edge so it never reads as a dark outline. Over light content the glow
    // mostly goes, since it can only tint what is there.
    float fall = exp(-uni.material.y * pow(max(sd + 0.4 * r, 0.0) / reach, 2.0));
    float shadowFall = exp(-2.0 * pow(max(sd - 1.5, 0.0) / reach, 2.0));
    float strength = (uni.glow.x + uni.glow.y * facing * facing) * shimmer * (1 - 0.7 * lightBehind);
    float3 glow = clamp(hue, 0.0, 1.0) * fall * strength * 0.7;
    // Light of its own: over black it adds its colour, so its opacity is its brightness.
    float haloAlpha = max(dot(glow, float3(0.333)), uni.glow.w * shadowFall);
    float4 halo = float4(min(glow, float3(haloAlpha)), haloAlpha);

    float3 H = normalize(L + float3(0, 0, 1));
    float nh = max(dot(n, H), 0.0);
    float spec = pow(nh, max(uni.material.x, 1.0)) * uni.more.w;
    float soft = pow(nh, 12.0) * shimmer;
    float core = pow(h, 3.0);
    // The ice: a white middle falling to its hue at the edge, its highlight running with the light.
    float3 ice = mix(hue * 0.8, float3(1.0), uni.light.a * core) + spec + 0.08 * soft * hue;
    // The deep blue: darker at the edge, with a paler highlight.
    float3 deep = mix(uni.deep.rgb * uni.material.z, uni.deep.rgb, core) + spec * 1.5;
    // Between the two, the deep sheath grows in from the edge rather than the colours mixing: a mid
    // colour stands out from nothing, and a light middle in a dark sheath stands out from anything.
    float sheath = smoothstep(1.12 - uni.behind.w * lightBehind, 1.28 - uni.behind.w * lightBehind, across);
    float3 colour = mix(ice, deep, sheath);
    float edge = clamp(0.5 - sd, 0.0, 1.0);
    float alpha = mix(uni.material.w + (1 - uni.material.w) * core, 0.95, sheath) * edge;
    float4 body = float4(clamp(colour, 0.0, 1.0) * alpha, alpha);
    return body + halo * (1 - body.a);
}
