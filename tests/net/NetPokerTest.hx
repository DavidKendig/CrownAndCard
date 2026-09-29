// SPDX-License-Identifier: AGPL-3.0-or-later
package net;

import games.poker.PokerTable;
import net.NetLink;
import net.PokerHost.Stage;
import utest.Assert;

class NetPokerTest extends utest.Test {
	static inline var SEED_A = "00112233445566778899aabbccddeeff00112233445566778899aabbccddeeff";
	static inline var SEED_B = "ffeeddccbbaa99887766554433221100ffeeddccbbaa99887766554433221100";

	function testCommitmentsAndHandSeeds() {
		var c = Fairness.commit(SEED_A);
		Assert.equals(64, c.length);
		Assert.notEquals(SEED_A, c);
		Assert.equals(c, Fairness.commit(SEED_A));
		Assert.isTrue(Fairness.validSeed(Fairness.newSeed()));
		Assert.isFalse(Fairness.validSeed("abc"));
		Assert.isFalse(Fairness.validSeed(SEED_A.toUpperCase()));
		Assert.isFalse(Fairness.validSeed(42));
		// Every guest's seed changes the deck; junk adds nothing.
		var base = Fairness.handSeed(SEED_A, []).toHex();
		Assert.notEquals(base, Fairness.handSeed(SEED_A, [SEED_B]).toHex());
		Assert.equals(base, Fairness.handSeed(SEED_A, ["", "not a seed"]).toHex());
		Assert.notEquals(Fairness.handSeed(SEED_A, [SEED_B, ""]).toHex(), Fairness.handSeed(SEED_B, [SEED_A, ""]).toHex());
	}

	/** A host, two guests and a house player: `hands` full hands, everyone calling or checking. **/
	function play(hands:Int, ?beforeEachStep:Int->Void):{hub:LoopbackHub, host:PokerHost, guests:Array<PokerGuest>, audits:Array<String>} {
		var hub = new LoopbackHub();
		var host = new PokerHost(hub.join("Ada"), "Ada");
		var guests = [for (name in ["Bea", "Cy"]) new PokerGuest(hub.join(name))];
		hub.flush();
		host.addHouse();
		hub.flush();
		var audits = [];
		for (h in 0...hands) {
			host.deal();
			var step = 0;
			while (host.stage != Stage.HandOver && step < 5000) {
				if (beforeEachStep != null) beforeEachStep(step);
				step++;
				hub.flush();
				host.update(1.0);
				if (host.stage == Stage.Playing && host.table.toAct == 0)
					host.act(host.table.legal(0).canCheck ? Check : Call);
				for (g in guests) if (g.view != null && g.view.legal != null && g.view.stage == "playing")
					g.act(g.view.legal.canCheck ? Check : Call);
				hub.flush();
			}
			Assert.equals(Stage.HandOver, host.stage);
			hub.flush();
			for (g in guests) if (g.closed == null) audits.push(g.audit);
		}
		return {hub: hub, host: host, guests: guests, audits: audits};
	}

	function testGuestsVerifyEveryHand() {
		var r = play(4);
		Assert.equals(8, r.audits.length);
		for (a in r.audits) Assert.equals("ok", a);
		// Both guests' checks reached the host.
		Assert.equals("ok", r.host.checks.get(1));
		Assert.equals("ok", r.host.checks.get(2));
		// Chips are conserved.
		var total = 0;
		for (s in r.host.seats) total += s.stack;
		Assert.equals(4 * NetPoker.STACK, total);
	}

	function testGuestsNeverSeeHiddenCards() {
		var hub = new LoopbackHub();
		var host = new PokerHost(hub.join("Ada"), "Ada");
		var bea = new PokerGuest(hub.join("Bea"));
		hub.flush();
		host.addHouse();
		host.deal();
		hub.flush();
		Assert.equals(Stage.Playing, host.stage);
		var seats:Array<Dynamic> = bea.view.seats;
		var mine:Array<String> = seats[bea.view.you].cards;
		Assert.equals(2, mine.length);
		for (c in mine) Assert.notEquals("", c);
		for (i in 0...seats.length) if (i != bea.view.you) {
			var cards:Array<String> = seats[i].cards;
			for (c in cards) Assert.equals("", c);
		}
		// Five seats' worth of cards are hidden, and none of them appear anywhere in the message.
		var json = haxe.Json.stringify(bea.view);
		for (i in 0...host.table.seats.length) if (i != bea.view.you)
			for (c in host.table.seats[i].cards) Assert.isFalse(json.indexOf('"${c.code}"') >= 0);
	}

	function testGuestsActOnlyForTheirOwnSeatInTurn() {
		var hub = new LoopbackHub();
		var host = new PokerHost(hub.join("Ada"), "Ada");
		var bea = new PokerGuest(hub.join("Bea"));
		var cyLink = hub.join("Cy");
		var cy = new PokerGuest(cyLink);
		hub.flush();
		host.deal();
		hub.flush();
		var toAct = host.table.toAct;
		// Cy tries to move for whoever is up (and for the host's seat), out of turn.
		cyLink.send(Net.HOST, {t: "act", hand: host.hand, seat: toAct, a: "fold"});
		cyLink.send(Net.HOST, {t: "act", hand: host.hand, seat: 0, a: "fold"});
		hub.flush();
		if (toAct != 2) {
			Assert.equals(toAct, host.table.toAct);
			for (s in host.table.seats) Assert.isFalse(s.folded);
		}
		Assert.pass();
	}

