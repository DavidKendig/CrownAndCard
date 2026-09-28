// SPDX-License-Identifier: AGPL-3.0-or-later
package games.mahjong;

import games.mahjong.Analysis.Decomposition;
import games.mahjong.MahjongGame;

/** A set in a finished hand, melded or concealed. **/
typedef Group = {kind:Int, chow:Bool, kong:Bool, concealed:Bool};

/** One reading of a finished hand: its groups, pair, and how the winning tile completed it. **/
typedef Reading = {groups:Array<Group>, pair:Int, wait:String};

typedef RiichiResult = {
	/** The hand has a yaku (dora alone doesn't count). **/
	var valid:Bool;

	var han:Int;
	var fu:Int;
	var yakuman:Int;

	/** Base points (fu × 2^(han + 2), capped by the limits). **/
	var base:Float;

	var lines:Array<String>;
	var label:String;
}

typedef ClassicResult = {faan:Int, points:Int, lines:Array<String>, label:String};

/**
	Scoring for both rule sets. Every reading of the hand (each split into sets
	and each place the winning tile could sit) is scored, and the best counts.

	Riichi follows the World Riichi Championship rules: open tanyao, no red
	fives; yakuman don't double (several simply add up).
	Classic uses a Hong Kong-style faan table with a 13-faan limit.
**/
class Scoring {
	// --- Readings ---

	static function meldGroups(p:MjPlayer):Array<Group> {
		return [for (m in p.melds) {kind: m.kind, chow: m.type == Chow, kong: m.type == Kong || m.type == ClosedKong, concealed: m.type == ClosedKong}];
	}

	public static function readings(p:MjPlayer, tiles:Array<Int>, winTile:Int, tsumo:Bool):Array<Reading> {
		var out:Array<Reading> = [];
		var open = meldGroups(p);
		for (d in Analysis.decompositions(Tiles.counts(tiles), p.melds.length)) {
			function add(wait:String, openIndex:Int) {
				var groups = open.copy();
				for (i in 0...d.sets.length) {
					var s = d.sets[i];
					// A pung finished with someone else's discard counts as open.
					groups.push({kind: s.kind, chow: s.chow, kong: false, concealed: !(i == openIndex && !tsumo && !s.chow)});
				}
				out.push({groups: groups, pair: d.pair, wait: wait});
			}
			if (d.pair == winTile) add("tanki", -1);
			for (i in 0...d.sets.length) {
				var s = d.sets[i];
				if (!s.chow && s.kind == winTile) add("shanpon", i);
				if (s.chow && winTile >= s.kind && winTile <= s.kind + 2) {
					var pos = winTile - s.kind;
					var wait = pos == 1 ? "kanchan" : pos == 0 ? (Tiles.rank(s.kind) == 7 ? "penchan" : "ryanmen") : (Tiles.rank(s.kind) == 1 ? "penchan" : "ryanmen");
					add(wait, i);
				}
			}
		}
		return out;
	}

	/** Every tile in the hand, melds included (a kong counts four). **/
	static function allTiles(p:MjPlayer, tiles:Array<Int>):Array<Int> {
		var out = tiles.copy();
		for (m in p.melds) switch m.type {
			case Chow:
				out.push(m.kind);
				out.push(m.kind + 1);
				out.push(m.kind + 2);
			case Pung:
				for (_ in 0...3) out.push(m.kind);
			default:
				for (_ in 0...4) out.push(m.kind);
		}
		return out;
	}

	static function suits(tiles:Array<Int>):{suits:Array<Int>, honors:Bool} {
		var s = [];
		var honors = false;
		for (t in tiles) if (Tiles.isSuited(t)) {
			if (s.indexOf(Tiles.suit(t)) < 0) s.push(Tiles.suit(t));
		} else honors = true;
		return {suits: s, honors: honors};
	}

	static function groupHasTerminal(g:Group):Bool return g.chow ? (Tiles.rank(g.kind) == 1 || Tiles.rank(g.kind) == 7) : Tiles.isTerminalOrHonor(g.kind);

	// --- Riichi ---

