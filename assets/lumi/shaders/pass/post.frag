#include lumi:shaders/pass/header.glsl

#include lumi:shaders/prog/clouds.glsl
#include lumi:shaders/prog/fog.glsl
#include lumi:shaders/prog/reflection.glsl
#include lumi:shaders/prog/tonemap.glsl

/*******************************************************
 *  lumi:shaders/post/post.frag
 *******************************************************/

uniform sampler2D u_color;
uniform sampler2D u_albedo;
uniform sampler2D u_depth;

uniform sampler2DArray u_gbuffer_main_etc;
uniform sampler2DArray u_gbuffer_normal;
uniform sampler2DArrayShadow u_gbuffer_shadow;

uniform sampler2D u_tex_sun;
uniform sampler2D u_tex_moon;
uniform sampler2D u_tex_cloud;
uniform sampler2D u_tex_noise;

out vec4 fragColor;

void main()
{
	fragColor = texture(u_color, v_texcoord);

	vec4 albedo = texture(u_albedo, v_texcoord);

	float idLight = albedo.a == 0.0 ? ID_SOLID_LIGT : (albedo.a < 1.0 ? ID_TRANS_LIGT : ID_PARTS_LIGT);
	float idMaterial = albedo.a == 0.0 ? ID_SOLID_MATS : ID_TRANS_MATS;
	float idNormal = albedo.a == 0.0 ? ID_SOLID_NORM : ID_TRANS_NORM;
	float idMicroNormal = albedo.a == 0.0 ? ID_SOLID_MNORM : ID_TRANS_MNORM;

	float lighty = texture(u_gbuffer_main_etc, vec3(v_texcoord, idLight)).y;
	float dMin   = texture(u_depth, v_texcoord).r;

	vec4 tempPos = frx_inverseViewProjectionMatrix * vec4(2.0 * v_texcoord - 1.0, 2.0 * dMin - 1.0, 1.0);
	vec3 eyePos  = tempPos.xyz / tempPos.w;

	fragColor += reflection(albedo.rgb, u_color, u_gbuffer_main_etc, u_gbuffer_normal, u_depth, u_gbuffer_shadow, u_tex_sun, u_tex_moon, u_tex_noise, idLight, idMaterial, idNormal, idMicroNormal, eyePos);
	fragColor = fog(fragColor, eyePos, lighty);

	vec4 clouds = volumetricCloud(u_tex_cloud, u_tex_noise, dMin, v_texcoord, eyePos, normalize(eyePos), NUM_SAMPLE);
	fragColor.rgb = fragColor.rgb * (1.0 - clouds.a) + clouds.rgb * clouds.a;

	fragColor = ldr_tonemap(fragColor);
}
