// SPDX-License-Identifier: AGPL-3.0-or-later
package ui;

import cards.Card;
import games.spades.SpadesGame;
import games.spades.SpadesAi;
import ui.ButtonGlyph;
import ui.TableKit;

/**
	Seated Spades view (§5.7): the player (South) and Professor Oyelaran
	(North) against the Vasquez twins, Rosalind (West) and Rafe (East) (§8.1).
	The other hands show as card backs at the table's edges.
**/
class SpadesTableUI extends h2d.Object {
	public static final NAMES = ["You", "Rosalind", "Prof. Oyelaran", "Rafe"];

	static inline var AI_SECONDS = 0.6;
	static inline var TRICK_HOLD_SECONDS = 1.2;

	public var onLeave:Void->Void = () -> {};

	public var status(get, never):String;

	final game = new SpadesGame();
	final rng:rng.IRng;
	final faces:CardFaces;
	final bg:h2d.Graphics;
	final tableArt:TableSurface;
	final cardLayer:h2d.Object;
	final handHits:Array<h2d.Interactive> = [];
	final scoreText:h2d.Text;
	final goalText:h2d.Text;
	final plates:Array<h2d.Text>;
	final message:h2d.Text;
	final panel:h2d.Graphics;
	final panelTitle:h2d.Text;
	final panelBody:h2d.Text;
	final choices:ChoiceRow;
	final hints:HintBar;
	var timer = 0.0;
	var hold = 0.0;
	var confirmLeave = false;
	var blindDecided = true;
	var bidChoice = 3;
	var cursor = 0;
	var note = "";
	var actions:Array<String> = [];
	var clickedCard:Null<Card> = null;
	var started = false;

	public function new(parent:h2d.Object, faces:CardFaces, rng:rng.IRng) {
		super(parent);
		this.faces = faces;
		this.rng = rng;
		tableArt = new TableSurface("spades", this);
		bg = new h2d.Graphics(this);
		cardLayer = new h2d.Object(this);
		for (i in 0...SpadesGame.HAND_SIZE) {
			var hit = new h2d.Interactive(CardFaces.W, CardFaces.H, this);
			hit.cursor = Button;
			hit.onOver = _ -> cursor = i;
			hit.onClick = _ -> if (i < game.hands[0].length) clickedCard = game.hands[0][i];
			handHits.push(hit);
		}
		scoreText = TableKit.text(this, TableKit.CREAM);
		goalText = TableKit.text(this, TableKit.DIM);
		plates = [for (_ in 0...4) TableKit.text(this, TableKit.CREAM)];
		message = TableKit.text(this, TableKit.GOLD);
		panel = new h2d.Graphics(this);
		panelTitle = TableKit.text(this, TableKit.GOLD);
		panelBody = TableKit.text(this, TableKit.CREAM);
		choices = new ChoiceRow(this);
		choices.onChoose = choose;
		hints = new HintBar(this);
	}

	function get_status():String {
		return 'spades hand ${game.handNumber} ${game.phase} score ${game.scores[0]}-${game.scores[1]}';
	}

	/** Call when the player sits down: starts a fresh game. **/
	public function sit():Void {
		game.newGame();
		confirmLeave = false;
		hold = 0;
		deal();
		started = true;
	}

	function deal():Void {
		game.dealFrom(rng);
		blindDecided = game.scores[0] > game.scores[1] - SpadesGame.BLIND_NIL_DEFICIT;
		timer = 0;
		cursor = 0;
		note = 'Hand ${game.handNumber}. ${NAMES[game.dealer]} ${game.dealer == 0 ? "deal" : "deals"}.';
	}

