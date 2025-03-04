#include frex:shaders/lib/noise/cellular2x2x2.glsl
#include frex:shaders/lib/noise/noise3d.glsl
#include lumi:shaders/common/atmosphere.glsl
#include lumi:shaders/lib/rectangle.glsl
#include lumi:shaders/prog/celest.glsl
#include lumi:shaders/prog/fog.glsl
#include lumi:shaders/prog/shading.glsl

/*******************************************************
 *  lumi:shaders/prog/sky.glsl
 *******************************************************/

l2_vary mat4 v_star_rotator;
l2_vary float v_not_in_void;
l2_vary float v_near_void_core;
l2_vary float v_cameraAt;

#ifdef VERTEX_SHADER

void skySetup()
{
	v_star_rotator = l2_rotationMatrix(vec3(1.0, 0.0, 1.0), frx_worldTime * PI);
	v_not_in_void	 = l2_clampScale(-65.0, -64.0, frx_cameraPos.y);
	v_near_void_core = l2_clampScale(-64.0, -128.0, frx_cameraPos.y);

	float rdMult = min(1.0, frx_viewDistance / 512.0);
	v_cameraAt = mix(0.0, -0.75, l2_clampScale(64.0 + 256.0 * rdMult, 256.0 + 256.0 * rdMult, frx_cameraPos.y));
}

#else

const vec3 VOID_CORE_COLOR = hdr_fromGamma(vec3(1.0, 0.7, 0.5));

vec4 celestFrag(in Rect celestRect, sampler2D ssun, sampler2D smoon, vec3 worldVec)
{
	if (dot(worldVec, frx_skyLightVector) < 0.) return vec4(0.); // no more both at opposites, sorry

	vec2 celestUV  = rect_innerUV(celestRect, worldVec * 1024.);
	vec3 celestCol = vec3(0.0);
	vec3 celestTex = vec3(0.0);
	float opacity  = 0.0;

	bool isMoon = frx_worldIsMoonlit == 1;

	if (celestUV == clamp(celestUV, 0.0, 1.0)) {
		if (isMoon){
			vec2 moonUv = clamp(celestUV, 0.25, 0.75);

			if (celestUV == moonUv) {
				celestUV = 2.0 * moonUv - 0.5;
				vec2 fullMoonUV	   = celestUV * vec2(0.25, 0.5);
				vec3 fullMoonColor = texture(smoon, fullMoonUV).rgb;

				opacity = l2_max3(fullMoonColor);
				opacity = min(1.0, opacity * 3.0);

				celestUV.x *= 0.25;
				celestUV.y *= 0.5;
				celestUV.x += mod(frx_worldDay, 4.) * 0.25;
				celestUV.y += (mod(frx_worldDay, 8.) >= 4.) ? 0.5 : 0.0;

				celestTex = hdr_fromGamma(texture(smoon, celestUV).rgb);
				celestCol = celestTex + vec3(0.001) * hdr_fromGamma(fullMoonColor);
				celestCol *= frx_skyLightTransitionFactor;
			}
		} else {
			celestTex = texture(ssun, celestUV).rgb;
			celestCol = hdr_fromGamma(celestTex) * atmosv_CelestialRadiance;
		}

		opacity = max(opacity, frx_luminance(clamp(celestTex, 0.0, 1.0)));
	}

	return vec4(celestCol, opacity);
}

vec4 skyBase(vec3 toSky, vec3 fallback, bool isUnderwater) {
	vec4 result = vec4(0.0, 0.0, 0.0, 1.0);
	if (frx_worldIsOverworld == 1) {
		#if SKY_MODE == SKY_MODE_LUMI
		result.rgb  = atmosv_SkyRadiance;
		#else
		float mul = 1.0 + frx_worldIsMoonlit * frx_skyLightTransitionFactor;
		vec3 fallback1 = hdr_fromGamma(fallback) * mul;
		result.rgb = fog(vec4(fallback1, 1.0), frx_viewDistance * 4.0, toSky, false).rgb;
		#endif

		result.rgb += vec3(frx_skyFlashStrength * LIGHTNING_FLASH_STR);

		float skyGradient = pow(l2_clampScale(0.625 + v_cameraAt, -0.125 + v_cameraAt, toSky.y), 3.0);
		result.rgb = mix(result.rgb, fogColor(false, toSky), skyGradient);
	}

	if (frx_worldIsEnd == 1){
		vec3 mov = vec3(0.0, 0.0, frx_renderSeconds * 2.0);
		float g = (snoise(toSky * 2.0 + snoise(toSky * 10.0 + mov) * 0.1 + mov * 0.05)) * 0.5 + 0.5;
		// float h = (snoise(toSky * 2.0 + snoise((v_star_rotator * vec4(toSky, 0.0)).xyz * 10.0 + mov) * 0.1 + mov * 0.05)) * 0.5 + 0.5;
		// vec3 norm = normalize(vec3(dFdx(g), dFdy(g), 0.0));
		// float sup = 1.0 + pow(dot(norm, vec3(0.0, 1.0, 0.0)) * 0.5 + 0.5, 5.0);
		// result.rgb *= 1.0 - clamp(g, 0.0, 1.0);
		result.rgb += 0.08 * atmosv_FogRadiance * g;// * sup;
		// result.rgb += 0.05 * atmosv_FogRadiance * h;
	
		result.rgb *= l2_clampScale(0.0, l2_clampScale(128.0, 10.0, frx_cameraPos.y), toSky.y * 0.5 + 0.5);
	}

	if (frx_worldIsOverworld + frx_worldIsEnd < 1) {
		result.rgb = hdr_fromGamma(fallback) * (1.0 + float(frx_worldIsEnd) * 1.0);
	}
	
	if (isUnderwater) {
		result.rgb = atmosv_WaterFogRadiance;
	} else if (frx_worldIsNether == 1) {
		result.rgb = atmosv_FogRadiance;
	}

	return result;
}

