Bindless

== Core

Holds instances of all the components, it serves as the scafholding of the engine, does not have any logic itself. It inits and deinits the engine.
- It holds a global descriptorset
- Holds all the layouts (pipeline, descriptor)
- It decides how many frames in flight there should be (how many FrameContexts)
- hold and instance of VmaMemoryAllocator
- holds instace of swapchain, device etc
!should Core hold the swapchain images or should they be in ImageManager?

== command.zig

Here you find FrameContext which hold all the synchronization needed per frame also holds a dynamic descritorset (so there would be one dynamic per frame in flight) and commandbuffer
it has scoped logic to issue general commands sent to the gpu like begin and end rendering


== BufferManager

Holds references to buffers allocated by VmaAllocator, keeps track of indices needed by bindless

== ImageMangaer

Does the same as BufferManager but for images

== PipelineManager

Holds the pipelines and builds and compiles them, uses descriptorsetlayouts and pipelinelayouts from Core

== renderer

holds the drawing logic, this would be called in between begin and end rendering from command.zig

== utils, image, buffer, gltf ...

These files does not hold data only logic, used to not have too large files


== TODO

Decouple, many of the functions take in core reference and change and use it, it is a headache to keep track of, consider using depenency injection
