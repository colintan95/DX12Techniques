#ifndef APP_H_
#define APP_H_

#include <d3d12.h>
#include <dxgi1_6.h>
#include <wrl/client.h>

#include <memory>
#include <vector>

#include "d3dx12.h"
#include "DirectXMath.h"

// TODO: See if this can be removed. Currently needed so that "Model.h" doesn't error out.
#include <stdexcept>

#include "GraphicsMemory.h"
#include "Model.h"

#include "constants.h"
#include "geometry_pass.h"
#include "lighting_pass.h"
#include "shadow_pass.h"

struct Material {
  DirectX::XMFLOAT4 ambient_color;
  DirectX::XMFLOAT4 diffuse_color;
};

class App {
public:
  App(HWND window_hwnd, int window_width, int window_height);

  void Initialize();

  void Cleanup();

  void RenderFrame();

private:
  friend class GeometryPass;
  friend class LightingPass;
  friend class ShadowPass;

  void InitDeviceAndSwapChain();

  void InitCommandAllocators();
  void InitFence();

  void InitPipelines();

  void InitDescriptorHeaps();

  void InitResources();
  void CreateSharedBuffers();
  void LoadModelData();
  void InitMatrices();

  void UploadDataToBuffer(const void* data, UINT64 data_size, ID3D12Resource* dst_buffer);

  void MoveToNextFrame();

  void WaitForGpu();

  ShadowPass shadow_pass_;
  GeometryPass geometry_pass_;
  LightingPass lighting_pass_;

  HWND window_hwnd_;
  int window_width_;
  int window_height_;

  int frame_index_ = 0;

  D3D_ROOT_SIGNATURE_VERSION root_signature_version_;

  CD3DX12_VIEWPORT viewport_;
  CD3DX12_RECT scissor_rect_;

  Microsoft::WRL::ComPtr<ID3D12Device> device_;
  Microsoft::WRL::ComPtr<ID3D12CommandQueue> command_queue_;
  Microsoft::WRL::ComPtr<IDXGISwapChain3> swap_chain_;

  Microsoft::WRL::ComPtr<ID3D12GraphicsCommandList> command_list_;

  Microsoft::WRL::ComPtr<ID3D12Fence> fence_;
  UINT64 latest_fence_value_ = 0;
  HANDLE fence_event_;

  Microsoft::WRL::ComPtr<ID3D12DescriptorHeap> rtv_heap_;
  UINT rtv_descriptor_size_ = 0;
  Microsoft::WRL::ComPtr<ID3D12DescriptorHeap> dsv_heap_;
  UINT dsv_descriptor_size_ = 0;
  Microsoft::WRL::ComPtr<ID3D12DescriptorHeap> cbv_srv_heap_;
  UINT cbv_srv_descriptor_size_ = 0;
  Microsoft::WRL::ComPtr<ID3D12DescriptorHeap> sampler_heap_;
  UINT sampler_descriptor_size_ = 0;

  std::vector<Microsoft::WRL::ComPtr<ID3D12Resource>> upload_buffers_;

  Microsoft::WRL::ComPtr<ID3D12Resource> depth_stencil_;

  struct Frame {
    Microsoft::WRL::ComPtr<ID3D12CommandAllocator> command_allocator;

    Microsoft::WRL::ComPtr<ID3D12Resource> swap_chain_buffer;
    Microsoft::WRL::ComPtr<ID3D12Resource> gbuffer;

    Microsoft::WRL::ComPtr<ID3D12Resource> pos_gbuffer;
    Microsoft::WRL::ComPtr<ID3D12Resource> diffuse_gbuffer;
    Microsoft::WRL::ComPtr<ID3D12Resource> normal_gbuffer;

    Microsoft::WRL::ComPtr<ID3D12Resource> shadow_cubemap;

    UINT64 fence_value = 0;
  };

  Frame frames_[kNumFrames];

  std::unique_ptr<DirectX::GraphicsMemory> graphics_memory_;
  std::unique_ptr<DirectX::Model> model_;

  struct DrawCallArgs {
    D3D12_PRIMITIVE_TOPOLOGY primitive_type;
    D3D12_VERTEX_BUFFER_VIEW vertex_buffer_view;
    D3D12_INDEX_BUFFER_VIEW index_buffer_view;

    uint32_t index_count;
    uint32_t start_index;
    int32_t vertex_offset;

    uint32_t material_index;
  };

  float camera_yaw_ = 0.f;
  float camera_pitch_ = 0.f;
  float camera_roll_ = 0.f;

  std::vector<DrawCallArgs> draw_call_args_;

  DirectX::XMFLOAT4X4 world_view_mat_;
  DirectX::XMFLOAT4X4 world_view_proj_mat_;

  DirectX::XMFLOAT4X4 shadow_mats_[6];

  std::vector<Material> materials_;

  DirectX::XMFLOAT4 light_pos_;
  DirectX::XMFLOAT4 light_view_pos_;
};

#endif  // APP_H_