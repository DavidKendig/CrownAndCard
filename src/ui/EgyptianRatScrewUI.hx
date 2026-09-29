// SPDX-License-Identifier: AGPL-3.0-or-later
package ui;

import cards.Card;
import games.parlour.EgyptianRatScrew;
import ui.ButtonGlyph;
import ui.TableKit;

/**
	Egyptian Rat Screw against three quick hands from below stairs. Playing
	cards is turn-based (or forced by a face-card challenge); slapping is
	real time, and anyone (even a player out of cards) can slap back in.
**/
class EgyptianRatScrewUI extends CardGameScreen {
	static final NAMES = ["You", "Tuppence Fitch", "Sir Reggie", "Rafe Vasquez"];

	/** Reaction time: fastest possible, plus up to this much more (seconds). **/
	static final REACTION = [[0.0, 0.0], [0.28, 0.30], [0.50, 0.55], [0.35, 0.38]];

	/** Chance per frame-tick to false-slap a near-miss (doubles-ish top cards). **/
	static final JUMPY = [0.0, 0.02, 0.05, 0.03];

	static inline var PLAY_SECONDS = 0.6;
	static inline var RESULT_SECONDS = 1.0;

	final shuffle:rng.IRng;
	final aiRng:rng.IRng;
	var game:EgyptianRatScrew;
	var timer = 0.0;
	var pause = 0.0;
	var armedLen = -1;
	var slapAt:Array<Float> = [];
	var patternTime = 0.0;
	var note = "";

	public function new(parent:h2d.Object, faces:CardFaces, shuffle:rng.IRng, aiRng:rng.IRng) {
		super(parent, faces, "war");
		this.shuffle = shuffle;
		this.aiRng = aiRng;
		newGame();
	}

	function newGame():Void {
		game = new EgyptianRatScrew(4, shuffle);
		timer = pause = patternTime = 0;
		armedLen = -1;
		note = "Cards dealt all around. Slap the jacks, doubles, sandwiches and marriages!";
	}

	override public function status():String {
		return 'egyptian rat screw cards ${[for (i in 0...4) game.count(i)].join("/")} winner ${game.winner}';
	}

	override public function sit():Void {
		confirmLeave = false;
		if (game.winner >= 0) newGame();
	}

	override public function update(w:Int, dt:Float, input:MenuInput):Void {
		var cx = w / 2;
		begin(w);
		drawTable(w, cx);
		var over = game.winner >= 0;
		if (leaveCheck(input, !over, "This game of Egyptian Rat Screw will be abandoned.")) {
			end(cx);
			return;
		}
		if (over) {
			title = game.winner == 0 ? "YOU WIN EVERY CARD" : '${NAMES[game.winner].toUpperCase()} WINS';
			body = game.winner == 0 ? "Fastest hands below stairs." : "Better luck next deal.";
			var p = offer(["Play again", "Leave table"], input);
			if (p == "Play again") newGame() else if (p == "Leave table") leave();
			end(cx);
			return;
		}

		// Re-arm the NPCs' reactions whenever the pile actually changes.
		if (game.center.length != armedLen) {
			armedLen = game.center.length;
			patternTime = 0;
			var pattern = game.slappable();
			if (pattern != "") slapAt = [for (i in 0...4) REACTION[i][0] + aiRng.nextFloat() * REACTION[i][1]] else slapAt = [];
		}

		var click = takeClick();
		var slapped = input.alt || click == 100;
		if (pause > 0) pause -= dt;
		else if (slapped) slap(0);
		else if (slapAt.length > 0) {
			patternTime += dt;
			var first = -1;
			for (i in 1...4) if (patternTime >= slapAt[i] && (first < 0 || slapAt[i] < slapAt[first])) first = i;
			if (first >= 0) slap(first);
		} else {
			patternTime += dt;
			for (i in 1...4) if (game.count(i) > 0 && aiRng.chance(JUMPY[i] * dt)) {
				slap(i);
				break;
			}
			if (game.turn == 0 && game.count(0) > 0) {
				if (input.confirm || click == 101) {
					playCard();
				}
			} else if (game.count(game.turn) > 0) {
				timer += dt;
				if (timer >= PLAY_SECONDS) {
					timer = 0;
					playCard();
				}
			}
		}
		var canPlay = game.turn == 0 && game.count(0) > 0 && pause <= 0 && slapAt.length == 0;
		if (canPlay) hint(Confirm, "Play a card");
		hint(Alt, "Slap!");
		if (game.challenge != null) {
			var c = game.challenge;
			label('${NAMES[c.responder]} must beat it: ${c.remaining} chance${c.remaining == 1 ? "" : "s"} left.', cx, 196, TableKit.GOLD, 1);
		} else if (note != "") label(note, cx, 196, TableKit.GOLD, 1);
		end(cx);
	}

	function playCard():Void {
		var card = game.play();
		note = card.rank >= Card.JACK ? '${cardName(card)} challenges the next player!' : "";
		timer = 0;
	}

	static function cardName(c:Card):String {
		var rank = switch c.rank {
			case Card.JACK: "jack";
			case Card.QUEEN: "queen";
			case Card.KING: "king";
			case Card.ACE: "ace";
			case r: Std.string(r);
		}
		var suit = switch c.suit {
			case Clubs: "clubs";
			case Diamonds: "diamonds";
			case Hearts: "hearts";
			case Spades: "spades";
		}
		return 'The $rank of $suit';
	}

	function slap(seat:Int):Void {
		var who = NAMES[seat];
		var you = seat == 0;
		note = switch game.slap(seat) {
			case Empty: "";
			case Won(n, pattern): '$who ${you ? "slap" : "slaps"} $pattern and ${you ? "take" : "takes"} $n cards!';
			case Penalty: '$who ${you ? "slap" : "slaps"} too soon: a card burns to the bottom.';
			case NothingToPay: '$who ${you ? "slap" : "slaps"} too soon, with nothing left to pay.';
		}
		if (note != "") pause = RESULT_SECONDS;
		armedLen = -2; // force a re-check next frame, even if the pile length happens to match
		timer = 0;
	}

	function drawTable(w:Int, cx:Float):Void {
		var n = game.center.length;
		for (k in Std.int(Math.max(0, n - 4))...n) {
			var depth = n - 1 - k;
			card(faces.face(game.center[k].card), cx - 20 - depth * 6, 118 - depth * 3);
		}
		if (n == 0) pile(0, cx - 20, 118, false);
		hit(100, cx - 44, 106, 88, 76);
		label('${n} in the center', cx, 178, TableKit.DIM, 1);
		var spots = [{x: cx - 20, y: 236.0}, {x: 40.0, y: 118.0}, {x: cx - 20, y: 34.0}, {x: w - 80.0, y: 118.0}];
		for (i in 0...4) {
			var s = spots[i];
			pile(game.count(i), s.x, s.y);
			var color = game.count(i) == 0 ? TableKit.DIM : game.turn == i ? TableKit.GOLD : TableKit.CREAM;
			var tag = game.count(i) == 0 ? " (slap only)" : "";
			switch i {
				case 0: label(NAMES[i] + tag, cx, 222, color, 1);
				case 2: label(NAMES[i] + tag, cx, 20, color, 1);
				default: label(NAMES[i] + tag, s.x + 20, 102, color, 1);
			}
		}
		hit(101, cx - 20, 236, CardFaces.W, CardFaces.H);
	}
}
