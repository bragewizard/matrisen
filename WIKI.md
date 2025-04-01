# Mini-Wiki: GPU Vector Graphics & Vulkan Buffer Management

## Buffer Uploads: Getting Data to the GPU

To make data accessible to GPU shaders, you need to upload it into `VkBuffer` objects. Efficient
uploading, especially to high-performance `GPU_ONLY` memory, requires **staging buffers**.

- **GPU Memory Types (VMA Perspective):**

  - `VMA_MEMORY_USAGE_GPU_ONLY`: Fastest memory for GPU access. Cannot be directly mapped (written
    to) by the CPU. Ideal for vertex/index buffers, SSBOs, textures that don't change often.
  - `VMA_MEMORY_USAGE_CPU_ONLY`: Memory easily accessible by the CPU (mappable). Slower for the GPU
    to access directly. Good for staging uploads.
  - `VMA_MEMORY_USAGE_CPU_TO_GPU`: Mappable by CPU, reasonably fast for GPU. Good for staging or
    buffers updated frequently by the CPU. Often uses PCI-E BAR memory.
  - `VMA_MEMORY_USAGE_GPU_TO_CPU`: Mappable by CPU, intended for reading data *back* from the GPU.

- **Why Staging Buffers?** You cannot write directly into `GPU_ONLY` memory from the CPU. The
  standard method is:

  1. Create the final **destination buffer** on the GPU (`GPU_ONLY`,
     `VK_BUFFER_USAGE_TRANSFER_DST_BIT`).
  1. Create a temporary **staging buffer** accessible by the CPU (`CPU_ONLY` or `CPU_TO_GPU`,
     `VK_BUFFER_USAGE_TRANSFER_SRC_BIT`).
  1. **Map** the staging buffer, **copy** your data into it using `memcpy`.
  1. **Unmap** (if necessary) and potentially **flush** caches (usually only needed for
     non-`HOST_COHERENT` memory).
  1. Record a **copy command** (`vkCmdCopyBuffer`) in a command buffer to transfer data from the
     staging buffer to the destination buffer.
  1. **Submit** the command buffer to a queue that supports transfers.
  1. **Synchronize:** Ensure the copy operation is complete on the GPU before the destination buffer
     is used (e.g., via fences, semaphores, or barriers).
  1. Destroy the staging buffer once the copy is complete.

```
 CPU                       GPU (PCI-E Bus)                       GPU Memory
┌──────────────┐        ┌──────────────────┐        ┌──────────────────────────┐
│ Your App Data│        │                  │        │ Dest. Buffer (GPU_ONLY)  │
│ (e.g., []u8) │ ─────> │   memcpy(...)    │ ─────> │ (Vertex, Index, SSBO)    │
└──────────────┘        │ Staging Buffer   │        │ vkCmdCopyBuffer          │
                        │ (CPU_ONLY /      │        │                          │
                        │  CPU_TO_GPU,     │        └────────────▲─────────────┘
                        │  Mapped)         │                     │ Copy Operation
                        └──────────────────┘                     │ Triggered by CPU
                                                                 │ via Command Buffer
```

## Bindless Rendering via Buffer Device Address

Instead of binding buffers to specific descriptor set slots (`layout(set=X, binding=Y) buffer`),
bindless rendering allows shaders to access *any* buffer whose address has been made available.

- **Concept:** Get a 64-bit GPU virtual address (`VkDeviceAddress`) for a buffer. Pass this address
  to the shader (commonly via Push Constants or another SSBO containing a list of addresses). The
  shader can then use pointer casting and GLSL extensions (`GL_EXT_buffer_reference`) to access the
  buffer's data.
- **Enabling:**
  1. Enable the `bufferDeviceAddress` feature when creating the `VkDevice`.
  1. Use the `VK_BUFFER_USAGE_SHADER_DEVICE_ADDRESS_BIT` when creating any buffer you want an
     address for.
- **Getting the Address (Vulkan API):**
  ```c
  // After creating the buffer (myBuffer)
  VkBufferDeviceAddressInfo addrInfo = {
      .sType = VK_STRUCTURE_TYPE_BUFFER_DEVICE_ADDRESS_INFO,
      .buffer = myBuffer
  };
  VkDeviceAddress bufferAddress = vkGetBufferDeviceAddress(device, &addrInfo);
  ```
- **Using in GLSL (Example):**
  ```glsl
  #extension GL_EXT_buffer_reference : require
  #extension GL_EXT_buffer_reference_uvec2 : require // Often needed

  layout(buffer_reference, buffer_reference_align = 16) buffer MyPrimitiveData {
      // Define the structure matching your SSBO layout
      float x;
      vec3 color;
      // ... other members
  };

  // Get the address (e.g., from a push constant)
  layout(push_constant) uniform PushConstants {
      uint64_t primitiveDataAddress;
  } pc;

  void main() {
      // Cast the address to a buffer reference (pointer)
      MyPrimitiveData primitiveBuffer = MyPrimitiveData(pc.primitiveDataAddress);

      // Access data using the reference (like a pointer dereference)
      float coord_x = primitiveBuffer.x; // Access first element
      // Access i-th element (if SSBO contains an array)
      // vec3 color_i = MyPrimitiveData(pc.primitiveDataAddress + sizeof(MyPrimitiveDataStruct) * i).color;
      // OR using pointer arithmetic style if the buffer reference itself points to an array:
      // vec3 color_i = primitiveBuffer[i].color;
  }
  ```
- **Pros:**
  - Massive flexibility: Access potentially thousands of buffers without managing descriptor sets
    for each. Simplifies rendering different objects with different data buffers.
  - Can reduce descriptor set management overhead.
- **Cons:**
  - Requires specific Vulkan feature and GLSL extensions.
  - Addresses must be passed somehow (Push Constants are small, SSBO indirection adds a memory
    lookup).
  - Less explicit binding information for validation layers/debuggers compared to descriptor sets
    (though they are improving).

## 5. Synchronization

Crucial for correctness! The CPU and GPU operate asynchronously. You *must* ensure operations
complete before dependent operations begin.

- **Upload Synchronization:** The `vkCmdCopyBuffer` is just a command recorded by the CPU. The
  actual copy happens later on the GPU. You need to ensure the copy finishes *before* any shader
  tries to read the destination buffer.

  - **Barriers (`vkCmdPipelineBarrier`):** Used *within* a command buffer to define execution and
    memory dependencies between commands. You'd place a barrier after the copy and before the draw
    command that uses the buffer, ensuring the copy's memory writes are visible to the shader reads.
  - **Semaphores (`VkSemaphore`):** Synchronize operations *between* different queue submissions.
    Signal a semaphore when the transfer submission completes, wait on it before the rendering
    submission begins.
  - **Fences (`VkFence`):** Synchronize the GPU with the *CPU*. Often used to know when a submitted
    command buffer (like the transfer one) has finished executing, allowing the CPU to safely reuse
    or destroy resources (like the staging buffer). Your `AsyncContext.submitEnd` likely uses a
    fence or waits idle implicitly.

- **General Rendering:** Barriers are essential for synchronizing render passes, image layout
  transitions (e.g., TRANSFER_DST -> SHADER_READ_ONLY), and dependencies between draw calls.

Remember to manage resource lifetimes correctly (e.g., don't destroy a buffer while the GPU might
still be using it). Fences are key for CPU-side cleanup.
