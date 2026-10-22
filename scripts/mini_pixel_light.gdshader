shader_type canvas_item;
render_mode unshaded;
uniform vec3 ambient = vec3(1.0);
uniform float local_gain = 0.34;
uniform float flicker = 1.0;
uniform vec2 scene_origin = vec2(0.0);
uniform vec2 scene_scale = vec2(2.0);
uniform vec4 pot_rect = vec4(17.0, 11.0, 48.0, 48.0);
uniform bool preserve_emissive = true;
varying vec2 logical_pixel;

void vertex() {
    logical_pixel = ((MODEL_MATRIX * vec4(VERTEX, 0.0, 1.0)).xy - scene_origin) / scene_scale;
}

float attenuation(vec2 point, vec2 center, float radius) {
    float t = max(0.0, 1.0 - distance(point, center) / radius);
    return floor(pow(t, 1.3) * 5.0 + 0.5) / 5.0;
}

void fragment() {
    vec4 raw = COLOR;
    vec2 point = floor(logical_pixel);
    vec2 warm_center = pot_rect.xy + pot_rect.zw * vec2(0.5, 0.9375);
    vec2 pink_center = pot_rect.xy + pot_rect.zw * vec2(0.5, 0.291667);
    float warm = attenuation(point, warm_center, pot_rect.z * 1.416667) * 0.65 * local_gain * flicker;
    float pink = attenuation(point, pink_center, pot_rect.z * 1.041667) * 0.32 * local_gain;
    vec3 gain = ambient + vec3(warm + pink * 0.8, warm * 0.82 + pink * 0.08, warm * 0.08 + pink * 0.63);
    vec3 lit = min(vec3(1.0), raw.rgb * gain);
    vec2 relative = (point - pot_rect.xy) / pot_rect.zw;
    bool inside_pot = all(greaterThanEqual(relative, vec2(0.0))) && all(lessThan(relative, vec2(1.0)));
    bool flame = relative.y > 0.75 && raw.r > 0.588 && raw.g > 0.196 && raw.b < 0.471;
    bool liquid = relative.y < 0.541667 && raw.r > 0.510 && raw.b > 0.255 && raw.r > raw.g * 1.4;
    if (preserve_emissive && inside_pot && (flame || liquid)) lit = min(vec3(1.0), raw.rgb * 1.04);
    COLOR = vec4(lit, raw.a);
}
