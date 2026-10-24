shader_type canvas_item;
uniform vec4 ink:source_color=vec4(0.52,0.69,1.0,1.0);
void fragment(){
	vec4 source=texture(TEXTURE,UV);
	float line=dot(source.rgb,vec3(0.2126,0.7152,0.0722));
	// Preserve subpixel contour strokes after the portrait is reduced to a small CRT.
	float alpha=smoothstep(0.005,0.16,line)*source.a;
	COLOR=vec4(ink.rgb,ink.a*alpha);
}