	public static function riichi(game:MahjongGame, seat:Int, tiles:Array<Int>, winTile:Int, tsumo:Bool, from:Int):RiichiResult {
		var p = game.players[seat];
		var counts = Tiles.counts(tiles);
		var closed = p.closed;
		var every = allTiles(p, tiles);
		var seatW = Tiles.EAST + game.seatWind(seat), roundW = Tiles.EAST + game.roundWind;
		var dealer = seat == game.dealer;

		// Situational yaku, the same for every reading.
		var situ:Array<{n:String, h:Int}> = [];
		var situYakuman:Array<String> = [];
		if (p.doubleRiichi) situ.push({n: "Double riichi", h: 2}) else if (p.riichi) situ.push({n: "Riichi", h: 1});
		if (p.riichi && p.ippatsu) situ.push({n: "Ippatsu", h: 1});
		if (closed && tsumo) situ.push({n: "Fully concealed hand (menzen tsumo)", h: 1});
		if (game.tilesLeft == 0) situ.push(tsumo ? {n: "Last tile from the wall (haitei)", h: 1} : {n: "Last discard (houtei)", h: 1});
		if (tsumo && game.replacementDraw) situ.push({n: "After a kong (rinshan kaihou)", h: 1});
		if (tsumo && p.firstTurn && !game.anyCallThisHand) situYakuman.push(dealer ? "Blessing of heaven (tenhou)" : "Blessing of earth (chiihou)");

		var best:Null<RiichiResult> = null;
		function consider(items:Array<{n:String, h:Int}>, yakuman:Array<String>, fu:Int) {
			var all = situ.concat(items);
			var yk = situYakuman.concat(yakuman);
			var yakuHan = 0;
			for (i in all) yakuHan += i.h;
			var valid = yakuHan > 0 || yk.length > 0;
			var lines = [];
			var han = yakuHan, base:Float;
			if (yk.length > 0) {
				for (y in yk) lines.push('$y: yakuman');
				base = 8000 * yk.length;
			} else {
				for (i in all) lines.push('${i.n}: ${i.h} han');
				var d = doraCount(game, every, p.riichi);
				if (d.dora > 0) lines.push('Dora: ${d.dora}');
				if (d.ura > 0) lines.push('Ura-dora: ${d.ura}');
				han += d.dora + d.ura;
				base = han >= 13 ? 8000 : han >= 11 ? 6000 : han >= 8 ? 4000 : han >= 6 ? 3000 : han >= 5 ? 2000 : Math.min(2000, fu * Math.pow(2, han + 2));
			}
			var r:RiichiResult = {valid: valid, han: han, fu: fu, yakuman: yk.length, base: base, lines: lines, label: label(han, fu, yk.length, base, dealer, tsumo)};
			if (best == null || (r.valid && !best.valid) || (r.valid == best.valid && (r.base > best.base || (r.base == best.base && r.han > best.han)))) best = r;
		}

		if (Analysis.isThirteenOrphans(counts, p.melds.length)) consider([], ["Thirteen orphans (kokushi musou)"], 0);
		if (Analysis.isSevenPairs(counts, p.melds.length)) {
			var items = [{n: "Seven pairs (chiitoitsu)", h: 2}];
			var yk = [];
			flushAndTerminalYaku(every, closed, items, yk);
			consider(items, yk, 25);
		}
		for (r in readings(p, tiles, winTile, tsumo)) {
			var y = standardYaku(r, every, closed, seatW, roundW, tsumo, counts, p.melds.length);
			consider(y.items, y.yakuman, y.fu);
		}
		if (best == null) return {valid: false, han: 0, fu: 0, yakuman: 0, base: 0, lines: [], label: "No yaku"};
		return best;
	}

	/** Tanyao, honitsu, chinitsu, honroutou and the all-honors yakuman: yaku any complete hand shape can have. **/
	static function flushAndTerminalYaku(every:Array<Int>, closed:Bool, items:Array<{n:String, h:Int}>, yakuman:Array<String>):Void {
		var allSimple = true, allTermHonor = true, allHonor = true;
		for (t in every) {
			if (!Tiles.isSimple(t)) allSimple = false;
			if (!Tiles.isTerminalOrHonor(t)) allTermHonor = false;
			if (!Tiles.isHonor(t)) allHonor = false;
		}
		if (allHonor) {
			yakuman.push("All honors (tsuuiisou)");
			return;
		}
		if (allSimple) items.push({n: "All simples (tanyao)", h: 1});
		if (allTermHonor) items.push({n: "All terminals and honors (honroutou)", h: 2});
		var s = suits(every);
		if (s.suits.length == 1) {
			if (s.honors) items.push({n: "Half flush (honitsu)", h: closed ? 3 : 2});
			else items.push({n: "Full flush (chinitsu)", h: closed ? 6 : 5});
		}
	}

