A CPU Rasterizer written in Zig during my free time for fun and to learn.

- Forward Renderer
- PBR Shading (Albedo, Metallic, Roughness, Transmission, Emissive)
- Lights: Area, Point, Directional
- Texture (Bilinear sampling)
- Transmission shading (with crude screen-space refraction)
- Exports to `.hdr` (HDR range) and `.png` (SDR range)
- glTF format (W.I.P, doesn't support .glb file, spotlight, among some other things)

Zig version: 0.15.2

## Build Instructions

In project root, do:

```
zig build -Doptimize=ReleaseFast
```

Find the exe in `zig-out/bin` named `ZigCPURasterizer`.

For interactive mode:

```
./ZigCPURasterizer --interactive -i path/to/demo.gltf
```

For static image exports (two format are supported `.png` and `.hdr`):

```
./ZigCPURasterizer -i path/to/demo.gltf -o image.png
```

---

Screenshot:

The Junk Shop:

![screenshot](0_junkshop.avif)

Lumberyard Bistro:

![screenshot2](0_bistro.avif)

![screenshot2](2_bistro.avif)

[Iron Howl v8](https://sketchfab.com/3d-models/iron-howl-v8-47a361137a3749858d21b2ce8bcbe21e)

![screenshot2](0_iron_howl_v8.avif)

![screenshot2](1_iron_howl_v8.avif)

---

Converting `.hdr` file to `.avif` (supported by both Safari/Chrome) or `.jxl` (supported by Safari only) to display on web.

```
ffmpeg -i camera_0.hdr \
  -vf "format=gbrpf32le,exposure=1,zscale=tin=linear:pin=bt709:rin=full:t=smpte2084:p=smpte432:r=full" \
  -c:v libaom-av1 -crf 10 -cpu-used 4 \
  -color_primaries smpte432 -color_trc smpte2084 -colorspace bt2020nc \
  test.avif
```

```
ffmpeg -i camera_0.hdr \
  -vf "format=gbrpf32le,exposure=1,zscale=tin=linear:pin=bt709:rin=full:t=smpte2084:p=smpte432:r=full" \
  -c:v libjxl \
  -color_primaries smpte432 -color_trc smpte2084 -colorspace bt2020nc \
  test.jxl
```

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
