// SPDX-License-Identifier: AGPL-3.0-or-later
package games.mahjong;

import games.mahjong.MahjongGame;

/** One decision on your own turn. **/
enum TurnChoice {
	Win;
	DeclareKong(kind:Int);
	Discard(tile:Int, riichi:Bool);
}

/**
	Normal-difficulty Mahjong opponents (§9.3). Tile efficiency: discard to
	the lowest shanten, then keep the most tiles that improve the hand, and
	shed isolated honors and terminals first. Far from ready while someone is
	in riichi, it throws safe tiles (that player's own discards). It always
	takes a win, declares riichi when ready, and calls only to get closer to
	ready (in Riichi, only when the call keeps a yaku in reach).
	Deterministic: no random stream needed.
**/
class MahjongAi {
	public static function turn(game:MahjongGame, seat:Int):TurnChoice {
		var p = game.players[seat];
		if (game.canTsumo(seat)) return Win;
		if (p.riichi) return Discard(p.drawn, false);
		var melds = p.melds.length;
		var before = Analysis.shanten(Tiles.counts(p.hand), melds);
		for (k in game.kongOptions(seat)) {
			// Kong only when it doesn't set the hand back.
			var c = Tiles.counts(p.hand);
			c[k] -= c[k] == 4 ? 4 : 1;
			if (Analysis.shanten(c, melds + (p.count(k) == 4 ? 1 : 0)) <= before) return DeclareKong(k);
		}
		var tile = bestDiscard(game, seat);
		var riichi = game.canRiichi(seat) && game.riichiDiscards(seat).indexOf(tile) >= 0;
		return Discard(tile, riichi);
	}

	public static function bestDiscard(game:MahjongGame, seat:Int):Int {
		var p = game.players[seat];
		var legal = game.legalDiscards(seat);
		var melds = p.melds.length;
		var counts = Tiles.counts(p.hand);
		var visible = visibleCounts(game, seat);
		var threat = false;
		for (s in 0...4) if (s != seat && game.players[s].riichi) threat = true;
		var farFromReady = threat && before(game, seat) >= 2;
		var best = legal[0], bestShanten = 99, bestUkeire = -1, bestSafe = false, bestIsolation = -1;
		for (t in legal) {
			counts[t]--;
			var sh = Analysis.shanten(counts, melds);
			var uk = sh <= 2 ? ukeire(counts, melds, sh, visible) : 0;
			counts[t]++;
			var safe = threat && isSafe(game, seat, t);
			var iso = isolation(counts, t);
			// Far from ready against a riichi: safety first.
			var better = if (farFromReady && safe != bestSafe) safe
				else if (sh != bestShanten) sh < bestShanten
				else if (uk != bestUkeire) uk > bestUkeire
				else iso > bestIsolation;
			if (better) {
				best = t;
				bestShanten = sh;
				bestUkeire = uk;
				bestSafe = safe;
				bestIsolation = iso;
			}
		}
		return best;
	}

	static function before(game:MahjongGame, seat:Int):Int {
		var p = game.players[seat];
		var c = Tiles.counts(p.hand);
		// Shanten of the 13 best tiles: a 14-tile hand is one discard from what it can be.
		var best = 99;
		for (k in 0...Tiles.KINDS) if (c[k] > 0) {
			c[k]--;
			best = Std.int(Math.min(best, Analysis.shanten(c, p.melds.length)));
			c[k]++;
		}
		return best;
	}

	/** How many unseen tiles would lower the shanten. **/
	static function ukeire(counts:Array<Int>, melds:Int, current:Int, visible:Array<Int>):Int {
		var total = 0;
		for (k in 0...Tiles.KINDS) {
			var left = 4 - visible[k] - counts[k];
			if (left <= 0) continue;
			counts[k]++;
			if (Analysis.shanten(counts, melds) < current) total += left;
			counts[k]--;
		}
		return total;
	}