	static function standardYaku(r:Reading, every:Array<Int>, closed:Bool, seatW:Int, roundW:Int, tsumo:Bool, counts:Array<Int>,
			melds:Int):{items:Array<{n:String, h:Int}>, yakuman:Array<String>, fu:Int} {
		var items:Array<{n:String, h:Int}> = [];
		var yk:Array<String> = [];
		var chows = [for (g in r.groups) if (g.chow) g];
		var pungs = [for (g in r.groups) if (!g.chow) g];
		function isYakuhai(k:Int) return Tiles.isDragon(k) || k == seatW || k == roundW;
		var pinfu = closed && chows.length == 4 && !isYakuhai(r.pair) && r.wait == "ryanmen";
		if (pinfu) items.push({n: "Pinfu", h: 1});
		flushAndTerminalYaku(every, closed, items, yk);
		// Identical chows: one pair iipeikou, two pairs ryanpeikou.
		if (closed) {
			var kinds = [for (g in chows) g.kind];
			kinds.sort((a, b) -> a - b);
			var pairs = 0, i = 0;
			while (i < kinds.length - 1) {
				if (kinds[i] == kinds[i + 1]) {
					pairs++;
					i += 2;
				} else i++;
			}
			if (pairs == 2) items.push({n: "Twice pure double chow (ryanpeikou)", h: 3});
			else if (pairs == 1) items.push({n: "Pure double chow (iipeikou)", h: 1});
		}
		for (g in pungs) {
			if (Tiles.isDragon(g.kind)) items.push({n: 'Dragon pung (${Tiles.name(g.kind)})', h: 1});
			if (g.kind == seatW) items.push({n: "Seat wind", h: 1});
			if (g.kind == roundW) items.push({n: "Round wind", h: 1});
		}
		for (rank in 1...8) {
			var hit = true;
			for (s in 0...3) {
				var found = false;
				for (g in chows) if (g.kind == s * 9 + rank - 1) found = true;
				if (!found) hit = false;
			}
			if (hit) {
				items.push({n: "Mixed triple chow (sanshoku)", h: closed ? 2 : 1});
				break;
			}
		}
		for (s in 0...3) {
			var have = [for (g in chows) if (Tiles.suit(g.kind) == s) Tiles.rank(g.kind)];
			if (have.indexOf(1) >= 0 && have.indexOf(4) >= 0 && have.indexOf(7) >= 0) items.push({n: "Pure straight (ittsu)", h: closed ? 2 : 1});
		}
		var outside = Tiles.isTerminalOrHonor(r.pair);
		for (g in r.groups) if (!groupHasTerminal(g)) outside = false;
		var honors = false;
		for (t in every) if (Tiles.isHonor(t)) honors = true;
		if (outside && chows.length > 0) {
			if (!honors) items.push({n: "Terminal in each set (junchan)", h: closed ? 3 : 2});
			else items.push({n: "Outside hand (chanta)", h: closed ? 2 : 1});
		}
		if (chows.length == 0) items.push({n: "All pungs (toitoi)", h: 2});
		var concealedPungs = 0;
		for (g in pungs) if (g.concealed) concealedPungs++;
		if (concealedPungs == 4) yk.push("Four concealed pungs (suuankou)");
		else if (concealedPungs == 3) items.push({n: "Three concealed pungs (sanankou)", h: 2});
		for (rank in 1...10) {
			var n = 0;
			for (s in 0...3) for (g in pungs) if (g.kind == s * 9 + rank - 1) n++;
			if (n == 3) items.push({n: "Triple pung (sanshoku doukou)", h: 2});
		}
		var kongs = 0;
		for (g in r.groups) if (g.kong) kongs++;
		if (kongs == 4) yk.push("Four kongs (suukantsu)");
		else if (kongs == 3) items.push({n: "Three kongs (sankantsu)", h: 2});
		var dragons = [for (g in pungs) if (Tiles.isDragon(g.kind)) g].length;
		if (dragons == 3) yk.push("Big three dragons (daisangen)");
		else if (dragons == 2 && Tiles.isDragon(r.pair)) items.push({n: "Little three dragons (shousangen)", h: 2});
		var winds = [for (g in pungs) if (Tiles.isWind(g.kind)) g].length;
		if (winds == 4) yk.push("Big four winds (daisuushii)");
		else if (winds == 3 && Tiles.isWind(r.pair)) yk.push("Little four winds (shousuushii)");
		var allTerminals = true, allGreen = true;
		var greens = [19, 20, 21, 23, 25, Tiles.GREEN];
		for (t in every) {
			if (!Tiles.isTerminal(t)) allTerminals = false;
			if (greens.indexOf(t) < 0) allGreen = false;
		}
		if (allTerminals) yk.push("All terminals (chinroutou)");
		if (allGreen) yk.push("All green (ryuuiisou)");
		if (closed && melds == 0 && nineGates(counts)) yk.push("Nine gates (chuuren poutou)");

		// Fu.
		var fu:Int;
		if (pinfu) fu = tsumo ? 20 : 30;
		else {
			fu = 20 + (closed && !tsumo ? 10 : 0) + (tsumo ? 2 : 0);
			for (g in pungs) {
				var v = Tiles.isTerminalOrHonor(g.kind) ? 4 : 2;
				if (g.concealed) v *= 2;
				if (g.kong) v *= 4;
				fu += v;
			}
			if (Tiles.isDragon(r.pair)) fu += 2;
			if (r.pair == seatW) fu += 2;
			if (r.pair == roundW) fu += 2;
			if (r.wait == "kanchan" || r.wait == "penchan" || r.wait == "tanki") fu += 2;
			if (!closed && fu == 20) fu = 30;
			fu = Std.int(Math.ceil(fu / 10) * 10);
		}
		return {items: items, yakuman: yk, fu: fu};
	}

