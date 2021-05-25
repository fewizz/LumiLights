#include frex:shaders/api/world.glsl

/*******************************************************
 *  lumi:shaders/lib/taa_jitter.glsl                   *
 *******************************************************/

const vec2 halton[4] = vec2[4](
    vec2(0.5, 0.3333333333333333),
    vec2(0.25, 0.6666666666666666),
    vec2(0.75, 0.1111111111111111),
    vec2(0.125, 0.4444444444444444)
    // vec2(0.625, 0.7777777777777777),
    // vec2(0.375, 0.2222222222222222),
    // vec2(0.875, 0.5555555555555556),
    // vec2(0.0625, 0.8888888888888888),
    // vec2(0.5625, 0.037037037037037035),
    // vec2(0.3125, 0.37037037037037035),
    // vec2(0.8125, 0.7037037037037037),
    // vec2(0.1875, 0.14814814814814814),
    // vec2(0.6875, 0.48148148148148145),
    // vec2(0.4375, 0.8148148148148147),
    // vec2(0.9375, 0.25925925925925924),
    // vec2(0.03125, 0.5925925925925926)
    );

vec2 taa_jitter(vec2 rcpSize) {
    return halton[frx_renderFrames() % 4u] * rcpSize;
}