	public function update(w:Int, dt:Float, input:MenuInput):Void {
		var cx = w / 2;
		drawTable(w);
		if (hold > 0) hold -= dt;
		var human = game.turn == 0;
		var opts:Array<String> = [];
		var title = "", body = "";
		var items:Array<{glyph:Null<GlyphAction>, label:String}> = [];

		if (confirmLeave) {
			title = "LEAVE THE TABLE?";
			body = "This game of Spades will be abandoned.";
			opts = ["Stay", "Leave"];
		} else if (hold > 0) {
			// Let the finished trick sit on the table for a moment.
		} else switch game.phase {
			case Bidding:
				if (!human) aiTurn(dt, () -> {
					var seat = game.turn, amount = SpadesAi.bid(game, seat);
					game.bid(seat, amount);
					note = '${NAMES[seat]} ${amount == 0 ? "bids nil" : 'bids $amount'}.';
				});
				else if (!blindDecided) {
					title = "BLIND NIL?";
					body = "Your side trails by 100 or more. You may bid nil\nbefore looking at your cards: 200 points if you\ntake no tricks, minus 200 if you take any.";
					opts = ["See my cards", "Bid blind nil"];
				} else {
					if (input.left) bidChoice = (bidChoice + 13) % 14;
					if (input.right) bidChoice = (bidChoice + 1) % 14;
					var partner = game.bids[2];
					title = "YOUR BID";
					body = '<  ${bidChoice == 0 ? "Nil" : Std.string(bidChoice)}  >\n\n'
						+ (partner == null ? "Your partner bids after you." : 'Prof. Oyelaran bid ${partner == 0 ? "nil" : Std.string(partner)}.');
					opts = ['Bid ${bidChoice == 0 ? "nil" : Std.string(bidChoice)}'];
					items.push({glyph: null, label: InputMode.usingPad ? "D-pad left/right: bid" : "Left/Right: bid"});
				}
			case Playing:
				if (!human) aiTurn(dt, () -> play(game.turn, SpadesAi.play(game, game.turn)));
				else {
					var legal = game.legalPlays(0);
					var hand = game.hands[0];
					if (cursor >= hand.length) cursor = hand.length - 1;
					if (input.left || input.right) {
						var step = input.left ? -1 : 1;
						for (_ in 0...hand.length) {
							cursor = (cursor + step + hand.length) % hand.length;
							if (legal.indexOf(hand[cursor]) >= 0) break;
						}
					}
					if (legal.indexOf(hand[cursor]) < 0) cursor = hand.indexOf(legal[0]);
					var pick = clickedCard != null ? clickedCard : input.confirm ? hand[cursor] : null;
					if (pick != null && legal.indexOf(pick) >= 0) play(0, pick);
					note = game.trick.length == 0 ? "Your lead." + (game.spadesBroken ? "" : " Spades aren't broken yet.") : "Your play.";
					items.push({glyph: Confirm, label: "Play card"});
					items.push({glyph: null, label: InputMode.usingPad ? "D-pad: choose" : "Left/Right: choose"});
				}
			case HandOver, GameOver:
				var over = game.phase == GameOver;
				title = over ? (game.winner == 0 ? "YOU AND PROF. OYELARAN WIN" : "THE VASQUEZ TWINS WIN") : 'HAND ${game.handNumber}';
				body = summary() + '\n\nUs ${game.scores[0]}   ·   Them ${game.scores[1]}';
				opts = [over ? "New game" : "Next hand", "Leave table"];
				note = "";
		}
		clickedCard = null;

		actions = opts;
		choices.set(opts);
		choices.visible = opts.length > 0;
		if (opts.length > 0) {
			choices.handle(input);
			items.unshift({glyph: Confirm, label: "Choose"});
		}
		items.push({glyph: Back, label: confirmLeave ? "Stay" : "Leave table"});
		if (input.back && started) {
			if (confirmLeave) confirmLeave = false;
			else if (game.phase == HandOver || game.phase == GameOver) onLeave();
			else confirmLeave = true;
		}

		drawCards(w, cx);
		drawPanel(cx, title, body, opts.length > 0);
		message.text = hold > 0 && game.lastWinner >= 0 ? '${NAMES[game.lastWinner]} ${game.lastWinner == 0 ? "take" : "takes"} the trick.' : note;
		message.x = Math.round(cx - message.textWidth / 2);
		message.y = 198;
		hints.show(items, cx, 340);
	}

	function aiTurn(dt:Float, act:Void->Void):Void {
		timer += dt;
		if (timer < AI_SECONDS) return;
		timer = 0;
		act();
	}

	function play(seat:Int, card:Card):Void {
		var before = game.tricksPlayed;
		game.play(seat, card);
		note = seat == 0 ? "" : '${NAMES[seat]} plays ${cardName(card)}.';
		if (game.tricksPlayed != before) hold = TRICK_HOLD_SECONDS;
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
		return 'the $rank of $suit';
	}

	function choose(i:Int):Void {
		var label = actions[i];
		switch label {
			case "Stay": confirmLeave = false;
			case "Leave", "Leave table": onLeave();
			case "See my cards": blindDecided = true;
			case "Bid blind nil":
				blindDecided = true;
				game.bid(0, 0, true);
				note = "You bid blind nil.";
			case "Next hand": deal();
			case "New game":
				game.newGame();
				deal();
			default:
				if (StringTools.startsWith(label, "Bid ")) {
					game.bid(0, bidChoice);
					note = bidChoice == 0 ? "You bid nil." : 'You bid $bidChoice.';
				}
		}
	}

	function summary():String {
		var lines = [];
		for (team in 0...2) {
			var r = game.lastResults[team];
			if (r == null) continue;
			var who = team == 0 ? "Us" : "Them";
			var sign = r.points >= 0 ? "+" : "";
			lines.push('$who: bid ${r.bid}, took ${r.tricks}   $sign${r.points}');
			for (n in r.nils)
				lines.push('   ${NAMES[n.seat]}: ${n.blind ? "blind nil" : "nil"} ${n.made ? "made" : "set"}');
			if (r.bags > 0) lines.push('   ${r.bags} bag${r.bags == 1 ? "" : "s"}' + (r.bagPenalty ? ", 10 bags: -100" : ""));
		}
		return lines.join("\n");
	}

