// kukabara close: an old TV switching off — squashed to a bright line, then to a dot.
vec4 close_color(vec3 coords_geo, vec3 size_geo) {
    float p = niri_clamped_progress;
    float sy = p < 0.55 ? mix(1.0, 0.006, pow(p / 0.55, 0.7)) : 0.006;
    float sx = p < 0.55 ? 1.0 : mix(1.0, 0.0, (p - 0.55) / 0.45);
    if (sx < 0.002)
        return vec4(0.0);
    vec2 c = coords_geo.xy - 0.5;
    vec2 g = vec2(c.x / sx, c.y / sy) + 0.5;
    if (g.x < 0.0 || g.x > 1.0 || g.y < 0.0 || g.y > 1.0)
        return vec4(0.0);
    vec4 color = texture2D(niri_tex, (niri_geo_to_tex * vec3(g, 1.0)).st);
    float flash = smoothstep(0.25, 0.55, p);
    color.rgb = mix(color.rgb, vec3(color.a), flash);
    return color * (1.0 - smoothstep(0.8, 1.0, p));
}
