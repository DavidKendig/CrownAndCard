// SPDX-License-Identifier: AGPL-3.0-or-later
package games;

import games.mahjong.Analysis;
import games.mahjong.MahjongAi;
import games.mahjong.MahjongGame;
import games.mahjong.Scoring;
import games.mahjong.Tiles;
import rng.ChaChaRng;
import utest.Assert;

class MahjongTest extends utest.Test {
	/** "123m 55p 777z": digits then a suit (m characters, p dots, s bamboo, z honors 1-7 = E S W N white green red). **/
	static function t(code:String):Array<Int> {
		var out = [];
		for (part in code.split(" ")) {
			if (part == "") continue;
			var suit = part.charAt(part.length - 1);
			var base = switch suit {
				case "m": 0;
				case "p": 9;
				case "s": 18;
				default: 27;
			}
			for (i in 0...part.length - 1) out.push(base + Std.parseInt(part.charAt(i)) - 1);
		}
		Tiles.sort(out);
		return out;
	}

	static function c(code:String) return Tiles.counts(t(code));

	static function rng(label:String) return ChaChaRng.fromSeed(TestUtil.countingSeed()).fork('test-mahjong/$label');

	function testCompleteHands() {
		Assert.isTrue(Analysis.isComplete(c("123m 456p 789s 234s 55p"), 0));
		Assert.isTrue(Analysis.isComplete(c("11m 22m 33p 44p 55s 66s 77z"), 0)); // seven pairs
		Assert.isTrue(Analysis.isComplete(c("19m 19p 19s 1234567z 1z"), 0)); // thirteen orphans
		Assert.isFalse(Analysis.isComplete(c("123m 456p 789s 234s 56p"), 0));
		// Four of a kind isn't two pairs.
		Assert.isFalse(Analysis.isSevenPairs(c("1111m 22m 33p 44p 55s 66s"), 0));
		// With one set melded, 11 concealed tiles complete the hand.
		Assert.isTrue(Analysis.isComplete(c("456p 789s 234s 55p"), 1));
	}

	function testShantenAndWaits() {
		Assert.equals(-1, Analysis.shanten(c("123m 456p 789s 234s 55p"), 0));
		Assert.equals(0, Analysis.shanten(c("123m 456p 789s 23s 55p"), 0));
		Assert.same(t("1s 4s"), Analysis.waits(c("123m 456p 789s 23s 55p"), 0));
		Assert.same(t("5p 6s"), Analysis.waits(c("123m 456p 789s 55p 66s"), 0)); // a double-pair (shanpon) wait
		Assert.equals(1, Analysis.shanten(c("123m 456p 78s 23s 55p 9m"), 0));
		Assert.equals(0, Analysis.shanten(c("11m 22m 33p 44p 55s 66s 7z"), 0)); // seven pairs, ready
	}

	/** A table where seat 0 holds `hand` (drawn = `win` for self-draws), dealer is seat 1, dora is none of these tiles. **/
	function table(variant:Variant, hand:String):MahjongGame {
		var g = new MahjongGame(variant, ["A", "B", "C", "D"], rng('table/$variant'));
		g.startHand();
		var p = g.players[0];
		p.hand.resize(0);
		for (x in t(hand)) p.hand.push(x);
		p.firstTurn = false;
		for (i in 0...5) {
			g.indicators[i] = Tiles.WHITE; // dora = green dragon, absent from the test hands
			g.ura[i] = Tiles.WHITE;
		}
		return g;
	}

	function testRiichiPinfuTsumo() {
		var g = table(Riichi, "123m 456p 789s 234s 55p");
		var s = Scoring.riichi(g, 0, g.players[0].hand, t("4s")[0], true, -1);
		Assert.isTrue(s.valid);
		Assert.equals(2, s.han); // menzen tsumo + pinfu
		Assert.equals(20, s.fu);
		Assert.equals(320.0, s.base);
	}

	function testRiichiFuForClosedRonWithKanchanAndTerminalPung() {
		// 111m concealed (8 fu), kanchan 4-6s on 5s (2 fu), closed ron (10 fu): 40 fu. Yaku: none but... add riichi.
		var g = table(Riichi, "111m 456p 789s 456s 22p");
		g.players[0].riichi = true;
		var s = Scoring.riichi(g, 0, g.players[0].hand, t("5s")[0], false, 2);
		Assert.isTrue(s.valid);
		Assert.equals(40, s.fu);
		Assert.equals(1, s.han);
	}

	function testOpenHandNeedsAYaku() {
		var g = table(Riichi, "456p 789s 234s 55p");
		g.players[0].melds.push({type: Chow, kind: 0, from: 3}); // 123m chowed
		var s = Scoring.riichi(g, 0, g.players[0].hand, t("4s")[0], false, 2);
		Assert.isFalse(s.valid);
		// A red dragon pung is a yaku.
		var h = table(Riichi, "456p 789s 234s 55p");
		h.players[0].melds.push({type: Pung, kind: Tiles.RED, from: 2});
		Assert.isTrue(Scoring.riichi(h, 0, h.players[0].hand, t("4s")[0], false, 2).valid);
	}

