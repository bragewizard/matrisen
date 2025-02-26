#import "@preview/lovelace:0.3.0": *
#set text(font: "Source Serif 4", size:10pt)
#show math.equation : set text(font:"TeX Gyre Schola Math")
#show heading: set text(font:"Source Serif 4",weight: "black",style: "italic")
#set par(justify: true)

#text("Matrisen", size: 24pt, weight: "black",style: "italic")

#datetime.today().display()
#v(1cm)


= Architechtural Elements
#v(1em)

Use Device Buffer Adress for large buffers (vertex data, parameters, images),
uniforms for global scene data (time, camera, lights) and depending on material use
uniforms for texture and samplers.
Use push constants for per object data (attenuation, device buffer index)

= Rendering primitives (lines, curves, circles, arcs, polygons) and their 3D variants
#v(1em)

The plan here is to have a single pipeline for all these primitives.
This will mean that the fragment shader has some branching.
Font rendering will be covered by this since they count as curves. To
make it more performant we combine tesselation with this so that we have a
nice size of triangles---not to small and not too big. With too large
triangles we waste alot in the fragment shader, with too small we will
be vertex limited.
Tesselation should ideally be done in the mesh shader.
We could also support texture in this pipeline but idk.

= Rendering traditional meshes
#v(1em)

Use a PBR material with its own pipeline or two
// #align(center,
// [#smallcaps("Fragmentshader")
// #pseudocode-list(hooks: .5em, line-numbering: none)[
//   + *if* pixel > boundry *then*
//     + discard
//   + *else*
//     + fill in pixel
// ]])
