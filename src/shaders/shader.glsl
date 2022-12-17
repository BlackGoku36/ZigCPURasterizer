/* quad vertex shader */
@vs vs

in vec2 position;
out vec2 uv;

void main() {
    gl_Position = vec4(position*2.0-1.0, 0.5, 1.0);
    uv = vec2(position.x, 1.0 - position.y);
}
@end

/* quad fragment shader */
@fs fs

uniform sampler2D tex;

in vec2 uv;

out vec4 frag_color;

void main() {
    vec3 col = texture(tex, uv).xyz;
    frag_color = vec4(col, 1.0);
}
@end

/* quad shader program */
@program shader vs fs

