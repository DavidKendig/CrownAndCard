// SPDX-License-Identifier: AGPL-3.0-or-later
package games.mahjong;

import games.PlayLog;

enum abstract Variant(String) to String {
	/** Hong Kong-style Classic: 144 tiles with flowers, faan scoring. **/
	var Classic = "Classic";

	/** Japanese Riichi: 136 tiles, riichi, dora, yaku and han/fu scoring (WRC-based). **/
	var Riichi = "Riichi";
}

enum abstract Phase(String) to String {
	var Waiting = "waiting";
	var Draw = "draw";
	var Act = "act";
	var Claims = "claims";
	var HandOver = "hand over";
	var GameOver = "game over";
}

enum abstract MeldType(String) to String {
	var Chow = "chow";
	var Pung = "pung";
	var Kong = "kong";
	var ClosedKong = "closed kong";
}

/** A melded set: `kind` is its lowest tile, `from` the seat whose discard made it (-1 for a closed kong). **/
/**
	A declared set. `from` is the seat whose discard was called (-1 for a closed
	kong), `called` that tile (the table turns it sideways toward that seat),
	and `added` marks a kong made by adding the fourth tile to a called pung.
**/
typedef Meld = {type:MeldType, kind:Int, from:Int, ?called:Int, ?added:Bool};

enum Claim {
	/** Win on the discard (Ron in Riichi, "Mahjong" in Classic). **/
	Ron;

	Pon;
	Kan;

	/** A chow of `low`, low + 1, low + 2 using the discard. **/
	Chi(low:Int);
}

typedef HandResult = {
	/** -1 for an exhaustive draw. **/
	var winner:Int;

	/** The discarder, or -1 for a self-drawn win. **/
	var from:Int;

	var tile:Int;
	var title:String;

	/** Scoring lines: yaku and han, faan items, fu, dora. **/
	var lines:Array<String>;

	/** "3 han 40 fu: 5,200" or "5 faan: 24". **/
	var value:String;

	/** Score change per seat. **/
	var deltas:Array<Int>;

	/** Ready hands at an exhaustive draw. **/
	var tenpai:Array<Bool>;
}

class MjPlayer {
	public final name:String;
	public var score:Int = 0;

	/** Concealed tiles, sorted, including a just-drawn tile. **/
	public final hand:Array<Int> = [];

	/** The tile drawn this turn, or -1. **/
	public var drawn = -1;

	public final melds:Array<Meld> = [];
	public final discards:Array<Int> = [];

	/** Discards other players claimed (they stay listed but are drawn apart). **/
	public final claimed:Array<Bool> = [];

	public final flowers:Array<Int> = [];
	public var riichi = false;
	public var doubleRiichi = false;

	/** Index in `discards` of the tile turned sideways for riichi. **/
	public var riichiDiscard = -1;

	public var ippatsu = false;

	/** Passed a win since this player's last discard. **/
	public var furitenTemp = false;

	/** Passed a win after declaring riichi: furiten for the rest of the hand. **/
	public var furitenRiichi = false;

	/** Still on the first go-around with no calls made (tenhou, chiihou, double riichi). **/
	public var firstTurn = true;

	public function new(name:String) {
		this.name = name;
	}

	public var closed(get, never):Bool;

	function get_closed():Bool {
		for (m in melds) if (m.type != ClosedKong) return false;
		return true;
	}

	public function count(kind:Int):Int {
		var n = 0;
		for (t in hand) if (t == kind) n++;
		return n;
	}

	public function removeTiles(kind:Int, n:Int):Void {
		for (_ in 0...n) hand.remove(kind);
	}
}

/**
	A four-player Mahjong table (§6.4) for both rule sets. Seats run in play
	order: 0 is the player, 1 to their right, 2 across, 3 to their left, so a
	chow can only be taken from the previous seat. Pure state and rules; the
	table screen drives it and the AI decides for the other seats.

	One East round: every seat deals at least once, and the dealer keeps the
	deal after winning (Classic also after a drawn hand; Riichi when the dealer
	is ready). A Riichi game also ends when anyone goes below zero.
**/
class MahjongGame {
	public static inline var MAX_HANDS = 16;

