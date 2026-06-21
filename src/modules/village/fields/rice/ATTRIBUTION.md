# Rice Asset Notes

The rice stage scenes in this directory are custom simple Godot scenes created for this project. They do not redistribute downloaded meshes or textures.

The current paddy visuals are generated in-engine:

- `RicePaddyRenderer.gd` builds flooded water surfaces, elevated soil bund meshes, and a far-distance macro overlay from generated plot polygons.
- `rice_dense_plants_particles.gd` creates a procedural rice clump mesh from multiple upright, slightly curved grass-like blade strips.
- The paddy bund, paddy water, and dense rice blade shaders are custom project shaders.

Reference candidates reviewed during planning:

- Rice Plant CC-BY: https://sketchfab.com/3d-models/rice-plant-be6aa4ac9adc4f558cc789a0baed8ae3
- Rice Plant CC-BY-NC: https://sketchfab.com/3d-models/rice-plant-68fd8a9b358144d895e3f7838e33e2a1
- Germinated Rice CC-BY: https://sketchfab.com/3d-models/germinated-rice-b6f400d10e1f4c55bd26e36de181444c
- Real-world paddy field structure and bund context: https://en.wikipedia.org/wiki/Paddy_field
- Procedural subdivision reference: https://cgl.ethz.ch/Downloads/Publications/Papers/2001/p_Par01.pdf
- Polygon clipping reference used for the generator shape pipeline: https://en.wikipedia.org/wiki/Sutherland%E2%80%93Hodgman_algorithm

The standalone stage scenes are lightweight visual references and can be replaced by imported `.glb` clumps if a suitable licensed asset pack is added later.
