// SPDX-License-Identifier: AGPL-3.0-or-later
package world;

import hxd.Key;

/**
	First-person movement (§4.6). W/S or Up/Down move, A/D strafe, Shift runs.
	Left/Right turn, PageUp/PageDown look up and down, End re-centers the view,
	and the mouse looks around too.

	Controller (§11.4): left stick or d-pad moves, right stick looks, LB or
	clicking the left stick runs, and clicking the right stick (or Y) re-centers
	the view. The stick's tilt sets the walking speed.

	Looking up and down (to 75° either way) starts with Build-style y-shearing
	(§5.5): the image slides instead of the camera pitching, so walls stay
	vertical. Past Build's ~31° the camera pitches for real.
**/
class PlayerController {
	public static inline var EYE_HEIGHT = 1.6;
	public static inline var RADIUS = 0.25;
	static inline var WALK_SPEED = 2.2;
	static inline var RUN_SPEED = 4.2;
	static inline var TURN_SPEED = 2.4; // radians per second
	static inline var PITCH_SPEED = 1.1;
	static inline var MOUSE_SENSITIVITY = 0.0025;
	/** Look limit up and down: 75°. **/
	public static inline var MAX_PITCH = 1.309;

	/**
		Y-shearing covers the first ~31° of look (Build's own range, §5.5).
		Beyond that the camera really pitches, because shearing that far
		stretches the image into a smear.
	**/
	static inline var SHEAR_LIMIT = 0.55;
	static inline var PAD_TURN_SPEED = 2.8; // radians per second at full tilt
	static inline var PAD_PITCH_SPEED = 1.3;

	public var x:Float;
	public var y:Float;
	public var feetZ:Float=0;

	/** Radians, 0 = +X (east), counter-clockwise. **/
	public var yaw:Float;

	public var pitch:Float = 0;

	/** 0 disables head bob (motion comfort option, §11.4). **/
	public var bobAmount:Float = 1;

	/** True perspective pitch instead of Build-style y-shearing (comfort option, §11.4). **/
	public var perspectiveLook = false;

	public var isMoving(default, null) = false;

	/** The connected controller, or an unconnected dummy (Main swaps it when one connects). **/
	public var pad:hxd.Pad = hxd.Pad.createDummy();

	final map:GridMap;
	var bobPhase = 0.0;

	public function new(map:GridMap, x:Float, y:Float, yaw:Float) {
		this.map = map;
		this.x = x;
		this.y = y;
		this.yaw = yaw;
		feetZ=map.floorAt(x,y);
	}

	public function look(dx:Float, dy:Float):Void {
		yaw -= dx * MOUSE_SENSITIVITY;
		pitch = Math.max(-MAX_PITCH, Math.min(MAX_PITCH, pitch - dy * MOUSE_SENSITIVITY));
	}

	public function update(dt:Float):Void {
		if (Key.isDown(Key.LEFT)) yaw += TURN_SPEED * dt;
		if (Key.isDown(Key.RIGHT)) yaw -= TURN_SPEED * dt;
		if (Key.isDown(Key.PGUP)) pitch = Math.min(MAX_PITCH, pitch + PITCH_SPEED * dt);
		if (Key.isDown(Key.PGDOWN)) pitch = Math.max(-MAX_PITCH, pitch - PITCH_SPEED * dt);
		if (Key.isPressed(Key.END)) pitch = 0;

		var p = pad;
		if (p.connected) {
			// Squared response: fine aim near the centre, fast turns at full tilt.
			var rx = p.rxAxis, ry = p.ryAxis;
			yaw -= rx * Math.abs(rx) * PAD_TURN_SPEED * dt;
			pitch = Math.max(-MAX_PITCH, Math.min(MAX_PITCH, pitch - ry * Math.abs(ry) * PAD_PITCH_SPEED * dt));
			if (p.isPressed(p.config.ranalogClick) || p.isPressed(p.config.Y))
				pitch = 0;
		}

		var fwd = 0.0, side = 0.0;
		if (Key.isDown(Key.W) || Key.isDown(Key.UP)) fwd += 1;
		if (Key.isDown(Key.S) || Key.isDown(Key.DOWN)) fwd -= 1;
		if (Key.isDown(Key.D)) side += 1;
		if (Key.isDown(Key.A)) side -= 1;
		var running = Key.isDown(Key.SHIFT);
		if (p.connected) {
			// Stick Y is negative when pushed forward.
			fwd -= p.yAxis;
			side += p.xAxis;
			if (p.isDown(p.config.dpadUp)) fwd += 1;
			if (p.isDown(p.config.dpadDown)) fwd -= 1;
			if (p.isDown(p.config.dpadRight)) side += 1;
			if (p.isDown(p.config.dpadLeft)) side -= 1;
			running = running || p.isDown(p.config.LB) || p.isDown(p.config.analogClick);
		}
		var len = Math.sqrt(fwd * fwd + side * side);
		isMoving = len > 0.01;
		if (!isMoving) {
			bobPhase = 0;
			return;
		}
		// Full speed for keys and a fully tilted stick; slower for a partly tilted one.
		var amount = Math.min(1, len);
		var speed = (running ? RUN_SPEED : WALK_SPEED) * amount;
		var step = speed * dt / len;
		// Facing +X at yaw 0, "right" is -Y.
		var mx = (Math.cos(yaw) * fwd + Math.sin(yaw) * side) * step;
		var my = (Math.sin(yaw) * fwd - Math.cos(yaw) * side) * step;
		// Slides along walls, and can always step out of a wall it started inside.
		var moved = map.slide(x, y, mx, my, RADIUS,feetZ);
		x = moved.x;
		y = moved.y;
		feetZ=moved.z;
		bobPhase += speed * dt * 3.0;
	}

	public function applyTo(camera:h3d.Camera):Void {
		var z = feetZ + EYE_HEIGHT + Math.abs(Math.sin(bobPhase)) * 0.035 * bobAmount;
		camera.pos.set(x, y, z);
		camera.up.set(0, 0, 1);
		if (perspectiveLook) {
			var c = Math.cos(pitch);
			camera.target.set(x + Math.cos(yaw) * c, y + Math.sin(yaw) * c, z + Math.sin(pitch));
			camera.viewY = 0;
		} else {
			// Y-shearing: offset the projection so the horizon moves (NDC units).
			// Positive pitch looks up (with the right-handed camera set in Main).
			var shear = Math.max(-SHEAR_LIMIT, Math.min(SHEAR_LIMIT, pitch));
			var tilt = pitch - shear, c = Math.cos(tilt);
			camera.target.set(x + Math.cos(yaw) * c, y + Math.sin(yaw) * c, z + Math.sin(tilt));
			camera.viewY = Math.tan(shear) / Math.tan(camera.fovY * Math.PI / 360);
		}
	}
}