	public final variant:Variant;
	public final players:Array<MjPlayer>;
	public var phase(default, null):Phase = Waiting;
	public var dealer(default, null) = 0;

	/** The prevailing wind: the game plays the East round. **/
	public final roundWind = 0;

	public var handNumber(default, null) = 0;
	public var honba(default, null) = 0;
	public var riichiSticks(default, null) = 0;
	public var turn(default, null) = 0;
	public var wall(default, null):Array<Int> = [];

	/** Riichi: four kong replacement tiles, dora indicators and ura-dora (the dead wall). **/
	public var rinshan(default, null):Array<Int> = [];

	public var indicators(default, null):Array<Int> = [];
	public var ura(default, null):Array<Int> = [];

	/** How many dora indicators are face up (1 + kongs). **/
	public var doraShown(default, null) = 1;

	public var lastDiscard(default, null):Null<{seat:Int, tile:Int}> = null;
	public var result(default, null):Null<HandResult> = null;

	/** The next draw is a kong replacement (for the rinshan / kong-replacement win). **/
	public var afterKong(default, null) = false;

	/** A tile drawn this turn was a replacement for a kong (still true while the player acts). **/
	public var replacementDraw(default, null) = false;

	public var anyCallThisHand(default, null) = false;

	/** Claims the other seats may make on the current discard; null once a seat has decided. **/
	public final pending:Array<Null<Array<Claim>>> = [null, null, null, null];

	final decisions:Array<Null<Claim>> = [null, null, null, null];
	final decided:Array<Bool> = [false, false, false, false];
	var dealersPassed = 0;
	final rng:rng.IRng;

	public function new(variant:Variant, names:Array<String>, rng:rng.IRng) {
		this.variant = variant;
		this.rng = rng;
		players = [for (n in names) new MjPlayer(n)];
		for (p in players) p.score = variant == Riichi ? 25000 : 500;
	}

	public inline function seatWind(seat:Int):Int return (seat - dealer + 4) % 4;

	public static inline function next(seat:Int):Int return (seat + 1) % 4;

	public var tilesLeft(get, never):Int;

	inline function get_tilesLeft():Int return wall.length;

	public function startHand():Void {
		if (phase == GameOver) throw 'The game is over';
		handNumber++;
		result = null;
		lastDiscard = null;
		afterKong = replacementDraw = anyCallThisHand = false;
		doraShown = 1;
		for (i in 0...4) {
			pending[i] = null;
			decided[i] = false;
		}
		wall = Tiles.wall(variant == Classic, rng);
		if (variant == Riichi) {
			var dead = wall.splice(wall.length - 14, 14);
			rinshan = dead.slice(0, 4);
			indicators = dead.slice(4, 9);
			ura = dead.slice(9, 14);
		} else {
			rinshan = [];
			indicators = [];
			ura = [];
		}
		for (p in players) {
			p.hand.resize(0);
			p.melds.resize(0);
			p.discards.resize(0);
			p.claimed.resize(0);
			p.flowers.resize(0);
			p.drawn = -1;
			p.riichi = p.doubleRiichi = p.ippatsu = p.furitenTemp = p.furitenRiichi = false;
			p.riichiDiscard = -1;
			p.firstTurn = true;
		}
		for (_ in 0...13) for (k in 0...4) players[(dealer + k) % 4].hand.push(wall.shift());
		// Classic: bonus tiles are set aside and replaced from the back of the wall.
		if (variant == Classic) for (k in 0...4) {
			var p = players[(dealer + k) % 4];
			var i = 0;
			while (i < p.hand.length) {
				if (Tiles.isBonus(p.hand[i])) {
					p.flowers.push(p.hand[i]);
					p.hand[i] = wall.pop();
				} else i++;
			}
		}
		for (p in players) Tiles.sort(p.hand);
		turn = dealer;
		phase = Draw;
	}

