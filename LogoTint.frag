#version 440

// Mask-style logo tint: keep the artwork's alpha, paint it the theme color.

layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 0) out vec4 fragColor;

layout(binding = 1) uniform sampler2D source;
layout(std140, binding = 0) uniform buf {
    vec4 tint;
};

void main() {
  vec4 c = texture(source, qt_TexCoord0);
  float a = c.a * tint.a;
  fragColor = vec4(tint.rgb * a, a);
}
