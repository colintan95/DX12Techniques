#include "raytracing_shader.h"

struct Material {
  float4 AmbientColor;
  float4 DiffuseColor;
};

struct ClosestHitConstants {
  uint MaterialIndex;
  uint BaseIbIndex;
};

struct Vertex {
  float3 Position;
  float3 Normal;
};

typedef BuiltInTriangleIntersectionAttributes IntersectAttributes;

struct RayPayload {
  float4 Color;
};

struct ShadowRayPayload {
  bool IsOccluded;
};

// Global descriptors.

RaytracingAccelerationStructure s_scene : register(t0);
RWTexture2D<float4> s_raytracingOutput : register(u0);

ByteAddressBuffer s_indexBuffer : register(t1);
StructuredBuffer<Vertex> s_vertexBuffer : register(t2);
StructuredBuffer<Material> s_materials : register(t3);

// Ray generation descriptors.

ConstantBuffer<RayGenConstantBuffer> s_rayGenConstants : register(b0);

// Closest hit descriptors.

ConstantBuffer<ClosestHitConstants> s_closestHitConstants : register(b1);

[shader("raygeneration")]
void RaygenShader() {
  float2 lerpValues = (float2)DispatchRaysIndex() / (float2)DispatchRaysDimensions();

  float viewportX = lerp(s_rayGenConstants.Viewport.Left, s_rayGenConstants.Viewport.Right,
                          lerpValues.x);
  float viewportY = lerp(s_rayGenConstants.Viewport.Top, s_rayGenConstants.Viewport.Bottom,
                          lerpValues.y);

  RayDesc ray;
  ray.Origin = float3(0, 1, 4.f);
  ray.Direction = float3(viewportX * 0.414f, viewportY * 0.414f, -1.f);
  ray.TMin = 0.0;
  ray.TMax = 10000.0;
  RayPayload payload = { float4(0, 0, 0, 0) };

  TraceRay(s_scene, RAY_FLAG_CULL_BACK_FACING_TRIANGLES, ~0, 0, 1, 0, ray, payload);

  s_raytracingOutput[DispatchRaysIndex().xy] = payload.Color;
}

// Taken from Microsoft sample.
uint3 Load3x16BitIndices(uint offsetBytes)
{
  uint3 indices;

  // ByteAdressBuffer loads must be aligned at a 4 byte boundary.
  // Since we need to read three 16 bit indices: { 0, 1, 2 }
  // aligned at a 4 byte boundary as: { 0 1 } { 2 0 } { 1 2 } { 0 1 } ...
  // we will load 8 bytes (~ 4 indices { a b | c d }) to handle two possible index triplet layouts,
  // based on first index's offsetBytes being aligned at the 4 byte boundary or not:
  //  Aligned:     { 0 1 | 2 - }
  //  Not aligned: { - 0 | 1 2 }
  const uint dwordAlignedOffset = offsetBytes & ~3;
  const uint2 four16BitIndices = s_indexBuffer.Load2(dwordAlignedOffset);

  // Aligned: { 0 1 | 2 - } => retrieve first three 16bit indices
  if (dwordAlignedOffset == offsetBytes)
  {
    indices.x = four16BitIndices.x & 0xffff;
    indices.y = (four16BitIndices.x >> 16) & 0xffff;
    indices.z = four16BitIndices.y & 0xffff;
  }
  else // Not aligned: { - 0 | 1 2 } => retrieve last three 16bit indices
  {
    indices.x = (four16BitIndices.x >> 16) & 0xffff;
    indices.y = four16BitIndices.y & 0xffff;
    indices.z = (four16BitIndices.y >> 16) & 0xffff;
  }

  return indices;
}

// Taken from Microsoft sample.
float3 HitAttribute(float3 vertexAttribute[3], IntersectAttributes attr)
{
  return vertexAttribute[0] +
    attr.barycentrics.x * (vertexAttribute[1] - vertexAttribute[0]) +
    attr.barycentrics.y * (vertexAttribute[2] - vertexAttribute[0]);
}

[shader("closesthit")]
void ClosestHitShader(inout RayPayload payload, IntersectAttributes intersectAttr) {
  float3 barycentrics = float3(1 - intersectAttr.barycentrics.x - intersectAttr.barycentrics.y,
                                intersectAttr.barycentrics.x, intersectAttr.barycentrics.y);

  // Stride of indices in triangle is index size in bytes * indices per triangle => 2 * 3 = 6.
  uint ibIndexBytes = PrimitiveIndex() * 6 + s_closestHitConstants.BaseIbIndex * 2;

  const uint3 indices = Load3x16BitIndices(ibIndexBytes);

  float3 triangleNormals[3] = {
    s_vertexBuffer[indices[0]].Normal,
    s_vertexBuffer[indices[1]].Normal,
    s_vertexBuffer[indices[2]].Normal
  };

  float3 normal = normalize(HitAttribute(triangleNormals, intersectAttr));

  float3 hitPos = WorldRayOrigin() + RayTCurrent() * WorldRayDirection();

  float3 lightPos = float3(0.0, 1.9, 0.0);
  float3 lightDistVec = lightPos - hitPos;
  float3 lightDir = normalize(lightDistVec);

  Material mtl = s_materials[s_closestHitConstants.MaterialIndex];

  float3 ambient = mtl.AmbientColor.rgb;
  float3 diffuse = clamp(dot(lightDir, normal), 0.0, 1.0) * mtl.DiffuseColor.rgb;

  RayDesc shadowRay;
  shadowRay.Origin = hitPos;
  shadowRay.Direction = lightDir;
  shadowRay.TMin = 0.0;
  shadowRay.TMax = length(lightDistVec);
  ShadowRayPayload shadowPayload = { true };

  TraceRay(s_scene,
            RAY_FLAG_CULL_BACK_FACING_TRIANGLES | RAY_FLAG_ACCEPT_FIRST_HIT_AND_END_SEARCH |
            RAY_FLAG_FORCE_OPAQUE | RAY_FLAG_SKIP_CLOSEST_HIT_SHADER, ~0, 0, 1, 1, shadowRay,
            shadowPayload);

  // float isIlluminated = shadowPayload.ShadowHitDist > length(lightDistVec) ? 1.0 : 0.0;
  float isIlluminated = shadowPayload.IsOccluded ? 0.0 : 1.0;

  payload.Color = float4(0.3 * ambient + isIlluminated * diffuse, 1);
}

[shader("miss")]
void MissShader(inout RayPayload payload) {
  payload.Color = float4(0, 0, 0, 1);
}

[shader("miss")]
void ShadowMissShader(inout ShadowRayPayload payload) {
  payload.IsOccluded = false;
}