	function testSevenPairsAndOrphans() {
		var g = table(Riichi, "11m 22m 33p 44p 55s 66s 77s");
		var s = Scoring.riichi(g, 0, g.players[0].hand, t("7s")[0], false, 2);
		Assert.equals(25, s.fu);
		Assert.isTrue(s.han >= 2);
		var k = table(Riichi, "19m 19p 19s 1234567z 1z");
		Assert.equals(1, Scoring.riichi(k, 0, k.players[0].hand, Tiles.EAST, false, 2).yakuman);
	}

	function testClassicFaan() {
		var g = table(Classic, "111m 555p 999s 222s 77z");
		g.players[0].flowers.push(Tiles.FIRST_BONUS + g.seatWind(0)); // own flower
		var s = Scoring.classic(g, 0, g.players[0].hand, t("2s")[0], false, 2);
		// All pungs 3, concealed 1, own flower 1: 5 faan.
		Assert.equals(5, s.faan);
		Assert.equals(24, s.points);
		var f = table(Classic, "123p 456p 789p 111p 99p");
		Assert.isTrue(Scoring.classic(f, 0, f.players[0].hand, t("9p")[0], true, -1).faan >= 7); // pure one suit
	}

	function testClaimsFollowTheRules() {
		var g = new MahjongGame(Riichi, ["A", "B", "C", "D"], rng("claims"));
		g.startHand();
		// Seat 0 (the dealer) draws and discards 5 dots; seat 1 (next) may chow, seat 2 only pung.
		g.draw();
		var p0 = g.players[0];
		p0.hand.resize(0);
		for (x in t("5p 123m 456m 789m 11s 22s")) p0.hand.push(x);
		p0.drawn = t("5p")[0];
		g.players[1].hand.resize(0);
		for (x in t("34p 111m 222s 333s 7z")) g.players[1].hand.push(x);
		g.players[2].hand.resize(0);
		for (x in t("55p 1m 2m 3m 4m 5m 6m 7m 8m 9m 1s 2s")) g.players[2].hand.push(x);
		g.players[3].hand.resize(0);
		for (x in t("67p 1z 2z 3z 4z 5z 6z 7z 1s 2s 3s 4s")) g.players[3].hand.push(x);
		g.discard(0, t("5p")[0]);
		Assert.equals(Claims, g.phase);
		var chi = false;
		for (o in g.claimOptions(1)) switch o {
			case Chi(_): chi = true;
			default:
		}
		Assert.isTrue(chi);
		Assert.isTrue(g.claimOptions(2).indexOf(Pon) >= 0);
		// Seat 3 is before the discarder: no chow for it.
		Assert.equals(0, g.claimOptions(3).length);
		// Pung beats chow.
		g.decide(1, Chi(t("3p")[0]));
		g.decide(2, Pon);
		Assert.equals(2, g.turn);
		Assert.equals(Act, g.phase);
		Assert.equals(1, g.players[2].melds.length);
		// The table turns the called tile toward the seat it came from.
		var m = g.players[2].melds[0];
		Assert.equals(0, m.from);
		Assert.equals(t("5p")[0], m.called);
	}

	function testRiichiStakesAThousand() {
		var g = new MahjongGame(Riichi, ["A", "B", "C", "D"], rng("riichi"));
		g.startHand();
		g.draw();
		var p = g.players[0];
		p.hand.resize(0);
		for (x in t("123m 456p 789s 23s 55p 9m")) p.hand.push(x);
		p.drawn = t("9m")[0];
		Assert.isTrue(g.canRiichi(0));
		g.discard(0, t("9m")[0], true);
		Assert.isTrue(p.riichi);
		Assert.equals(24000, p.score);
		Assert.equals(1, g.riichiSticks);
	}

	/** AI-only hands: legal play throughout, and the points balance. **/
	function testAiHandsRun() {
		for (variant in [Riichi, Classic]) {
			var g = new MahjongGame(variant, ["A", "B", "C", "D"], rng('sim/$variant'));
			var total = 0;
			for (q in g.players) total += q.score;
			for (_ in 0...2) {
				if (g.phase == GameOver) break;
				g.startHand();
				var guard = 0;
				while ((g.phase == Draw || g.phase == Act || g.phase == Claims) && guard++ < 2000) {
					switch g.phase {
						case Draw:
							g.draw();
						case Act:
							switch MahjongAi.turn(g, g.turn) {
								case Win: g.tsumo(g.turn);
								case DeclareKong(k): g.kong(g.turn, k);
								case Discard(tile, riichi): g.discard(g.turn, tile, riichi);
							}
						case Claims:
							var s = g.undecided()[0];
							g.decide(s, MahjongAi.claim(g, s));
						default:
					}
				}
				Assert.isTrue(g.phase == HandOver || g.phase == GameOver);
				var sum = g.riichiSticks * 1000;
				for (q in g.players) sum += q.score;
				Assert.equals(total, sum);
			}
		}
	}
}