	function drawTable(w:Int):Void {
		bg.clear();
		tableArt.fit(w);

		scoreText.text = 'Us ${game.scores[0]}  (${bagCount(0)})\nThem ${game.scores[1]}  (${bagCount(1)})';
		scoreText.x = 18;
		scoreText.y = 16;
		goalText.text = 'Game to ${SpadesGame.WINNING_SCORE}';
		goalText.x = w - 18 - goalText.textWidth;
		goalText.y = 16;
		TableKit.panel(bg, scoreText.x - 3, scoreText.y - 2, scoreText.textWidth + 6, scoreText.textHeight + 4);
		TableKit.panel(bg, goalText.x - 3, goalText.y - 2, goalText.textWidth + 6, goalText.textHeight + 4);
	}

	function bagCount(team:Int):String {
		var n = game.bags[team];
		return n == 1 ? "1 bag" : '$n bags';
	}

	function plate(seat:Int):String {
		var bid = game.bids[seat];
		var b = bid == null ? "-" : bid == 0 ? (game.blind[seat] ? "blind nil" : "nil") : Std.string(bid);
		return 'Bid $b  ·  Won ${game.tricks[seat]}';
	}

	function drawCards(w:Int, cx:Float):Void {
		cardLayer.removeChildren();
		var back = faces.back();
		// Opponents' and partner's hands, peeking in from the table's edges.
		var n = game.hands[2].length;
		for (i in 0...n) bitmap(back, cx - (CardFaces.W + (n - 1) * 6) / 2 + i * 6, -34);
		for (seat in [1, 3]) {
			var m = game.hands[seat].length;
			for (i in 0...m) bitmap(back, seat == 1 ? -26 : w - 14, 150 - (CardFaces.H + (m - 1) * 6) / 2 + i * 6);
		}
		plates[2].text = 'Prof. Oyelaran (partner)   ${plate(2)}';
		plates[2].x = Math.round(cx - plates[2].textWidth / 2);
		plates[2].y = 26;
		plates[1].text = 'Rosalind\n${plate(1)}';
		plates[1].x = 20;
		plates[1].y = 118;
		plates[3].text = 'Rafe\n${plate(3)}';
		plates[3].x = w - 20 - plates[3].textWidth;
		plates[3].y = 118;
		plates[0].text = 'You   ${plate(0)}';
		plates[0].x = Math.round(cx - plates[0].textWidth / 2);
		plates[0].y = 214;
		for (s in 0...4) plates[s].textColor = game.turn == s && (game.phase == Bidding || game.phase == Playing) && hold <= 0 ? TableKit.GOLD : TableKit.CREAM;

		// The trick in the middle: each card in front of the seat that played it.
		var spots = [{x: cx - 20, y: 134.0}, {x: cx - 80, y: 90.0}, {x: cx - 20, y: 44.0}, {x: cx + 40, y: 90.0}];
		for (p in (hold > 0 ? game.lastTrick : game.trick)) bitmap(faces.face(p.card), spots[p.seat].x, spots[p.seat].y);

		// The player's hand, fanned along the bottom; the chosen card lifts.
		var hand = game.hands[0];
		var hidden = game.phase == Bidding && !blindDecided;
		var myTurn = game.phase == Playing && game.turn == 0 && hold <= 0 && !confirmLeave;
		var legal = myTurn ? game.legalPlays(0) : [];
		var step = Math.min(22, (w - 40 - CardFaces.W) / Math.max(1, hand.length - 1));
		var x0 = cx - (CardFaces.W + step * (hand.length - 1)) / 2;
		for (i in 0...handHits.length) {
			var hit = handHits[i];
			hit.visible = i < hand.length && myTurn;
			if (i >= hand.length) continue;
			var c = hand[i];
			var lifted = myTurn && i == cursor;
			var b = bitmap(hidden ? back : faces.face(c), x0 + i * step, lifted ? 226 : 234);
			if (myTurn && legal.indexOf(c) < 0) b.color.set(.5, .5, .55);
			hit.x = b.x;
			hit.y = b.y;
			hit.width = i == hand.length - 1 ? CardFaces.W : step;
		}
	}

	function drawPanel(cx:Float, title:String, body:String, hasChoices:Bool):Void {
		panel.clear();
		var visible = title != "";
		panelTitle.visible = panelBody.visible = visible;
		if (!visible) {
			choices.layout(cx, 300);
			return;
		}
		panelTitle.text = title;
		panelBody.text = body;
		panelBody.textAlign = Center;
		var pw = Math.max(260, Math.max(panelTitle.textWidth, panelBody.textWidth) + 32);
		var ph = 30 + panelBody.textHeight + (hasChoices ? 30 : 8);
		var top = Math.round(Math.max(40, 120 - ph / 2));
		TableKit.panel(panel, cx - pw / 2, top, pw, ph, .92);
		panelTitle.x = Math.round(cx - panelTitle.textWidth / 2);
		panelTitle.y = top + 8;
		panelBody.maxWidth = pw - 24;
		panelBody.x = Math.round(cx - panelBody.maxWidth / 2);
		panelBody.y = top + 24;
		choices.layout(cx, top + ph - 24);
	}

	function bitmap(tile:h2d.Tile, x:Float, y:Float):h2d.Bitmap {
		var b = new h2d.Bitmap(tile, cardLayer);
		b.x = Math.round(x);
		b.y = Math.round(y);
		return b;
	}
}