	/** The current seat draws (a kong replacement after a kong). An empty wall ends the hand. **/
	public function draw():Void {
		if (phase != Draw) throw 'Not time to draw';
		var p = players[turn];
		if (wall.length == 0) {
			exhaustiveDraw();
			return;
		}
		var tile = afterKong ? replacement() : wall.shift();
		PlayLog.play(turn, afterKong ? "draws a replacement tile" : "draws a tile");
		replacementDraw = afterKong;
		afterKong = false;
		while (variant == Classic && Tiles.isBonus(tile)) {
			p.flowers.push(tile);
			PlayLog.play(turn, "sets aside " + Tiles.name(tile) + " and draws again");
			if (wall.length == 0) {
				exhaustiveDraw();
				return;
			}
			tile = wall.pop();
			replacementDraw = true;
		}
		p.hand.push(tile);
		Tiles.sort(p.hand);
		p.drawn = tile;
		phase = Act;
	}

	function replacement():Int {
		if (variant == Riichi) {
			var t = rinshan.shift();
			// The dead wall stays at 14: the last live tile moves into it.
			if (wall.length > 0) rinshan.push(wall.pop());
			return t;
		}
		return wall.pop();
	}

	// --- Acting on your own turn ---

	public function canTsumo(seat:Int):Bool {
		if (phase != Act || seat != turn) return false;
		var p = players[seat];
		// Only with a freshly drawn tile: never straight after a pung or chow.
		if (p.drawn < 0 || !Analysis.isComplete(Tiles.counts(p.hand), p.melds.length)) return false;
		return variant == Classic || Scoring.riichi(this, seat, p.hand, p.drawn, true, -1).valid;
	}

	/** Kinds this seat may kong now: four in hand (closed) or a pung plus the fourth (added). **/
	public function kongOptions(seat:Int):Array<Int> {
		if (phase != Act || seat != turn || wall.length == 0) return [];
		var p = players[seat];
		if (p.riichi) return [];
		if (variant == Riichi && rinshan.length == 0) return [];
		var out = [];
		for (k in 0...Tiles.KINDS) if (p.count(k) == 4) out.push(k);
		for (m in p.melds) if (m.type == Pung && p.count(m.kind) > 0) out.push(m.kind);
		return out;
	}

	/** Riichi: a closed, ready-after-discard hand with 1,000 to stake and at least four tiles left. **/
	public function canRiichi(seat:Int):Bool {
		if (variant != Riichi || phase != Act || seat != turn) return false;
		var p = players[seat];
		return !p.riichi && p.closed && p.score >= 1000 && wall.length >= 4 && riichiDiscards(seat).length > 0;
	}

	/** Discards that leave the hand ready. **/
	public function riichiDiscards(seat:Int):Array<Int> {
		var p = players[seat];
		var out = [];
		var c = Tiles.counts(p.hand);
		for (k in 0...Tiles.KINDS) if (c[k] > 0 && out.indexOf(k) < 0) {
			c[k]--;
			if (Analysis.shanten(c, p.melds.length) == 0) out.push(k);
			c[k]++;
		}
		return out;
	}

	/** After riichi the drawn tile must go (unless it wins). **/
	public function legalDiscards(seat:Int):Array<Int> {
		var p = players[seat];
		if (p.riichi) return [p.drawn];
		var out = [];
		for (t in p.hand) if (out.indexOf(t) < 0) out.push(t);
		return out;
	}

	public function tsumo(seat:Int):Void {
		if (!canTsumo(seat)) throw 'Seat $seat cannot win now';
		PlayLog.play(seat, "wins on a self-drawn " + Tiles.name(players[seat].drawn) + " (tsumo)");
		win(seat, players[seat].drawn, -1);
	}