	/** Loose tiles go first: honors and terminals with no neighbors score highest. **/
	static function isolation(counts:Array<Int>, t:Int):Int {
		var score = 0;
		if (counts[t] > 1) return 0;
		if (Tiles.isHonor(t)) score += 3;
		else {
			if (Tiles.isTerminal(t)) score += 1;
			for (d in [-2, -1, 1, 2]) {
				var n = t + d;
				if (n >= 0 && Tiles.isSuited(n) && Tiles.suit(n) == Tiles.suit(t) && counts[n] > 0) score -= 1;
			}
			score += 2;
		}
		return score;
	}

	static function isSafe(game:MahjongGame, seat:Int, t:Int):Bool {
		for (s in 0...4) if (s != seat && game.players[s].riichi && game.players[s].discards.indexOf(t) < 0) return false;
		return true;
	}

	/** Tiles this seat can see: every discard, every meld and its own hand. **/
	static function visibleCounts(game:MahjongGame, seat:Int):Array<Int> {
		var c = [for (_ in 0...Tiles.KINDS) 0];
		for (q in game.players) {
			for (t in q.discards) c[t]++;
			for (m in q.melds) switch m.type {
				case Chow:
					c[m.kind]++;
					c[m.kind + 1]++;
					c[m.kind + 2]++;
				case Pung:
					c[m.kind] += 3;
				default:
					c[m.kind] += 4;
			}
		}
		if (game.variant == Riichi) for (i in 0...game.doraShown) c[game.indicators[i]]++;
		return c;
	}

	/** Which claim (if any) to make on the current discard. **/
	public static function claim(game:MahjongGame, seat:Int):Null<Claim> {
		var options = game.pending[seat];
		if (options == null) return null;
		for (o in options) if (o == Ron) return Ron;
		var p = game.players[seat];
		var t = game.lastDiscard.tile;
		var counts = Tiles.counts(p.hand);
		var now = Analysis.shanten(counts, p.melds.length);
		var best:Null<Claim> = null, bestShanten = now;
		for (o in options) {
			var c = counts.copy();
			var kind = -1;
			switch o {
				case Pon:
					c[t] -= 2;
					kind = t;
				case Chi(low):
					for (k in [low, low + 1, low + 2]) if (k != t) c[k]--;
				default:
					continue; // exposed kongs aren't worth it for this AI
			}
			// After calling, one tile goes: the best discard's shanten.
			var after = 99;
			for (k in 0...Tiles.KINDS) if (c[k] > 0) {
				c[k]--;
				after = Std.int(Math.min(after, Analysis.shanten(c, p.melds.length + 1)));
				c[k]++;
			}
			if (after >= bestShanten) continue;
			if (game.variant == Riichi && !keepsYaku(game, seat, o, t)) continue;
			best = o;
			bestShanten = after;
		}
		return best;
	}

	/** Riichi: an open hand needs a yaku. This AI goes for a value pung, or all simples. **/
	static function keepsYaku(game:MahjongGame, seat:Int, o:Claim, t:Int):Bool {
		var seatW = Tiles.EAST + game.seatWind(seat), roundW = Tiles.EAST + game.roundWind;
		if (o == Pon && (Tiles.isDragon(t) || t == seatW || t == roundW)) return true;
		var p = game.players[seat];
		for (m in p.melds) if (m.type != Chow && (Tiles.isDragon(m.kind) || m.kind == seatW || m.kind == roundW)) return true;
		// All simples: every tile in hand and melds simple (allowing one stray to discard).
		var strays = 0;
		for (k in p.hand) if (!Tiles.isSimple(k)) strays++;
		for (m in p.melds) if (m.type == Chow ? (Tiles.rank(m.kind) == 1 || Tiles.rank(m.kind) == 7) : !Tiles.isSimple(m.kind)) return false;
		var callOk = switch o {
			case Chi(low): Tiles.rank(low) >= 2 && Tiles.rank(low) <= 6;
			default: Tiles.isSimple(t);
		}
		return callOk && strays <= 1;
	}
}
