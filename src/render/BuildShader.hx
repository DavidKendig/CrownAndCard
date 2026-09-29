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
			var position:Vec3;
			var uv:Vec2;
			var color:Vec3;
		};

		var transformedPosition:Vec3;
		var relativePosition:Vec3;
		var waterPosition:Vec2;
		var pixelColor:Vec4;
		var calculatedUV:Vec2;
		var vertexShade:Float;

		@param var indexMap:Sampler2D;
		@param var shadeLut:Sampler2D;

		/** Shade levels added per meter of distance (Build's "visibility"). **/
		@param var visibility:Float;

		/** Added to every pixel of this object (negative = brighter, e.g. candle flames). **/
		@param var shadeOffset:Float;
		@param var opacity:Float;
		/** xyz: courtyard flash origin; w: strength, zero when there is no storm. */
		@param var stormLight:Vec4;
		@param var conservatoryStormLight:Vec4;

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
		@const var waterSurface:Bool;
		@const var waterStream:Bool;
		@param var waterTime:Float;
		@param var waterImpacts:Array<Vec4,12>;

		function vertex() {
			if(waterSurface) {
				waterPosition=input.position.xy;
				relativePosition.z += sin(input.position.x*9.+waterTime*2.1)*.004
					+sin(input.position.y*11.-waterTime*2.7)*.004;
			}
			calculatedUV = input.uv * uvScale + uvOffset;
			vertexShade = input.color.x;
		}

		function fragment() {
			var waterUV=calculatedUV;
			var ripple=0.;
			var foam=0.;
			if(waterSurface) {
				for(i in 0...12) {
					var impact=waterImpacts[i];
					var d=length(waterPosition-impact.xy);
					var fade=max(0.,1.-d/.42)*impact.w;
					ripple+=sin(d*55.-waterTime*13.+impact.z)*fade;
					foam=max(foam,fade*max(0.,sin(d*70.-waterTime*17.+impact.z)));
				}
				waterUV += vec2(sin(waterPosition.y*6.+waterTime),cos(waterPosition.x*7.-waterTime*1.3))*.018
					+vec2(ripple*.008,-ripple*.008);
			}
			if(waterStream) waterUV.y-=waterTime*2.8;
			var texel = indexMap.get(waterUV);
			if (alphaTest && texel.a < 0.5)
				discard;
			var index = floor(texel.r * 255. + 0.5);
			if(waterSurface && foam>.48) index=138.;
			// Broken silver highlights travel with the flow, instead of reading as solid teal cords.
			if(waterStream && sin(waterUV.y*23.+waterUV.x*12.)>.4) index=140.;
			var shade = vertexShade + shadeOffset + length(transformedPosition - camera.position) * visibility;
			shade -= max(stormLight.w * max(0., 1. - length(transformedPosition - stormLight.xyz) / 18.),
				conservatoryStormLight.w * max(0., 1. - length(transformedPosition - conservatoryStormLight.xyz) / 18.));
			if(waterSurface) shade-=ripple*3.;
			if(waterStream) shade-=3.+3.*sin(waterUV.y*19.);
			for (i in 0...8) {
				var l = lights[i];
				var d = length(transformedPosition - l.xyz);
				shade -= lightPower[i].x * max(0., 1. - d / max(l.w, 0.001));
			}
			shade = clamp(floor(shade), 0., 31.);
			var lut = shadeLut.get(vec2((index + 0.5) / 256., (shade + 0.5) / 32.));
			var alpha=opacity;
			if(waterSurface) {
				var view=normalize(camera.position-transformedPosition);
				var grazing=pow(1.-abs(view.z),3.);
				alpha=min(.94,opacity+grazing*.22+foam*.15);
			}
			pixelColor = vec4(lut.rgb, alpha);
		}
	};

	public function new(indexMap:h3d.mat.Texture, shadeLut:h3d.mat.Texture, alphaTest:Bool) {
		super();
		this.indexMap = indexMap;
		this.shadeLut = shadeLut;
		this.alphaTest = alphaTest;
		waterSurface=false; waterStream=false; waterTime=0;
		waterImpacts=[for(_ in 0...12) new h3d.Vector4(0,0,0,0)];
		visibility = 0.6;
		shadeOffset = 0;
		opacity = 1;
		stormLight.set(0,0,0,0);
		conservatoryStormLight.set(0,0,0,0);
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
