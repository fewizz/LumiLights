#include lumi:shaders/prog/fog.glsl
#include lumi:shaders/prog/shading.glsl
#include lumi:shaders/prog/sky.glsl

/*******************************************************
 *  lumi:shaders/prog/reflection.glsl
 *******************************************************/

const float HITBOX = 0.125;
const int MAXSTEPS = 30;
const int PERIOD = 2;
const int REFINE = 8;

void clipSides(inout vec3 end, in vec3 start)
{
	float delta, param = 1.0;

	if (end.z > 1.0) {
		delta = end.z - start.z;
		param = min(param, (1.0 - start.z) / delta);
	}

	if (end.y < 0.0) {
		delta = end.y - start.y;
		param = min(param, (0.0 - start.y) / delta);
	} else if (end.y > 1.0) {
		delta = end.y - start.y;
		param = min(param, (1.0 - start.y) / delta);
	}

	if (end.x < 0.0) {
		delta = end.x - start.x;
		param = min(param, (0.0 - start.x) / delta);
	} else if (end.x > 1.0) {
		delta = end.x - start.x;
		param = min(param, (1.0 - start.x) / delta);
	}

	end = start + (end - start) * param;
}

vec3 clipNear(vec3 end, vec3 start, float nearZ)
{
	if (end.z > nearZ) {
		float delta = end.z - start.z;
		float param = (nearZ - start.z) / delta;
		return start + (end - start) * clamp(param, 0.0, 1.0);
	}

	return end;
}

vec3 reflectionMarch_v2(sampler2D depthBuffer, sampler2DArray lightNormalBuffer, float idNormal, vec3 viewStartPos, vec3 viewMarch, float nearZ)
{
	// padding to prevent back face reflection. we want the divisor to be as small as possible.
	// too small with cause distortion of reflection near the reflector
	float padding = -viewStartPos.z / 12.;
	viewStartPos = viewStartPos + viewMarch * padding;

	vec4 temp = frx_projectionMatrix * vec4(viewStartPos, 1.0);
	vec3 uvStartPos = temp.xyz / temp.w * 0.5 + 0.5;

	float maxTravel = frx_viewDistance;

	vec3 viewEndPos = viewStartPos + maxTravel * viewMarch;
	viewEndPos = clipNear(viewEndPos, viewStartPos, nearZ * 30.); // no question
	temp = frx_projectionMatrix * vec4(viewEndPos, 1.0);
	vec3 uvEndPos = temp.xyz / temp.w * 0.5 + 0.5;

	clipSides(uvEndPos, uvStartPos);

	vec3 uvMarch = (uvEndPos - uvStartPos) / float(MAXSTEPS);
	vec3 uvRayPos = uvStartPos;

	// best thickness for reflecting extreme angles
	const float thickness = 0.0064; // 0.0004 // old option

	float marchSign = sign(uvMarch.z);
	float lastZ = texture(depthBuffer, v_texcoord).r - 0.0016 * marchSign;

	float sampledZ;
	float hit = 0.0;
	float dZ;
	int steps;

	for (steps=0; steps < MAXSTEPS && hit < 1.0; steps++) {
		uvRayPos = uvRayPos + uvMarch;
		sampledZ = texture(depthBuffer, uvRayPos.xy).r;
		dZ = uvRayPos.z - sampledZ;

		bool edge = marchSign * (sampledZ - lastZ) > 0.0;

		if (dZ > 0 && edge) {
			hit = 1.0;	
		}
	}

	uvMarch *= -1.0 / float(REFINE);

	for (int i=0; i<REFINE && hit == 1.0; i++) {
		vec3 uvNextPos = uvRayPos + uvMarch;
		float nextZ = texture(depthBuffer, uvNextPos.xy).r;
		float nextdZ = uvNextPos.z - nextZ;

		if (nextdZ < 0 || abs(nextdZ) > abs(dZ)) break;

		dZ = nextdZ;
		sampledZ = nextZ;
		uvRayPos = uvNextPos;
	}

	return vec3(uvRayPos.xy, hit);
}

const float JITTER_STRENGTH = 0.6;

