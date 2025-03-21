#version 330 core
out vec4 FragColor;

in vec2 TexCoord;

// texture samplers
uniform sampler2D texture1;

void main()
{
	// linearly interpolate between both textures (80% container, 20% awesomeface)
	//vec4 col = mix(texture(texture1, TexCoord), texture(texture2, TexCoord), 0.2);
    //FragColor = mix(col, vec4(cos(TexCoord.x), TexCoord.y, sin(TexCoord.x), 1.0), 0.7);
    FragColor = texture(texture1, TexCoord);
}