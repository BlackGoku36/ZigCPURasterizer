A CPU Rasterizer written in Zig during my free time for fun and to learn.

- PBR Shading
- Lights: Area, Point, Directional
- Texture (Bilinear sampling)
- glTF format (W.I.P, doesn't support .glb file, PBR Textures of different sizes, spotlight, among some other things)

Zig version: 0.15.2

## Build Instructions

<!--Requirements:-->
<!--- The submodules-->
<!--- Sokol-shdc bin from [here](https://github.com/floooh/sokol-tools-bin), and set ENV var to it. (to compile sokol side shader, in case you just want to run, you can comment out `line 15` from `build.zig` as the shader is already compiled).-->

Put glTF (.gltf) in project_root/assets/ with below structure:

```
project_root/
		assets/
				some_demo/
						demo.gltf
						demo.bin
								textures/
										...
```

Run (in project_root):

```
zig build run -Doptimize=ReleaseFast
```
---

Screenshot:

The Junk Shop:

![screenshot](screenshot.png)

<!--Lumberyard Bistro:-->

<!--![screenshot2](screenshot2.png)-->

<!--![screenshot2](screenshot2.png)-->

---

Some refs:

- https://www.scratchapixel.com/ (Huge thanks)
- http://acta.uni-obuda.hu/Mileff_Nehez_Dudra_63.pdf
- https://fgiesen.wordpress.com/2013/02/10/optimizing-the-basic-rasterizer/
- https://www.cs.drexel.edu/~david/Classes/Papers/comp175-06-pineda.pdf

Lion (Prev | ReleaseFast):
Frame Time (Min - Max): 22 - 31
Avg.  Time (Min - Max): 26.68868 - 30.67742


Lion (New | ReleaseFast):
Frame Time (Min - Max): 19 - 27
Avg.  Time (Min - Max): 21.70513 - 23.67742


Lion (Prev | Debug):
Frame Time (Min - Max): 106 - 142
Avg.  Time (Min - Max): 122.10526 - 128.07500


Lion (New | Debug):
Frame Time (Min - Max): 92 - 118
Avg.  Time (Min - Max): 107.01357 - 112.09677


Note: There wasn't any (apparent) performance improvement from using 
new datastructure compared to used zigimg directly. Most of the improvements
is from moving image operation (normal map [0, 1] -> [-1, 1] and albedo's srgb -> linear)
conversions.
