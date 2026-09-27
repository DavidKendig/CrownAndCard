// SPDX-License-Identifier: AGPL-3.0-or-later
package render;

import h3d.col.Point;
import h3d.prim.UV;

/**
	A Build-style "face sprite" (§5.3): an upright billboard that turns to face
	the camera around the vertical axis only, and shows one of 8 viewing angles
	from 5 drawn frames (front, front-¾, side, back-¾, back). Angles 5–7 are
	frames 3–1 mirrored. It snaps between angles and never interpolates.
**/
class BuildSprite {
	public static inline var DRAWN_ANGLES = 5;

	public final mesh:h3d.scene.Mesh;
	public final shader:BuildShader;

	/** Direction the character faces, in radians (0 = +X, counter-clockwise). **/
	public var facing:Float = 0;

	/** Which of the 8 view angles is showing (0 = front), for debugging. **/
	public var angleIndex(default, null):Int = 0;

	final frames:Int;
	final rows:Int;
	/** Animation phase is independent of the camera-facing angle. **/
	public var animationFrame:Int = 0;
	final halfWidth:Float;

	/**
		`sheet` holds the drawn angles side by side (or a single frame when
		`frames` is 1). Size is in meters; texture scale is 64 texels per meter.
	**/
	public function new(sheet:h3d.mat.Texture, shadeLut:h3d.mat.Texture, frames:Int, widthM:Float, heightM:Float, parent:h3d.scene.Object, rows:Int = 1) {
		this.frames = frames;
		this.rows = rows;
		halfWidth = widthM / 2;
		// Quad in the XZ plane, facing +Y. Viewed from +Y, screen-right is -X,
		// so u runs from +X to -X to keep the art the right way round.
		var mb = new MeshBuilder();
		mb.quad(new Point(halfWidth, 0, heightM), new Point(-halfWidth, 0, heightM), new Point(-halfWidth, 0, 0), new Point(halfWidth, 0, 0),
			new UV(0, 0), new UV(1, 0), new UV(1, 1), new UV(0, 1), new Point(0, 1, 0), 0);
		var mat = h3d.mat.Material.create();
		mat.mainPass.enableLights = false;
		mat.shadows = false;
		mat.mainPass.culling = None;
		shader = new BuildShader(sheet, shadeLut, true);
		mat.mainPass.addShader(shader);
		mesh = new h3d.scene.Mesh(mb.toPrimitive(), mat, parent);
		setFrame(0, false);
	}

	public function setPosition(x:Float, y:Float, z:Float):Void {
		mesh.setPosition(x, y, z);
	}

	/** Turns to face the camera and picks the view angle. Call once per frame. **/
	public function update(camX:Float, camY:Float):Void {
		var toCam = Math.atan2(camY - mesh.y, camX - mesh.x);
		mesh.setRotation(0, 0, toCam - Math.PI / 2);
		if (frames == 1) {
			setFrame(0, false);
			return;
		}
		var rel = toCam - facing;
		var index = Math.round(rel / (Math.PI / 4)) % 8;
		if (index < 0)
			index += 8;
		angleIndex = index;
		// 0 front, 1 front-¾, 2 side, 3 back-¾, 4 back; 5–7 mirror 3–1.
		if (index <= 4)
			setFrame(index, false);
		else
			setFrame(8 - index, true);
	}

	function setFrame(frame:Int, mirrored:Bool):Void {
		var w = 1 / frames;
		var h = 1 / rows;
		var row = ((animationFrame % rows) + rows) % rows;
		if (mirrored) {
			shader.uvScale.set(-w, h);
			shader.uvOffset.set((frame + 1) * w, row * h);
		} else {
			shader.uvScale.set(w, h);
			shader.uvOffset.set(frame * w, row * h);
		}
	}
}
