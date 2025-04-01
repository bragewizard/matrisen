#set text(font: "Source Serif 4 18pt", size:10pt)
#show math.equation : set text(font:"TeX Gyre Schola Math")
#show heading: set text(font:"Source Serif 4",weight: "black",style: "italic")
#set par(justify: true)



= Mini-Wiki: GPU Vector Graphics & Vulkan Buffer Management
<mini-wiki-gpu-vector-graphics-vulkan-buffer-management>
== Buffer Uploads: Getting Data to the GPU
<buffer-uploads-getting-data-to-the-gpu>
To make data accessible to GPU shaders, you need to upload it into
`VkBuffer` objects. Efficient uploading, especially to high-performance
`GPU_ONLY` memory, requires #strong[staging buffers];.

- #strong[GPU Memory Types (VMA Perspective):]

  - `VMA_MEMORY_USAGE_GPU_ONLY`: Fastest memory for GPU access. Cannot
    be directly mapped (written to) by the CPU. Ideal for vertex/index
    buffers, SSBOs, textures that don’t change often.
  - `VMA_MEMORY_USAGE_CPU_ONLY`: Memory easily accessible by the CPU
    (mappable). Slower for the GPU to access directly. Good for staging
    uploads.
  - `VMA_MEMORY_USAGE_CPU_TO_GPU`: Mappable by CPU, reasonably fast for
    GPU. Good for staging or buffers updated frequently by the CPU.
    Often uses PCI-E BAR memory.
  - `VMA_MEMORY_USAGE_GPU_TO_CPU`: Mappable by CPU, intended for reading
    data #emph[back] from the GPU.

- #strong[Why Staging Buffers?] You cannot write directly into
  `GPU_ONLY` memory from the CPU. The standard method is:

  + Create the final #strong[destination buffer] on the GPU (`GPU_ONLY`,
    `VK_BUFFER_USAGE_TRANSFER_DST_BIT`).
  + Create a temporary #strong[staging buffer] accessible by the CPU
    (`CPU_ONLY` or `CPU_TO_GPU`, `VK_BUFFER_USAGE_TRANSFER_SRC_BIT`).
  + #strong[Map] the staging buffer, #strong[copy] your data into it
    using `memcpy`.
  + #strong[Unmap] (if necessary) and potentially #strong[flush] caches
    (usually only needed for non-`HOST_COHERENT` memory).
  + Record a #strong[copy command] (`vkCmdCopyBuffer`) in a command
    buffer to transfer data from the staging buffer to the destination
    buffer.
  + #strong[Submit] the command buffer to a queue that supports
    transfers.
  + #strong[Synchronize:] Ensure the copy operation is complete on the
    GPU before the destination buffer is used (e.g., via fences,
    semaphores, or barriers).
  + Destroy the staging buffer once the copy is complete.

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

== Bindless Rendering via Buffer Device Address
<bindless-rendering-via-buffer-device-address>
Instead of binding buffers to specific descriptor set slots
(`layout(set=X, binding=Y) buffer`), bindless rendering allows shaders
to access #emph[any] buffer whose address has been made available.

- #strong[Concept:] Get a 64-bit GPU virtual address (`VkDeviceAddress`)
  for a buffer. Pass this address to the shader (commonly via Push
  Constants or another SSBO containing a list of addresses). The shader
  can then use pointer casting and GLSL extensions
  (`GL_EXT_buffer_reference`) to access the buffer’s data.

- #strong[Enabling:]

  + Enable the `bufferDeviceAddress` feature when creating the
    `VkDevice`.
  + Use the `VK_BUFFER_USAGE_SHADER_DEVICE_ADDRESS_BIT` when creating
    any buffer you want an address for.

- #strong[Getting the Address (Vulkan API):]

  ```c
  // After creating the buffer (myBuffer)
  VkBufferDeviceAddressInfo addrInfo = {
      .sType = VK_STRUCTURE_TYPE_BUFFER_DEVICE_ADDRESS_INFO,
      .buffer = myBuffer
  };
  VkDeviceAddress bufferAddress = vkGetBufferDeviceAddress(device, &addrInfo);
  ```

- #strong[Using in GLSL (Example):]

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

- #strong[Pros:]

  - Massive flexibility: Access potentially thousands of buffers without
    managing descriptor sets for each. Simplifies rendering different
    objects with different data buffers.
  - Can reduce descriptor set management overhead.

- #strong[Cons:]

  - Requires specific Vulkan feature and GLSL extensions.
  - Addresses must be passed somehow (Push Constants are small, SSBO
    indirection adds a memory lookup).
  - Less explicit binding information for validation layers/debuggers
    compared to descriptor sets (though they are improving).

== 5. Synchronization
<synchronization>
Crucial for correctness! The CPU and GPU operate asynchronously. You
#emph[must] ensure operations complete before dependent operations
begin.

- #strong[Upload Synchronization:] The `vkCmdCopyBuffer` is just a
  command recorded by the CPU. The actual copy happens later on the GPU.
  You need to ensure the copy finishes #emph[before] any shader tries to
  read the destination buffer.

  - #strong[Barriers (`vkCmdPipelineBarrier`):] Used #emph[within] a
    command buffer to define execution and memory dependencies between
    commands. You’d place a barrier after the copy and before the draw
    command that uses the buffer, ensuring the copy’s memory writes are
    visible to the shader reads.
  - #strong[Semaphores (`VkSemaphore`):] Synchronize operations
    #emph[between] different queue submissions. Signal a semaphore when
    the transfer submission completes, wait on it before the rendering
    submission begins.
  - #strong[Fences (`VkFence`):] Synchronize the GPU with the
    #emph[CPU];. Often used to know when a submitted command buffer
    (like the transfer one) has finished executing, allowing the CPU to
    safely reuse or destroy resources (like the staging buffer). Your
    `AsyncContext.submitEnd` likely uses a fence or waits idle
    implicitly.

- #strong[General Rendering:] Barriers are essential for synchronizing
  render passes, image layout transitions (e.g., TRANSFER\_DST -\>
  SHADER\_READ\_ONLY), and dependencies between draw calls.

Remember to manage resource lifetimes correctly (e.g., don’t destroy a
buffer while the GPU might still be using it). Fences are key for
CPU-side cleanup.
