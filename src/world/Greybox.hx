// SPDX-License-Identifier: AGPL-3.0-or-later
package world;

import render.BuildShader.SceneLight;

/** A character placed in the level, drawn as a Build face sprite. **/
typedef GuestSpawn = {
	var name:String;
	var x:Float;
	var y:Float;

	/** Radians, 0 = +X (east), counter-clockwise. **/
	var facing:Float;

	/** Authored PNG identity. Preserve its outfit colors through the shade LUT. **/
	var art:String;

	/** Turns slowly on the spot, to show off the 8-angle snapping. **/
	var spins:Bool;
	@:optional var walkTo:{x:Float, y:Float};
}

/**
	Phase 0 greybox (§14.2): the Entrance Hall with the front desk, a corridor,
	the Rotunda (hub) and the Card Room with one blackjack table. It's there
	to test the look and movement, not the final layout.
**/
class Greybox {
	/** First row is north (+Y). One character = one meter. **/
	static final ROWS = [
		"##########################",
		"########cccccccccc########",
		"########cccccccccc########",
		"########cccccccccc########",
		"########cccccccccc########",
		"########cccccccccc########",
		"########cccccccccc########",
		"############hh############",
		"######rrrrrrrrrrrrrr######",
		"######rrrrrrrrrrrrrr######",
		"######rr#rrrrrrrr#rr######",
		"######rrrrrrrrrrrrrr######",
		"######rrrrrrrrrrrrrr######",
		"######rrrrrrrrrrrrrr######",
		"######rr#rrrrrrrr#rr######",
		"######rrrrrrrrrrrrrr######",
		"######rrrrrrrrrrrrrr######",
		"############hh############",
		"############hh############",
		"#########eeeeeeee#########",
		"#########eeeeeeee#########",
		"#########eeeeeeee#########",
		"#########eeeeeeee#########",
		"##########################",
	];

	public static function map():GridMap {
		var sectors = [
			"r" => {name: "Rotunda", floorZ: 0.0, ceilZ: 6.0, floorTex: "marble", ceilTex: "dome", wallTex: "damask", upperTex: "damaskUpper", shade: 5.0},
			"c" => {name: "Card Room", floorZ: 0.0, ceilZ: 3.5, floorTex: "carpet", ceilTex: "coffer", wallTex: "deco", upperTex: "decoUpper", shade: 8.0},
			"h" => {name: "Corridor", floorZ: 0.0, ceilZ: 3.0, floorTex: "parquet", ceilTex: "coffer", wallTex: "green", upperTex: "greenUpper", shade: 11.0},
			"e" => {name: "Entrance Hall", floorZ: 0.0, ceilZ: 3.5, floorTex: "parquet", ceilTex: "coffer", wallTex: "damask", upperTex: "damaskUpper", shade: 7.0},
		];
		var m = new GridMap(ROWS, sectors);
		// Blackjack table in the Card Room.
		m.props.push({x0: 11.8, y0: 19.4, x1: 14.2, y1: 20.6, height: 0.9, topTex: "felt", sideTex: "tableWood"});
		// Front desk in the Entrance Hall, where Mr. Quill checks guests in (§4.2).
		m.props.push({x0: 10.2, y0: 1.4, x1: 10.9, y1: 3.6, height: 1.1, topTex: "tableWood", sideTex: "tableWood"});
		return m;
	}

	public static final PLAYER_START = {x: 13.0, y: 1.6, yaw: Math.PI / 2};

	public static final GUESTS:Array<GuestSpawn> = [
		{name: "Mr. Quill (front desk)", x: 9.6, y: 2.5, facing: 0, art: "male_staff", spins: false},
		{name: "Cloakroom attendant", x: 16.0, y: 3.0, facing: Math.PI, art: "female_staff", spins: false},
		{name: "Spinning guest", x: 11.0, y: 10.0, facing: 0, art: "masked_guest", spins: true},
		{name: "Colonel", x: 16.0, y: 12.6, facing: Math.PI, art: "masked_guest", spins: false},
		{name: "Rotunda guest", x: 14.8, y: 10.0, facing: -Math.PI / 2, art: "female_guest", spins: false},
		{name: "Dealer", x: 13.0, y: 21.3, facing: -Math.PI / 2, art: "female_staff", spins: false},
		{name: "Seated lady", x: 12.1, y: 18.7, facing: Math.PI / 2, art: "female_guest_seated", spins: false},
		{name: "Seated gentleman", x: 14.0, y: 18.7, facing: Math.PI / 2, art: "male_guest_seated", spins: false},
		{name: "Strolling gentleman", x: 10.0, y: 9.0, facing: Math.PI / 2, art: "male_guest_walk", spins: false, walkTo: {x: 10.0, y: 13.0}},
		{name: "Strolling lady", x: 15.0, y: 11.0, facing: Math.PI / 2, art: "female_guest_walk", spins: false, walkTo: {x: 15.0, y: 15.0}},
		{name: "Pemberton", x: 9.5, y: 14.0, facing: 0, art: "male_staff", spins: false},
	];

	public static final CHANDELIER = {x: 13.0, y: 11.0, z: 4.1};

	public static final LIGHTS:Array<SceneLight> = [
		{x: 13.0, y: 11.0, z: 4.4, radius: 9.0, power: 11.0}, // Rotunda chandelier
		{x: 13.0, y: 20.0, z: 2.4, radius: 4.5, power: 11.0}, // lamp over the blackjack table
		{x: 9.2, y: 2.5, z: 2.2, radius: 3.2, power: 7.0}, // Entrance Hall sconces
		{x: 16.8, y: 2.5, z: 2.2, radius: 3.2, power: 7.0},
	];
}