vec4 voidCore(vec4 result, vec3 toSky) {
	if (frx_worldIsOverworld == 1) {
		// VOID CORE
		float voidCore = l2_clampScale(-0.8 + v_near_void_core, -1.0 + v_near_void_core, toSky.y); 
		vec3 voidColor = mix(vec3(0.0), VOID_CORE_COLOR, voidCore);

		result.rgb = mix(voidColor, result.rgb, v_not_in_void);
	}

	return result;
}

vec4 basicSky(vec3 toSky, vec3 fallback, bool isUnderwater) {
	return voidCore(skyBase(toSky, fallback, isUnderwater), toSky);
}

vec4 customSky(vec4 result, sampler2D sunTexture, sampler2D moonTexture, vec3 toSky, vec3 fallback, bool isUnderwater, float skyVisible, float celestVisible) {
	float starEraser = 0.0;

	if (frx_worldIsOverworld == 1 && !isUnderwater) {
		// Sky, sun and moon
		#if SKY_MODE == SKY_MODE_LUMI
		vec4 celestColor = celestFrag(Rect(v_celest1, v_celest2, v_celest3), sunTexture, moonTexture, toSky);
		starEraser = celestColor.a;

		result.rgb += pow(max(0.0, dot(toSky, frx_skyLightVector)), 100.0) * atmosv_CelestialRadiance * exp(-lightLuminance(atmosv_CelestialRadiance)) * 0.1 * (1. - frx_rainGradient) * celestVisible; // halo?
		result.rgb += celestColor.rgb * (1. - frx_rainGradient) * celestVisible;
		#endif
	}

	if (frx_worldIsOverworld + frx_worldIsEnd > 0 && !isUnderwater) {
		#if SKY_MODE == SKY_MODE_LUMI || SKY_MODE == SKY_MODE_VANILLA_STARRY
		// Stars
		const vec3 NON_MILKY_AXIS = vec3(-0.598964, 0.531492, 0.598964);

		float starGate = max(float(frx_worldIsEnd), max(frx_worldIsMoonlit, 1.0 - frx_skyLightTransitionFactor));
		float starry = pow(starGate, 10.0);
			 starry *= l2_clampScale(-0.6, -0.5, toSky.y); //prevent star near the void core

		float milkyness   = l2_clampScale(0.7, 0.0, abs(dot(NON_MILKY_AXIS, toSky.xyz))) * float(frx_worldIsOverworld);
		float rainOcclude = (1.0 - frx_rainGradient);
		vec4  starVec     = v_star_rotator * vec4(toSky, 0.0);
		float milkyHaze   = starry * rainOcclude * milkyness * 0.4 * l2_clampScale(-1.0, 1.0, snoise(starVec.xyz * 2.0));
		float starNoise   = cellular2x2x2(starVec.xyz * mix(20 + LUMI_STAR_DENSITY, 40 + LUMI_STAR_DENSITY, milkyness)).x;
		float star        = starry * l2_clampScale(0.025 + 0.005 * (LUMI_STAR_SIZE + frx_worldIsEnd * 10.0) + milkyness * milkyness * 0.1, 0.0, starNoise);

		star = l2_clampScale(0.0, 1.0 - 0.6, star) * rainOcclude;

		#if SKY_MODE == SKY_MODE_LUMI
		star -= star * starEraser;

		milkyHaze -= milkyHaze * starEraser;
		milkyHaze *= milkyHaze;
		#endif

		vec3 starColor = mix(vec3(LUMI_STAR_BRIGHTNESS), atmosv_FogRadiance, frx_worldIsEnd);
		vec3 starRadiance = vec3(star) * EMISSIVE_LIGHT_STR * 0.05 * starColor + NEBULAE_COLOR * milkyHaze;

		result.rgb += starRadiance * skyVisible;
		#endif
	}

	return voidCore(result, toSky);
}

vec4 customSky(vec4 result, sampler2D sunTexture, sampler2D moonTexture, vec3 toSky, vec3 fallback, bool isUnderwater) {
	return customSky(result, sunTexture, moonTexture, toSky, fallback, isUnderwater, 1.0, 1.0);
}

vec3 skyRadiance(sampler2D sunTexture, sampler2D moonTexture, vec2 material, vec3 toSky, vec2 lightyw) {
	float skyVisible = lightmapRemap(lightyw.x);

	if (material.x > REFLECTION_MAXIMUM_ROUGHNESS) {
		return atmosv_SkyRadiance * skyVisible;
	} else {
		bool isUnderwater = frx_cameraInWater == 1 && toSky.y < 0.0;
		vec4 base = skyBase(toSky, vec3(0.0), isUnderwater) * skyVisible;
		return customSky(base, sunTexture, moonTexture, toSky, vec3(0.0), isUnderwater, skyVisible, lightyw.y).rgb;
	}
}

#define skyReflectionFac(march) smoothstep(-0.1, 0.1, march.y)

vec4 skyReflection(sampler2D sunTexture, sampler2D moonTexture, sampler2D noiseTexture, vec3 albedo, vec2 material, vec3 toFrag, vec3 normal, vec2 lightyw) {
	vec3 toSky = reflectRough(noiseTexture, toFrag, normal, material.x);
	vec3 radiance = skyRadiance(sunTexture, moonTexture, material, toSky, lightyw);
	return vec4(reflectionPbr(albedo, material, radiance, toSky, -toFrag), 0.0) * skyReflectionFac(toSky);
}

#endif