	/** 1112345678999 in one suit plus any one more of that suit. **/
	static function nineGates(counts:Array<Int>):Bool {
		for (s in 0...3) {
			var total = 0;
			for (k in 0...Tiles.KINDS) if (counts[k] > 0 && (!Tiles.isSuited(k) || Tiles.suit(k) != s)) total = -100;
			if (total < 0) continue;
			var need = [3, 1, 1, 1, 1, 1, 1, 1, 3];
			var ok = true;
			for (r in 0...9) if (counts[s * 9 + r] < need[r]) ok = false;
			if (ok) return true;
		}
		return false;
	}

	static function doraCount(game:MahjongGame, every:Array<Int>, riichi:Bool):{dora:Int, ura:Int} {
		var dora = 0, ura = 0;
		for (i in 0...game.doraShown) {
			var d = Tiles.doraFrom(game.indicators[i]);
			for (t in every) if (t == d) dora++;
			if (riichi) {
				var u = Tiles.doraFrom(game.ura[i]);
				for (t in every) if (t == u) ura++;
			}
		}
		return {dora: dora, ura: ura};
	}

	static function label(han:Int, fu:Int, yakuman:Int, base:Float, dealer:Bool, tsumo:Bool):String {
		inline function up(x:Float):Int return Std.int(Math.ceil(x / 100) * 100);
		var name = yakuman > 0 ? (yakuman > 1 ? '$yakuman× yakuman' : "Yakuman") : han >= 13 ? "Counted yakuman" : han >= 11 ? "Sanbaiman" : han >= 8 ? "Baiman"
			: han >= 6 ? "Haneman" : base >= 2000 ? "Mangan" : '$han han $fu fu';
		var pay = tsumo ? (dealer ? '${up(base * 2)} all' : '${up(base)} / ${up(base * 2)}') : Std.string(up(base * (dealer ? 6 : 4)));
		return '$name: $pay';
	}

	// --- Classic (Hong Kong-style faan) ---

	/** Points for 0..10+ faan (a doubling table that flattens after 4 faan). **/
	public static final CLASSIC_POINTS = [1, 2, 4, 8, 16, 24, 32, 48, 64, 96, 128, 128, 128, 128];

