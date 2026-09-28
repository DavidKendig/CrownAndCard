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
			"c" => {name: "Card Room", floorZ: 0.0, ceilZ: 3.5, floorTex: "carpet", ceilTex: "coffer", wallTex: "damask", upperTex: "decoUpper", shade: 8.0},
			"h" => {name: "Corridor", floorZ: 0.0, ceilZ: 3.0, floorTex: "parquet", ceilTex: "coffer", wallTex: "green", upperTex: "greenUpper", shade: 11.0},
			"e" => {name: "Entrance Hall", floorZ: 0.0, ceilZ: 8.0, floorTex: "marble", ceilTex: "coffer", wallTex: "damask", upperTex: "damaskUpper", shade: 7.0},
		];
		var rows = ROWS.slice(0, 17);
		rows.push("######hhh########hhh######");
		rows.push("######hhh########hhh######");
		for (_ in 0...20) rows.push("###eeeeeeeeeeeeeeeeeeee###");
		rows.push("##########################");
		var m = new GridMap(rows, sectors);
		// The card table in the Card Room (blackjack and spades, §4.3).
		var t = CardRoom.TABLE;
		m.props.push({x0: t.x0, y0: t.y0, x1: t.x1, y1: t.y1, height: 0.9, topTex: "felt", sideTex: "tableWood"});
		// Front desk in the Entrance Hall, where Mr. Quill checks guests in (§4.2).
		Foyer.furnish(m);
		return m;
	}

	public static final PLAYER_START = Foyer.START;

	public static final GUESTS:Array<GuestSpawn> = [
		{name: "Mr. Quill (front desk)", x: 13.0, y: 7.8, facing: -Math.PI / 2, art: "hooded_keeper", spins: false},
		{name: "Cloakroom attendant", x: 20.0, y: 5.0, facing: Math.PI, art: "female_staff", spins: false},
		{name: "Spinning guest", x: 11.0, y: 26, facing: 0, art: "masked_guest", spins: true},
		{name: "Colonel", x: 16.0, y: 28.6, facing: Math.PI, art: "masked_guest", spins: false},
		{name: "Rotunda guest", x: 14.8, y: 26, facing: -Math.PI / 2, art: "female_guest", spins: false},
		{name: "Dealer", x: 13.0, y: 37.3, facing: -Math.PI / 2, art: "female_staff", spins: false},
		{name: "Seated lady", x: 12.1, y: 34.7, facing: Math.PI / 2, art: "female_guest_seated", spins: false},
		{name: "Seated gentleman", x: 14.0, y: 34.7, facing: Math.PI / 2, art: "male_guest_seated", spins: false},
		{name: "Strolling gentleman", x: 10.0, y: 25, facing: Math.PI / 2, art: "male_guest_walk", spins: false, walkTo: {x: 10.0, y: 29}},
		{name: "Strolling lady", x: 15.0, y: 27, facing: Math.PI / 2, art: "female_guest_walk", spins: false, walkTo: {x: 15.0, y: 31}},
		{name: "Pemberton", x: 9.5, y: 30, facing: 0, art: "male_staff", spins: false},
	];

	public static final CHANDELIER = {x: 13.0, y: 27.0, z: 4.1};

	public static final LIGHTS:Array<SceneLight> = [
		{x: 13.0, y: 27.0, z: 4.4, radius: 9.0, power: 11.0}, // Rotunda chandelier
		{x: 13.0, y: 36.0, z: 2.4, radius: 4.5, power: 11.0}, // lamp over the blackjack table
		{x: 13.0, y: 6.0, z: 3.8, radius: 10.0, power: 8.0}, // Entrance chandelier
		{x: 13.0, y: 15.0, z: 5.2, radius: 10.0, power: 8.0},
	];
}