	public function kong(seat:Int, kind:Int):Void {
		if (kongOptions(seat).indexOf(kind) < 0) throw 'Seat $seat cannot kong $kind';
		var p = players[seat];
		PlayLog.play(seat, (p.count(kind) == 4 ? "declares a closed kong of " : "adds to a kong of ") + Tiles.name(kind));
		if (p.count(kind) == 4) {
			p.removeTiles(kind, 4);
			p.melds.push({type: ClosedKong, kind: kind, from: -1, called: -1, added: false});
		} else {
			p.removeTiles(kind, 1);
			for (m in p.melds) if (m.type == Pung && m.kind == kind) {
				m.type = Kong;
				m.added = true;
			}
		}
		p.drawn = -1;
		kongMade(seat);
	}

	function kongMade(seat:Int):Void {
		for (q in players) q.ippatsu = false;
		if (variant == Riichi && doraShown < 5) doraShown++;
		turn = seat;
		afterKong = true;
		phase = Draw;
	}

	public function discard(seat:Int, tile:Int, declareRiichi = false):Void {
		if (phase != Act || seat != turn) throw 'Seat $seat cannot discard now';
		if (legalDiscards(seat).indexOf(tile) < 0) throw 'Seat $seat cannot discard $tile';
		var p = players[seat];
		if (declareRiichi) {
			if (!canRiichi(seat) || riichiDiscards(seat).indexOf(tile) < 0) throw 'Riichi is not allowed with that discard';
			p.riichi = true;
			p.doubleRiichi = p.firstTurn && !anyCallThisHand;
			p.ippatsu = true;
			p.score -= 1000;
			riichiSticks++;
			p.riichiDiscard = p.discards.length;
		} else if (p.riichi) p.ippatsu = false;
		p.hand.remove(tile);
		p.discards.push(tile);
		PlayLog.play(seat, "discards " + Tiles.name(tile) + (declareRiichi ? " and declares riichi" : ""));
		p.claimed.push(false);
		p.drawn = -1;
		p.furitenTemp = false;
		p.firstTurn = false;
		replacementDraw = false;
		lastDiscard = {seat: seat, tile: tile};
		openClaims();
	}

	// --- Claims on a discard ---

	/** What `seat` may claim on the current discard (empty when nothing). **/
	public function claimOptions(seat:Int):Array<Claim> {
		var d = lastDiscard;
		if (d == null || seat == d.seat) return [];
		var p = players[seat];
		var t = d.tile;
		var out:Array<Claim> = [];
		var c = Tiles.counts(p.hand);
		c[t]++;
		if (Analysis.isComplete(c, p.melds.length)) {
			var ok = variant == Classic || (!furiten(seat) && Scoring.riichi(this, seat, p.hand.concat([t]), t, false, d.seat).valid);
			if (ok) out.push(Ron);
		}
		if (p.riichi || wall.length == 0) return out;
		var have = p.count(t);
		if (have >= 2) out.push(Pon);
		if (have >= 3 && (variant == Classic || rinshan.length > 0)) out.push(Kan);
		if (seat == next(d.seat) && Tiles.isSuited(t)) {
			for (low in t - 2...t + 1) {
				if (low < 0 || !Tiles.isSuited(low) || Tiles.suit(low) != Tiles.suit(t) || Tiles.rank(low) > 7) continue;
				var need = [low, low + 1, low + 2];
				need.remove(t);
				if (p.count(need[0]) > 0 && p.count(need[1]) > 0) out.push(Chi(low));
			}
		}
		return out;
	}

	function openClaims():Void {
		var any = false;
		for (s in 0...4) {
			var opts = claimOptions(s);
			pending[s] = opts.length > 0 ? opts : null;
			decided[s] = opts.length == 0;
			decisions[s] = null;
			if (opts.length > 0) any = true;
		}
		if (!any) {
			nextTurn();
			return;
		}
		phase = Claims;
	}