	public static function classic(game:MahjongGame, seat:Int, tiles:Array<Int>, winTile:Int, tsumo:Bool, from:Int):ClassicResult {
		var p = game.players[seat];
		var counts = Tiles.counts(tiles);
		var every = allTiles(p, tiles);
		var seatW = Tiles.EAST + game.seatWind(seat), roundW = Tiles.EAST + game.roundWind;

		// Situational faan and flowers, the same for every reading.
		var situ:Array<{n:String, f:Int}> = [];
		if (tsumo) situ.push({n: "Self-drawn", f: 1});
		if (p.closed) situ.push({n: "Concealed hand", f: 1});
		if (game.tilesLeft == 0) situ.push({n: "Win on the last tile", f: 1});
		if (tsumo && game.replacementDraw) situ.push({n: "Win on a replacement tile", f: 1});
		if (p.flowers.length == 0) situ.push({n: "No flowers", f: 1});
		for (f in p.flowers) if (Tiles.ownBonus(f, game.seatWind(seat))) situ.push({n: 'Own flower (${Tiles.name(f)})', f: 1});
		for (set in [[34, 35, 36, 37], [38, 39, 40, 41]]) {
			var all = true;
			for (f in set) if (p.flowers.indexOf(f) < 0) all = false;
			if (all) situ.push({n: set[0] == 34 ? "All four flowers" : "All four seasons", f: 2});
		}

		var best:Null<ClassicResult> = null;
		function consider(items:Array<{n:String, f:Int}>, limit:Bool) {
			var all = items.concat(situ);
			var faan = 0;
			for (i in all) faan += i.f;
			if (limit || faan > 13) faan = 13;
			var points = CLASSIC_POINTS[Std.int(Math.min(faan, CLASSIC_POINTS.length - 1))];
			var lines = [for (i in all) '${i.n}: ${i.f} faan'];
			if (limit) lines.unshift("Limit hand: 13 faan");
			var r:ClassicResult = {faan: faan, points: points, lines: lines, label: '$faan faan: $points points'};
			if (best == null || r.faan > best.faan) best = r;
		}
		if (Analysis.isThirteenOrphans(counts, p.melds.length)) consider([{n: "Thirteen orphans", f: 13}], true);
		if (Analysis.isSevenPairs(counts, p.melds.length)) {
			var items = [{n: "Seven pairs", f: 4}];
			classicFlushes(every, items);
			consider(items, false);
		}
		for (r in readings(p, tiles, winTile, tsumo)) {
			var items:Array<{n:String, f:Int}> = [];
			var limit = false;
			var chows = [for (g in r.groups) if (g.chow) g];
			var pungs = [for (g in r.groups) if (!g.chow) g];
			if (chows.length == 4) items.push({n: "All chows", f: 1});
			if (chows.length == 0) items.push({n: "All pungs", f: 3});
			classicFlushes(every, items);
			var dragons = [for (g in pungs) if (Tiles.isDragon(g.kind)) g].length;
			var winds = [for (g in pungs) if (Tiles.isWind(g.kind)) g].length;
			if (dragons == 3) items.push({n: "Great three dragons", f: 8});
			else {
				for (g in pungs) if (Tiles.isDragon(g.kind)) items.push({n: 'Dragon pung (${Tiles.name(g.kind)})', f: 1});
				if (dragons == 2 && Tiles.isDragon(r.pair)) items.push({n: "Small three dragons", f: 3});
			}
			if (winds == 4) {
				items.push({n: "Great four winds", f: 13});
				limit = true;
			} else if (winds == 3 && Tiles.isWind(r.pair)) items.push({n: "Small four winds", f: 10});
			else {
				for (g in pungs) {
					if (g.kind == seatW) items.push({n: "Seat wind pung", f: 1});
					if (g.kind == roundW) items.push({n: "Prevailing wind pung", f: 1});
				}
			}
			var concealed = [for (g in pungs) if (g.concealed) g].length;
			if (concealed == 4) {
				items.push({n: "Four concealed pungs", f: 13});
				limit = true;
			}
			if (p.melds.length == 0 && nineGates(counts)) {
				items.push({n: "Nine gates", f: 13});
				limit = true;
			}
			var allTerminals = true;
			for (t in every) if (!Tiles.isTerminal(t)) allTerminals = false;
			if (allTerminals) {
				items.push({n: "All terminals", f: 10});
			}
			consider(items, limit);
		}
		if (best == null) return {faan: 0, points: 0, lines: [], label: "Not a complete hand"};
		return best;
	}

	static function classicFlushes(every:Array<Int>, items:Array<{n:String, f:Int}>):Void {
		var s = suits(every);
		if (s.suits.length == 0) items.push({n: "All honors", f: 10});
		else if (s.suits.length == 1) {
			if (s.honors) items.push({n: "Mixed one suit", f: 3});
			else items.push({n: "Pure one suit", f: 7});
		}
	}
}
