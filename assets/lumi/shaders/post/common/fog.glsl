#include lumi:shaders/common/atmosphere.glsl
#include lumi:shaders/common/userconfig.glsl

/*******************************************************
 *  lumi:shaders/post/common/fog.glsl
 *******************************************************
 *  Copyright (c) 2020-2021 spiralhalo
 *  Released WITHOUT WARRANTY under the terms of the
 *  GNU Lesser General Public License version 3 as
 *  published by the Free Software Foundation, Inc.
 *******************************************************/

// #define FOG_NOISE_SCALE 0.125
// #define FOG_NOISE_SPEED 0.25
// #define FOG_NOISE_HEIGHT 4.0

const float FOG_FAR				   = FOG_FAR_CHUNKS * 16.0;
const float FOG_DENSITY			   = FOG_DENSITY_RELATIVE / 20.0;
const float UNDERWATER_FOG_FAR	   = UNDERWATER_FOG_FAR_CHUNKS * 16.0;
const float UNDERWATER_FOG_DENSITY = UNDERWATER_FOG_DENSITY_RELATIVE / 20.0;

vec4 fog(float skyLight, float ec, float vblindness, vec4 a, vec3 modelPos, inout float bloom)
{
	float pFogDensity = frx_cameraInFluid == 1 ? UNDERWATER_FOG_DENSITY : FOG_DENSITY;
	float pFogFar     = frx_cameraInFluid == 1 ? UNDERWATER_FOG_FAR     : FOG_FAR;

	pFogFar = min(frx_viewDistance, pFogFar); // clamp to render distance

	// float fog_noise = snoise(worldPos.xz * FOG_NOISE_SCALE + frx_renderSeconds * FOG_NOISE_SPEED) * FOG_NOISE_HEIGHT;

	if (frx_cameraInFluid == 0 && frx_worldHasSkylight == 1) {
		float inverseThickener = 1.0;

		inverseThickener -= 0.5 * inverseThickener * frx_rainGradient;
		inverseThickener -= 0.5 * inverseThickener * frx_thunderGradient;

		pFogFar *= inverseThickener;
		pFogDensity = mix(min(1.0, pFogDensity * 2.0), min(0.8, pFogDensity), inverseThickener);
	}

	float fogFactor = pFogDensity;

	if (frx_effectBlindness == 1) {
		pFogFar   = mix(pFogFar, 3.0, vblindness);
		fogFactor = mix(fogFactor, 1.0, vblindness);
	}

	if (frx_cameraInLava == 1) {
		pFogFar   = float(frx_effectFireResistance) * 2.0 + 0.5;
		fogFactor = 1.0;
	}

	float distToCamera = length(modelPos);
	float distFactor   = min(1.0, distToCamera / pFogFar);

	fogFactor = clamp(fogFactor * distFactor, 0.0, 1.0);

	float aboveGround	 = l2_clampScale(0.0, 0.2, max(skyLight, frx_eyeBrightness.y));
	vec3  worldVec		 = normalize(modelPos);
	vec3  fogColor		 = mix(atmos_hdrCaveFogRadiance(), atmos_hdrFogColorRadiance(worldVec), aboveGround);
	float smoothSkyBlend = frx_cameraInFluid == 1 ? 0.0 : min(distToCamera, frx_viewDistance) / frx_viewDistance * aboveGround;
	vec3  worldVecMod	 = worldVec;
		  worldVecMod.y	 = mix(1.0, worldVecMod.y, pow(smoothSkyBlend, 0.3));
		  fogColor		 = mix(fogColor, atmos_hdrSkyGradientRadiance(worldVecMod), smoothSkyBlend);

	vec4 blended;

	// NB: additive fog blending looks bad in this setup. don't use.
	blended = mix(a, vec4(fogColor, 1.0), fogFactor);
	bloom  *= l2_clampScale(0.5, 0.1, fogFactor);

	return blended;
}