	/** A seat takes a claim or passes (null). The table resolves once every seat with options has decided. **/
	public function decide(seat:Int, claim:Null<Claim>):Void {
		if (phase != Claims || pending[seat] == null || decided[seat]) throw 'Seat $seat has nothing to decide';
		if (claim != null) {
			var ok = false;
			for (o in pending[seat]) if (Type.enumEq(o, claim)) ok = true;
			if (!ok) throw 'Seat $seat cannot claim $claim';
		}
		decided[seat] = true;
		decisions[seat] = claim;
		if (claim != null) PlayLog.play(seat, "calls " + (switch (claim) {
			case Chi(low): 'chi (a run from the ${Tiles.name(low)})';
			case Ron: "ron";
			case other: Std.string(other).toLowerCase();
		}) + " on " + Tiles.name(lastDiscard.tile));
		// Passing up a win: furiten until your next discard (for the hand, after riichi).
		var couldWin = false;
		for (o in pending[seat]) if (o == Ron) couldWin = true;
		if (couldWin && claim != Ron) {
			if (players[seat].riichi) players[seat].furitenRiichi = true;
			else players[seat].furitenTemp = true;
		}
		for (s in 0...4) if (!decided[s]) return;
		resolveClaims();
	}

	/** Seats still to decide on the current discard. **/
	public function undecided():Array<Int> return [for (s in 0...4) if (pending[s] != null && !decided[s]) s];

	function resolveClaims():Void {
		var d = lastDiscard;
		for (s in 0...4) pending[s] = null;
		// A win beats everything; the first winner in turn order after the discarder takes it.
		var k = next(d.seat);
		for (_ in 0...3) {
			if (decisions[k] == Ron) {
				win(k, d.tile, d.seat);
				return;
			}
			k = next(k);
		}
		for (s in 0...4) switch decisions[s] {
			case Pon, Kan:
				takeDiscard(s, decisions[s]);
				return;
			default:
		}
		for (s in 0...4) switch decisions[s] {
			case Chi(_):
				takeDiscard(s, decisions[s]);
				return;
			default:
		}
		nextTurn();
	}

	function takeDiscard(seat:Int, claim:Claim):Void {
		var d = lastDiscard;
		var p = players[seat];
		var from = players[d.seat];
		from.claimed[from.claimed.length - 1] = true;
		anyCallThisHand = true;
		for (q in players) {
			q.ippatsu = false;
			q.firstTurn = false;
		}
		switch claim {
			case Pon:
				p.removeTiles(d.tile, 2);
				p.melds.push({type: Pung, kind: d.tile, from: d.seat, called: d.tile, added: false});
				turn = seat;
				phase = Act;
			case Kan:
				p.removeTiles(d.tile, 3);
				p.melds.push({type: Kong, kind: d.tile, from: d.seat, called: d.tile, added: false});
				kongMade(seat);
			case Chi(low):
				for (t in [low, low + 1, low + 2]) if (t != d.tile) p.hand.remove(t);
				p.melds.push({type: Chow, kind: low, from: d.seat, called: d.tile, added: false});
				turn = seat;
				phase = Act;
			default:
		}
		p.drawn = -1;
		lastDiscard = null;
	}

	function nextTurn():Void {
		turn = next(turn);
		phase = Draw;
	}

	/** In furiten: a tile this seat waits on is among its own discards, or it passed a win. **/
	public function furiten(seat:Int):Bool {
		var p = players[seat];
		if (p.furitenTemp || p.furitenRiichi) return true;
		var c = Tiles.counts(p.hand);
		for (w in Analysis.waits(c, p.melds.length)) if (p.discards.indexOf(w) >= 0) return true;
		return false;
	}

	// --- Ending a hand ---

