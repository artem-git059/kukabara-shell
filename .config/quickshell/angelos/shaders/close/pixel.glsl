// kukabara close: the window crumbles into pixel blocks that blink out one by one.
float angelos_hash(vec2 p) {
    return fract(sin(dot(p, vec2(12.9898, 78.233))) * 43758.5453);
}

vec4 close_color(vec3 coords_geo, vec3 size_geo) {
    if (coords_geo.x < 0.0 || coords_geo.x > 1.0 || coords_geo.y < 0.0 || coords_geo.y > 1.0)
        return vec4(0.0);
    float p = niri_clamped_progress;
    vec2 px = coords_geo.xy * size_geo.xy;
    // blocks grow in steps (4 → 24 px) so the picture turns chunky
    float block = 4.0 * floor(mix(1.0, 6.99, p));
    vec2 sample_geo = (floor(px / block) + 0.5) * block / size_geo.xy;
    // a fixed 16 px grid decides when each block vanishes: top rows first, with noise
    vec2 cell = floor(px / 16.0);
    float t = angelos_hash(cell + niri_random_seed * 37.0) * 0.75 + (1.0 - coords_geo.y) * 0.25;
    if (p > t)
        return vec4(0.0);
    vec4 color = texture2D(niri_tex, (niri_geo_to_tex * vec3(sample_geo, 1.0)).st);
    return color * (1.0 - 0.35 * p);
}
