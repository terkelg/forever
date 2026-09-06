"""Render the saved .blend into a sprite sheet. Blender supplies bpy and NumPy."""

import argparse
import json
from pathlib import Path
import subprocess
import sys
import tempfile

import bpy


ROOT = Path(__file__).resolve().parents[1]


def positive(value):
    number = int(value)
    if number < 1:
        raise argparse.ArgumentTypeError("must be greater than zero")
    return number


parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument("--frames", type=positive, default=48, help="unique frames per rotation")
parser.add_argument("--fps", type=positive, default=24, help="playback frames per second")
parser.add_argument("--size", type=positive, default=256, help="pixels per square frame")
parser.add_argument("--samples", type=positive, default=64, help="Cycles samples per pixel")
parser.add_argument("--columns", type=positive, default=8, help="columns in the sprite sheet")
parser.add_argument("--output", type=Path, default=ROOT, help="export root; defaults to this project")
args = parser.parse_args(sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else [])

scene = bpy.context.scene
scene.render.resolution_x = args.size
scene.render.resolution_y = args.size
scene.render.resolution_percentage = 100
scene.render.film_transparent = True
scene.render.use_border = False
scene.render.image_settings.file_format = "PNG"
scene.render.image_settings.color_mode = "RGBA"
scene.render.image_settings.color_depth = "8"
scene.cycles.samples = args.samples
scene.cycles.use_denoising = True
scene.render.use_persistent_data = True

# Sample the saved model's complete timeline without duplicating its loop endpoint.
start = scene.frame_start
length = scene.frame_end - start + 1
output = args.output.resolve()
resources = output / "Forever" / "Resources"
resources.mkdir(parents=True, exist_ok=True)
with tempfile.TemporaryDirectory(prefix="forever-frames-") as temporary:
    directory = Path(temporary)
    for index in range(args.frames):
        position = start + index * length / args.frames
        scene.frame_set(int(position), subframe=position % 1)
        scene.render.filepath = str(directory / f"{index:04}.png")
        bpy.ops.render.render(write_still=True)
        print(f"Rendered {index + 1}/{args.frames}", flush=True)

    # A separate full-size render keeps the static app icon crisp in Finder.
    scene.frame_set(start)
    scene.render.resolution_x = 1024
    scene.render.resolution_y = 1024
    scene.render.filepath = str(directory / "icon.png")
    bpy.ops.render.render(write_still=True)

    columns = min(args.columns, args.frames)
    manifest = {
        "frames": args.frames,
        "fps": args.fps,
        "size": args.size,
        "columns": columns,
        "rows": (args.frames + columns - 1) // columns,
        "samples": args.samples,
    }
    (directory / "animation.json").write_text(json.dumps(manifest, indent=2) + "\n")
    subprocess.run([
        "/usr/bin/swift", str(ROOT / "scripts" / "Pack.swift"),
        str(directory), str(resources), str(output / "Forever" / "Assets.xcassets"),
    ], check=True)
print(f"Exported {args.frames} frames at {args.fps} fps to {output}")
