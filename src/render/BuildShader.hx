// SPDX-License-Identifier: AGPL-3.0-or-later
package render;

/**
	The Build-style surface shader (§5.4, §13.5).

	1. Reads a palette index from `indexMap` (nearest sampling, red channel).
	2. Works out a shade level: per-vertex area shade + object offset
	   + distance × visibility − nearby lights.
	3. Looks up the final color in the 256 × 32 shade table. The table maps
	   back into the palette, which gives Build's banded falloff.
**/
class BuildShader extends hxsl.Shader {
	public static inline var MAX_LIGHTS = 8;

	static var SRC = {
		@global var camera:{
			var position:Vec3;
		};

		@input var input:{
			var uv:Vec2;
			var color:Vec3;
		};

		var transformedPosition:Vec3;
		var pixelColor:Vec4;
		var calculatedUV:Vec2;
		var vertexShade:Float;

		@param var indexMap:Sampler2D;
		@param var shadeLut:Sampler2D;

		/** Shade levels added per meter of distance (Build's "visibility"). **/
		@param var visibility:Float;

		/** Added to every pixel of this object (negative = brighter, e.g. candle flames). **/
		@param var shadeOffset:Float;

		/** Sprite-sheet frame selection. **/
		@param var uvScale:Vec2;
		@param var uvOffset:Vec2;

		/** xyz = position, w = radius in meters. **/
		@param var lights:Array<Vec4, 8>;

		/**
			Shade levels removed at the center of each light, in `x`. (HXSL can
			only index arrays of whole vec4s with a loop variable.)
		**/
		@param var lightPower:Array<Vec4, 8>;

		@const var alphaTest:Bool;

		function vertex() {
			calculatedUV = input.uv * uvScale + uvOffset;
			vertexShade = input.color.x;
		}

		function fragment() {
			var texel = indexMap.get(calculatedUV);
			if (alphaTest && texel.a < 0.5)
				discard;
			var index = floor(texel.r * 255. + 0.5);
			var shade = vertexShade + shadeOffset + length(transformedPosition - camera.position) * visibility;
			for (i in 0...8) {
				var l = lights[i];
				var d = length(transformedPosition - l.xyz);
				shade -= lightPower[i].x * max(0., 1. - d / max(l.w, 0.001));
			}
			shade = clamp(floor(shade), 0., 31.);
			var lut = shadeLut.get(vec2((index + 0.5) / 256., (shade + 0.5) / 32.));
			pixelColor = vec4(lut.rgb, 1.);
		}
	};

	public function new(indexMap:h3d.mat.Texture, shadeLut:h3d.mat.Texture, alphaTest:Bool) {
		super();
		this.indexMap = indexMap;
		this.shadeLut = shadeLut;
		this.alphaTest = alphaTest;
		visibility = 0.6;
		shadeOffset = 0;
		uvScale.set(1, 1);
		uvOffset.set(0, 0);
		lights = [for (_ in 0...MAX_LIGHTS) new h3d.Vector4(0, 0, -1000, 1)];
		lightPower = [for (_ in 0...MAX_LIGHTS) new h3d.Vector4(0, 0, 0, 0)];
	}

	/** Copies up to MAX_LIGHTS lights into this shader. **/
	public function setLights(list:Array<SceneLight>):Void {
		for (i in 0...MAX_LIGHTS) {
			if (i < list.length) {
				var l = list[i];
				lights[i].set(l.x, l.y, l.z, l.radius);
				lightPower[i].set(l.power, 0, 0, 0);
			} else {
				lights[i].set(0, 0, -1000, 1);
				lightPower[i].set(0, 0, 0, 0);
			}
		}
	}
}

/** A Build-style light: it lowers the shade level within its radius. **/
typedef SceneLight = {
	var x:Float;
	var y:Float;
	var z:Float;
	var radius:Float;
	var power:Float;
}
