// kukabara close: the window drops down with a slight random tilt (niri's example, tuned).
vec4 close_color(vec3 coords_geo, vec3 size_geo) {
    float p = niri_clamped_progress * niri_clamped_progress;
    vec2 coords = (coords_geo.xy - vec2(0.5, 1.0)) * size_geo.xy;
    coords.y -= p * 360.0;
    float r = (niri_random_seed - 0.5) / 2.0;
    r = sign(r) - r;
    float angle = p * 0.09 * r;
    mat2 rotate = mat2(cos(angle), -sin(angle), sin(angle), cos(angle));
    coords = rotate * coords;
    vec3 geo = vec3(coords / size_geo.xy + vec2(0.5, 1.0), 1.0);
    if (geo.x < 0.0 || geo.x > 1.0 || geo.y < 0.0 || geo.y > 1.0)
        return vec4(0.0);
    vec4 color = texture2D(niri_tex, (niri_geo_to_tex * geo).st);
    return color * (1.0 - niri_clamped_progress);
}