vec4 reflection(vec3 albedo, sampler2D colorBuffer, sampler2DArray mainEtcBuffer, sampler2DArray lightNormalBuffer, sampler2D depthBuffer, sampler2DArrayShadow shadowMap, sampler2D sunTexture, sampler2D moonTexture, sampler2D noiseTexture, float idLight, float idMaterial, float idNormal, float idMicroNormal)
{
	vec3 rawMat = texture(mainEtcBuffer, vec3(v_texcoord, idMaterial)).xyz;

	bool isUnmanaged = rawMat.x == 0.0; // unmanaged draw

	if (isUnmanaged) return vec4(0.0);

	vec4 light	= texture(lightNormalBuffer, vec3(v_texcoord, idLight));
	vec3 normal	= texture(lightNormalBuffer, vec3(v_texcoord, idMicroNormal)).xyz * 2.0 - 1.0;
	float depth	= texture(depthBuffer, v_texcoord).r;

	vec4 tempPos = frx_inverseViewProjectionMatrix * vec4(2.0 * v_texcoord - 1.0, 2.0 * depth - 1.0, 1.0);
	vec3 eyePos  = tempPos.xyz / tempPos.w;
	light.w = denoisedShadowFactor(shadowMap, v_texcoord, eyePos, depth, light.y);

	vec3 viewPos = (frx_viewMatrix * vec4(eyePos, 1.0)).xyz;
	float roughness = rawMat.x;

	// TODO: rain puddles?

	vec3 jitterPrc;

	// view bobbing shaking reduction, thanks to fewizz
	vec4 nearPos	= frx_inverseProjectionMatrix * vec4(v_texcoord * 2.0 - 1.0, -1.0, 1.0); nearPos.xyz /= nearPos.w;
	vec3 viewToEye  = normalize(-viewPos + nearPos.xyz);
	vec3 viewToFrag = -viewToEye;
	vec3 viewNormal = frx_normalModelMatrix * normal;
	vec3 viewMarch  = reflectRough(noiseTexture, viewToFrag, viewNormal, roughness, jitterPrc);

	#ifdef SS_REFLECTION
	vec4 objLight = vec4(0.0);
	if (roughness <= REFLECTION_MAXIMUM_ROUGHNESS) {
		// Impossible Ray Resultion:
		vec3 rawNormal = texture(lightNormalBuffer, vec3(v_texcoord, idNormal)).xyz * 2.0 - 1.0;
		vec3 rawViewNormal = frx_normalModelMatrix * rawNormal;
		bool impossibleRay	= dot(rawViewNormal, viewMarch) < 0;

		if (impossibleRay) {
			normal = rawNormal;
			viewNormal = rawViewNormal;
			viewMarch = normalize(reflect(viewToFrag, viewNormal) + jitterPrc);
		}

		vec3 result = reflectionMarch_v2(depthBuffer, lightNormalBuffer, idNormal, viewPos, viewMarch, nearPos.z);

		vec2 uvFade = smoothstep(0.5, 0.475 + l2_clampScale(0.1, 0.0, rawViewNormal.z) * 0.024, abs(result.xy - 0.5));
		result.z *= min(uvFade.x, uvFade.y);

		vec4 reflectedPos = frx_inverseViewProjectionMatrix * vec4(result.xy * 2.0 - 1.0, texture(depthBuffer, result.xy).r * 2.0 - 1.0, 1.0);
		float distanceFade = fogFactor(length(reflectedPos.xyz / reflectedPos.w), frx_cameraInFluid == 1);

		result.z *= 1.0 - pow(distanceFade, 3.0);

		vec4 reflectedColor = texture(colorBuffer, result.xy);

		objLight = vec4(reflectionPbr(albedo, rawMat.xy, reflectedColor.rgb, viewMarch, viewToEye).rgb, result.z);
	}
	#else
	const vec4 objLight = vec4(0.0);
	#endif

	vec3 skyLight = skyReflection(sunTexture, moonTexture, albedo, rawMat.xy, viewToFrag * frx_normalModelMatrix, viewMarch * frx_normalModelMatrix, normal, light.yw).rgb;

	vec3 reflectedLight = skyLight * (1.0 - objLight.a) * smoothstep(0.0, 1.0, viewNormal.y) + objLight.rgb * objLight.a;

	return vec4(reflectedLight, 0.0);
}
