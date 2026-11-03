// kukabara close: slices jump sideways, colours split, rows drop out.
float angelos_hash1(float n) {
    return fract(sin(n) * 43758.5453);
}

vec4 angelos_take(vec2 g) {
    if (g.x < 0.0 || g.x > 1.0 || g.y < 0.0 || g.y > 1.0)
        return vec4(0.0);
    return texture2D(niri_tex, (niri_geo_to_tex * vec3(g, 1.0)).st);
}

vec4 close_color(vec3 coords_geo, vec3 size_geo) {
    float p = niri_clamped_progress;
    float slice = floor(coords_geo.y * 22.0);
    float tick = floor(p * 14.0);
    float r = angelos_hash1(slice * 7.13 + tick * 3.71 + niri_random_seed * 91.0);
    if (r < p * 0.9)
        return vec4(0.0);
    float shift = r > 0.6 ? (angelos_hash1(slice + tick * 1.3) - 0.5) * 0.3 * p : 0.0;
    vec2 g = vec2(coords_geo.x + shift, coords_geo.y);
    float split = 0.025 * p;
    vec4 cr = angelos_take(g + vec2(split, 0.0));
    vec4 cg = angelos_take(g);
    vec4 cb = angelos_take(g - vec2(split, 0.0));
    vec4 color = vec4(cr.r, cg.g, cb.b, max(max(cr.a, cg.a), cb.a));
    return color * (1.0 - p * p);
}
