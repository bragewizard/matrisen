#import "@preview/lovelace:0.3.0": *
#set text(font: "Source Serif 4")
#show math.equation : set text(font:"STIX Two Math")
#show heading: h => { set text(font:"Source Serif 4",weight: "black"); h }

#set page(numbering: "1")
#set par(justify: true)

#text("Matrisen", size: 24pt, weight: "black")

#datetime.today().display()
#v(1cm)


= Notes
#v(1em)

set up mesh shader that takes in parameters for curves and lines
save the parameters after model view projection and lighting calculations

make a global resource bank with buffers and images, dont bundle them together
and put structs everywhere and member variables everywhere


// TODO
// = Algorithm
// #align(center,
// pseudocode-list(hooks: .5em, line-numbering: none)[
//   + do something
//   + do something else
//   + *while* still something to do
//     + do even more
//     + *if* not done yet *then*
//       + wait a bit
//       + resume working
//     + *else*
//       + go home
// ]
// )