	function win(seat:Int, tile:Int, from:Int):Void {
		var p = players[seat];
		if (from >= 0) {
			p.hand.push(tile);
			Tiles.sort(p.hand);
			var f = players[from];
			f.claimed[f.claimed.length - 1] = true;
		}
		var deltas = [0, 0, 0, 0];
		var lines:Array<String>, value:String;
		if (variant == Riichi) {
			var s = Scoring.riichi(this, seat, p.hand, tile, from < 0, from);
			lines = s.lines;
			value = s.label;
			var dealerWin = seat == dealer;
			inline function up(x:Float):Int return Std.int(Math.ceil(x / 100) * 100);
			if (from >= 0) {
				var pay = up(s.base * (dealerWin ? 6 : 4)) + 300 * honba;
				deltas[from] -= pay;
				deltas[seat] += pay;
			} else for (q in 0...4) if (q != seat) {
				var pay = up(s.base * (dealerWin || q == dealer ? 2 : 1)) + 100 * honba;
				deltas[q] -= pay;
				deltas[seat] += pay;
			}
			deltas[seat] += riichiSticks * 1000;
			riichiSticks = 0;
		} else {
			var s = Scoring.classic(this, seat, p.hand, tile, from < 0, from);
			lines = s.lines;
			value = s.label;
			if (from >= 0) {
				deltas[from] -= 2 * s.points;
				deltas[seat] += 2 * s.points;
			} else for (q in 0...4) if (q != seat) {
				deltas[q] -= s.points;
				deltas[seat] += s.points;
			}
		}
		for (q in 0...4) players[q].score += deltas[q];
		result = {
			winner: seat,
			from: from,
			tile: tile,
			title: from < 0 ? '${p.name} ${seat == 0 ? "win" : "wins"} by self-draw' : '${p.name} ${seat == 0 ? "win" : "wins"} on ${players[from].name}\'s discard',
			lines: lines,
			value: value,
			deltas: deltas,
			tenpai: [false, false, false, false],
		};
		endHand(seat == dealer);
	}

	function exhaustiveDraw():Void {
		PlayLog.note("The wall is empty: the hand is a draw");
		var tenpai = [for (q in players) Analysis.shanten(Tiles.counts(q.hand), q.melds.length) <= 0];
		var deltas = [0, 0, 0, 0];
		var ready = [for (i in 0...4) if (tenpai[i]) i];
		if (variant == Riichi && ready.length > 0 && ready.length < 4) {
			// Noten payments: 3,000 in all, from the players not ready to those who are.
			for (i in 0...4) deltas[i] = tenpai[i] ? Std.int(3000 / ready.length) : -Std.int(3000 / (4 - ready.length));
			for (i in 0...4) players[i].score += deltas[i];
		}
		result = {
			winner: -1,
			from: -1,
			tile: -1,
			title: "The wall is empty: a drawn hand",
			lines: [for (i in 0...4) '${players[i].name}: ${tenpai[i] ? "ready" : "not ready"}'],
			value: "",
			deltas: deltas,
			tenpai: tenpai,
		};
		endHand(variant == Classic || tenpai[dealer], true);
	}

	function endHand(dealerKeeps:Bool, draw = false):Void {
		for (p in players) p.drawn = -1;
		if (variant == Riichi) honba = dealerKeeps || draw ? honba + 1 : 0;
		if (!dealerKeeps) {
			dealer = next(dealer);
			dealersPassed++;
		}
		var busted = false;
		for (p in players) if (variant == Riichi && p.score < 0) busted = true;
		phase = dealersPassed >= 4 || busted || handNumber >= MAX_HANDS ? GameOver : HandOver;
	}

	/** Seats in final order, best first. **/
	public function standings():Array<Int> {
		var order = [0, 1, 2, 3];
		order.sort((a, b) -> players[b].score - players[a].score);
		return order;
	}

	/** Dora tiles currently in play (face-up indicators). **/
	public function dora():Array<Int> return [for (i in 0...doraShown) Tiles.doraFrom(indicators[i])];

	/** The round and hand, like "East 2" (plus honba in Riichi). **/
	public function roundLabel():String {
		var dealerNumber = dealersPassed + 1;
		return 'East ${Std.int(Math.min(4, dealerNumber))}' + (variant == Riichi && honba > 0 ? ', $honba honba' : "");
	}
}