	function testTamperingIsCaught() {
		// Record one real hand's reveal.
		var hub = new LoopbackHub();
		var host = new PokerHost(hub.join("Ada"), "Ada");
		var spyLink = hub.join("Bea");
		var reveal:Dynamic = null, commit = "";
		var bea = new PokerGuest(spyLink);
		var handler = spyLink.onEvent;
		spyLink.onEvent = e -> {
			switch e {
				case Message(_, body) if (body.t == "reveal"): reveal = body;
				case Message(_, body) if (body.t == "commit"): commit = body.commit;
				default:
			}
			handler(e);
		};
		hub.flush();
		host.addHouse();
		host.deal();
		var guard = 0;
		while (host.stage != Stage.HandOver && guard++ < 2000) {
			hub.flush();
			host.update(1.0);
			if (host.stage == Stage.Playing && host.table.toAct == 0) host.act(host.table.legal(0).canCheck ? Check : Call);
			if (bea.view != null && bea.view.legal != null && bea.view.stage == "playing") bea.act(bea.view.legal.canCheck ? Check : Call);
		}
		hub.flush();
		Assert.equals("ok", bea.audit);
		Assert.notNull(reveal);
		var copy = () -> haxe.Json.parse(haxe.Json.stringify(reveal));
		// The honest record replays.
		Assert.isTrue(NetPoker.replay(copy(), commit).phase == games.poker.PokerTable.Phase.HandOver);
		// A different host seed than the one committed to.
		var r1:Dynamic = copy();
		r1.hostSeed = SEED_A;
		Assert.raises(() -> NetPoker.replay(r1, commit));
		// A swapped guest seed changes the deck, so the dealt cards stop matching.
		var r2:Dynamic = copy();
		var seeds:Array<String> = r2.seeds;
		seeds[1] = SEED_B;
		var dealt = NetPoker.codes(NetPoker.replay(copy(), commit).seats[1].cards).join(" ");
		// (The house player's moves usually stop matching too, which is also caught.)
		var caught = try NetPoker.codes(NetPoker.replay(r2, commit).seats[1].cards).join(" ") != dealt catch (_:Dynamic) true;
		Assert.isTrue(caught);
		// A house player's move that the house AI wouldn't have made.
		var r3:Dynamic = copy();
		var kinds:Array<String> = r3.setup.kinds;
		var actions:Array<Dynamic> = r3.actions;
		for (a in actions) if (kinds[a.seat] == "house" && a.a != "forfeit") {
			a.a = a.a == "fold" ? "call" : "fold";
			break;
		}
		Assert.raises(() -> NetPoker.replay(r3, commit));
	}

	function testGettingUpAndComingBack() {
		var hub = new LoopbackHub();
		var host = new PokerHost(hub.join("Ada"), "Ada");
		var beaLink = hub.join("Bea");
		var bea = new PokerGuest(beaLink);
		hub.flush();
		Assert.equals(1, [for (s in host.seats) if (s.kind == Human && s.peer == beaLink.id) s].length);
		bea.leave();
		hub.flush();
		Assert.equals(-1, [for (s in host.seats) s.peer].indexOf(beaLink.id));
		// Reopening the game (a new PokerGuest on the same connection) seats her again.
		var again = new PokerGuest(beaLink);
		hub.leave(hub.join("Cy")); // any roster change reaches the new guest
		hub.flush();
		Assert.notNull(again.view);
		// The host closing the table tells everyone.
		host.close();
		hub.flush();
		Assert.equals("The host left the table.", again.closed);
	}

	function testLeavingMidHandForfeits() {
		// Cy walks away during the first betting round.
		var hub = new LoopbackHub();
		var host = new PokerHost(hub.join("Ada"), "Ada");
		var bea = new PokerGuest(hub.join("Bea"));
		var cyLink = hub.join("Cy");
		var cy = new PokerGuest(cyLink);
		hub.flush();
		host.deal();
		hub.flush();
		hub.leave(cyLink);
		hub.flush();
		var guard = 0;
		while (host.stage != Stage.HandOver && guard++ < 2000) {
			host.update(1.0);
			if (host.stage == Stage.Playing && host.table.toAct == 0) host.act(host.table.legal(0).canCheck ? Check : Call);
			if (bea.view != null && bea.view.legal != null && bea.view.stage == "playing") bea.act(bea.view.legal.canCheck ? Check : Call);
			hub.flush();
		}
		Assert.equals(Stage.HandOver, host.stage);
		Assert.isTrue(host.table.seats[2].folded);
		Assert.equals("ok", bea.audit);
		// Cy's seat opens for the next hand.
		host.deal();
		Assert.equals("open", (host.seats[2].kind : String));
	}

	function testSeatsAndLobby() {
		var hub = new LoopbackHub();
		var host = new PokerHost(hub.join("Ada"), "Ada");
		Assert.isFalse(host.canDeal());
		host.addHouse();
		Assert.isTrue(host.canDeal());
		host.removeHouse();
		Assert.equals(0, host.houseCount());
		var links = [for (i in 0...7) hub.join('P$i')];
		hub.flush();
		// Connected isn't seated: a guest sits down when its game says hello.
		Assert.equals(5, host.openCount());
		var full = [];
		for (l in links) {
			l.onEvent = e -> switch e {
				case Message(_, body) if (body.t == "full"): full.push(l.id);
				default:
			};
			l.send(Net.HOST, {t: "hello"});
		}
		hub.flush();
		Assert.same([links[5].id, links[6].id], full);
		// Six seats: the host and five guests; the seventh waits outside.
		Assert.equals(0, host.openCount());
		Assert.equals(-1, [for (s in host.seats) s.peer].indexOf(links[5].id));
	}
}

