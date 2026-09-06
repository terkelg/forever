"""Create the editable Blender source. Run with Blender --background --python."""

import math
from pathlib import Path
import struct
import zlib

import bpy
import numpy as np
from mathutils import Vector


ROOT = Path(__file__).resolve().parents[1]
ART = ROOT / "art"
ART.mkdir(exist_ok=True)


def png(path, pixels):
    """Write the source texture without adding a Python imaging dependency."""
    height, width, _ = pixels.shape

    def chunk(kind, data):
        return struct.pack(">I", len(data)) + kind + data + struct.pack(">I", zlib.crc32(kind + data))

    scanlines = b"".join(b"\0" + row.tobytes() for row in pixels)
    path.write_bytes(
        b"\x89PNG\r\n\x1a\n"
        + chunk(b"IHDR", struct.pack(">IIBBBBB", width, height, 8, 2, 0, 0, 0))
        + chunk(b"IDAT", zlib.compress(scanlines))
        + chunk(b"IEND", b"")
    )


def aim(obj, target=(0, 0, 0)):
    obj.rotation_euler = (Vector(target) - obj.location).to_track_quat("-Z", "Y").to_euler()


def light(name, location, power, size, color=(1, 1, 1)):
    data = bpy.data.lights.new(name, "AREA")
    data.energy = power
    data.shape = "DISK"
    data.size = size
    data.color = color
    obj = bpy.data.objects.new(name, data)
    bpy.context.collection.objects.link(obj)
    obj.location = location
    aim(obj)


bpy.ops.object.select_all(action="SELECT")
bpy.ops.object.delete(use_global=False)
bpy.context.preferences.filepaths.save_version = 0
scene = bpy.context.scene
scene.render.engine = "CYCLES"
scene.cycles.samples = 64
scene.cycles.use_denoising = True
scene.render.film_transparent = True
scene.render.image_settings.file_format = "PNG"
scene.render.image_settings.color_mode = "RGBA"
scene.render.image_settings.color_depth = "8"
scene.render.resolution_x = 512
scene.render.resolution_y = 512
scene.render.resolution_percentage = 100
scene.render.fps = 24
scene.view_settings.view_transform = "Standard"
scene.view_settings.look = "None"
scene.view_settings.exposure = -0.4
scene.world.use_nodes = True
scene.world.node_tree.nodes["Background"].inputs["Color"].default_value = (0.8, 0.8, 0.8, 1)
scene.world.node_tree.nodes["Background"].inputs["Strength"].default_value = 0.7

# Six vinyl panels, with white circular patches at the two poles.
width, height = 1536, 768
palette = np.array([
    (28, 102, 250), (245, 246, 247), (250, 45, 54),
    (245, 246, 247), (255, 193, 0), (245, 246, 247),
], dtype=np.uint8)
texture = np.empty((height, width, 3), dtype=np.uint8)
for index, color in enumerate(palette):
    texture[:, index * width // 6:(index + 1) * width // 6] = color
texture[:43] = palette[1]
texture[-43:] = palette[1]
png(ART / "beachball-texture.png", texture)

material = bpy.data.materials.new("Glossy vinyl — beachball texture")
material.use_nodes = True
nodes = material.node_tree.nodes
shader = nodes.get("Principled BSDF")
shader.inputs["Roughness"].default_value = 0.24
shader.inputs["IOR"].default_value = 1.46
shader.inputs["Coat Weight"].default_value = 0.3
shader.inputs["Coat Roughness"].default_value = 0.18
image = nodes.new("ShaderNodeTexImage")
image.image = bpy.data.images.load(str(ART / "beachball-texture.png"))
image.image.pack()
image.label = "Edit the six colored panels here"
image.location = (-340, 200)
material.node_tree.links.new(image.outputs["Color"], shader.inputs["Base Color"])

bpy.ops.mesh.primitive_uv_sphere_add(segments=192, ring_count=96, radius=1)
ball = bpy.context.object
ball.name = "Beachball"
ball.data.name = "Inflated six-panel sphere"
ball.data.materials.append(material)
for face in ball.data.polygons:
    face.use_smooth = True

# Tiny welded seams keep the object feeling inflatable without a ribbed silhouette.
for vertex in ball.data.vertices:
    point = vertex.co
    latitude = math.acos(max(-1, min(1, point.z)))
    longitude = math.atan2(point.y, point.x)
    seam = math.exp(-((math.sin(3 * longitude)) / 0.022) ** 2)
    cap = math.exp(-((min(latitude, math.pi - latitude) - math.pi * 43 / height) / 0.008) ** 2)
    depth = 0.0018 * seam * math.sin(latitude) + 0.001 * cap
    vertex.co *= 1 - depth

tilt = bpy.data.objects.new("Spin axis — tilt toward camera", None)
bpy.context.collection.objects.link(tilt)
tilt.rotation_mode = "QUATERNION"
tilt.rotation_quaternion = Vector((0, 0, 1)).rotation_difference(Vector((0.26, -0.9, 0.35)).normalized())
ball.parent = tilt
ball.rotation_euler.z = math.radians(40)
ball.keyframe_insert(data_path="rotation_euler", frame=1)
ball.rotation_euler.z -= math.tau
ball.keyframe_insert(data_path="rotation_euler", frame=49)
for curve in ball.animation_data.action.fcurves:
    for key in curve.keyframe_points:
        key.interpolation = "LINEAR"
scene.frame_start = 1
scene.frame_end = 48
scene.frame_set(1)

bpy.ops.object.camera_add(location=(0, -6, 0))
camera = bpy.context.object
camera.name = "Icon camera — transparent square"
camera.data.type = "ORTHO"
camera.data.ortho_scale = 2.25
aim(camera)
scene.camera = camera
light("Large softbox — upper left", (-3, -4, 4), 300, 3.5)
light("Right softbox", (4, -2, 1.5), 130, 2.5)
light("Soft rim", (0, 2, 3), 220, 3)
light("Lower fill", (-1, -4, -3), 100, 5)

bpy.ops.object.select_all(action="DESELECT")
ball.select_set(True)
bpy.context.view_layer.objects.active = ball
for screen in bpy.data.screens:
    for area in screen.areas:
        if area.type == "VIEW_3D":
            area.spaces.active.region_3d.view_perspective = "CAMERA"
            area.spaces.active.shading.type = "MATERIAL"

scene.render.filepath = str(ART / "preview.png")
bpy.ops.wm.save_as_mainfile(filepath=str(ART / "beachball.blend"))
bpy.ops.render.render(write_still=True)
