Shader "Hidden/VolumetricFog"
{
    SubShader
    {
        Tags
        { 
            "RenderPipeline" = "UniversalPipeline"
        }

        Pass
        {
            Name "VolumetricFogRender"

            ZTest Always
            ZWrite Off
            Cull Off
            Blend Off

            HLSLPROGRAM

            #include "./VolumetricFog.hlsl"

            #pragma target 4.5

            #pragma multi_compile _ _CLUSTER_LIGHT_LOOP

            #pragma multi_compile _ _MAIN_LIGHT_SHADOWS _MAIN_LIGHT_SHADOWS_CASCADE _MAIN_LIGHT_SHADOWS_SCREEN
            #pragma multi_compile _ _ADDITIONAL_LIGHTS
            #pragma multi_compile _ _ADDITIONAL_LIGHT_SHADOWS
            #pragma multi_compile_fragment _ _LIGHT_COOKIES
            #pragma multi_compile_fragment _ PROBE_VOLUMES_L1 PROBE_VOLUMES_L2

            #pragma multi_compile_local_fragment _ _VOLUME_MODIFIER
            #pragma multi_compile_local_fragment _ _MAIN_LIGHT_CONTRIBUTION
            #pragma multi_compile_local_fragment _ _ADDITIONAL_LIGHTS_CONTRIBUTION
            #pragma multi_compile_local_fragment _ _APV_CONTRIBUTION
            #pragma multi_compile_local_fragment _ _REFLECTION_PROBES_CONTRIBUTION
            #pragma multi_compile_local_fragment _ _NOISE
            #pragma multi_compile_local_fragment _ _NOISE_DISTORTION
            
            #pragma vertex Vert
            #pragma fragment Frag

            float4 Frag(Varyings input) : SV_Target
            {
                UNITY_SETUP_STEREO_EYE_INDEX_POST_VERTEX(input);

                return VolumetricFog(input.texcoord, input.positionCS.xy);
            }

            ENDHLSL
        }

        Pass
        {
            Name "VolumetricFogReprojection"
            
            ZTest Always
            ZWrite Off
            Cull Off
            Blend Off

            HLSLPROGRAM

            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
            #include "Packages/com.unity.render-pipelines.core/Runtime/Utilities/Blit.hlsl"
            #include "./Reprojection.hlsl"

            #pragma target 4.5

            #pragma vertex Vert
            #pragma fragment Frag

            TEXTURE2D_X(_VolumetricFogHistoryTexture);

            float4 Frag(Varyings input) : SV_Target
            {
                UNITY_SETUP_STEREO_EYE_INDEX_POST_VERTEX(input);

                return Reproject(input.texcoord, _BlitTexture, _VolumetricFogHistoryTexture);
            }

            ENDHLSL
        }

        Pass
        {
            Name "VolumetricFogHorizontalBlur"
            
            ZTest Always
            ZWrite Off
            Cull Off
            Blend Off

            HLSLPROGRAM

            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
            #include "Packages/com.unity.render-pipelines.core/Runtime/Utilities/Blit.hlsl"
            #include "./DepthAwareGaussianBlur.hlsl"

            #pragma target 4.5

            #pragma vertex Vert
            #pragma fragment Frag

            float4 Frag(Varyings input) : SV_Target
            {
                UNITY_SETUP_STEREO_EYE_INDEX_POST_VERTEX(input);

                return DepthAwareGaussianBlur(input.texcoord, float2(1.0, 0.0), _BlitTexture, sampler_PointClamp, _BlitTexture_TexelSize.xy);
            }

            ENDHLSL
        }

        Pass
        {
            Name "VolumetricFogVerticalBlur"
            
            ZTest Always
            ZWrite Off
            Cull Off
            Blend Off

            HLSLPROGRAM

            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
            #include "Packages/com.unity.render-pipelines.core/Runtime/Utilities/Blit.hlsl"
            #include "./DepthAwareGaussianBlur.hlsl"

            #pragma target 4.5

            #pragma vertex Vert
            #pragma fragment Frag

            float4 Frag(Varyings input) : SV_Target
            {
                UNITY_SETUP_STEREO_EYE_INDEX_POST_VERTEX(input);

                return DepthAwareGaussianBlur(input.texcoord, float2(0.0, 1.0), _BlitTexture, sampler_PointClamp, _BlitTexture_TexelSize.xy);
            }

            ENDHLSL
        }

        Pass
        {
            Name "VolumetricFogUpsampleComposition"
            
            ZTest Always
            ZWrite Off
            Cull Off
            Blend Off

            HLSLPROGRAM

            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
            #include "Packages/com.unity.render-pipelines.core/Runtime/Utilities/Blit.hlsl"
            #include "./DepthAwareUpsample.hlsl"

            #pragma target 4.5

            #pragma vertex Vert
            #pragma fragment Frag

            #pragma multi_compile_local_fragment _ _DEFERRED_FOG
            #pragma multi_compile_local_fragment _ _DEFERRED_FOG_DEBUG

            TEXTURE2D_X(_VolumetricFogTexture);
            SAMPLER(sampler_BlitTexture);

            float _DeferredFogBaseHeight;
            float _DeferredFogMaximumHeight;
            float _DeferredFogMaxDistance;
            float _DeferredFogStart;
            float _DeferredFogEnd;
            float _DeferredFogDensity;
            float3 _DeferredFogColor;

            float GetDeferredFogHeightDensity(float3 posWS)
            {
                float heightT = saturate((posWS.y - _DeferredFogBaseHeight) / (_DeferredFogMaximumHeight - _DeferredFogBaseHeight));
                heightT= 1.0 - heightT;

                float density = _DeferredFogDensity * heightT;
                return density;
            }

            float4 Frag(Varyings input) : SV_Target
            {
                UNITY_SETUP_STEREO_EYE_INDEX_POST_VERTEX(input);

                // sample depth
                float depth = SampleSceneDepth(input.texcoord);
                float fullResLinearEyeDepth = LinearEyeDepthConsiderProjection(depth);
                
                // get the volumetric fog and get the current camera color
                float4 volumetricFog = DepthAwareUpsample(input.texcoord, _VolumetricFogTexture, fullResLinearEyeDepth);
                float4 cameraColor = SAMPLE_TEXTURE2D_X(_BlitTexture, sampler_BlitTexture, input.texcoord);

                #if _DEFERRED_FOG
                    // clamp depth to a maximum value to avoid extreme fogging at far distances
                    fullResLinearEyeDepth = clamp(fullResLinearEyeDepth, 0.0, _DeferredFogMaxDistance);
                    
                    // get a factor based on height to reduce fog density at higher altitudes
                    float3 posWS = ComputeWorldSpacePosition(input.texcoord, depth, UNITY_MATRIX_I_VP);
                    float density = GetDeferredFogHeightDensity(posWS);

                    // make it exponential but with additional control over falloff
                    //float fog = 1.0 / exp(pow(fullResLinearEyeDepth * density, _DeferredFogPower));

                    // make fog linear, gives better control given our camera angle
                    float fog = saturate((_DeferredFogEnd - fullResLinearEyeDepth) / (_DeferredFogEnd - _DeferredFogStart));
                    fog = 1.0 - fog;
                    fog *= density;

                    // debug deferred fog
                    #if _DEFERRED_FOG_DEBUG
                        return float4(fog.xxx * _DeferredFogColor.rgb, 1.0);
                    #endif

                    // apply deferred fog to the camera color before combining with volumetric fog, which should be applied later
                    cameraColor.rgb = lerp(cameraColor.rgb, _DeferredFogColor, fog);
                #endif

                return float4(cameraColor.rgb * volumetricFog.a + volumetricFog.rgb, cameraColor.a);
            }

            ENDHLSL
        }
    }

    Fallback Off
}