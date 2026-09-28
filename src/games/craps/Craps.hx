// SPDX-License-Identifier: AGPL-3.0-or-later
package games.craps;

/** One outstanding Come or Don't Come bet, with its own point and any odds behind it. **/
typedef PointBet = {point:Int, amount:Int, odds:Int};

/** What one roll of the dice resolved, for the table to narrate. **/
typedef RollResult = {
	die1:Int,
	die2:Int,
	total:Int,
	/** The point after this roll settles (null if the come-out just started or just cleared). **/
	point:Null<Int>,
	/** Plain-English lines of what happened, in resolution order. **/
	events:Array<String>,
	/** Sovereigns paid out this roll, across every bet that resolved. **/
	payout:Int,
};

/**
	The Grand Salon craps table (§6.4): Pass/Don't Pass and Come/Don't Come
	with 3-4-5x odds, Field, Place (4, 5, 6, 8, 9, 10), Hardways (4, 6, 8, 10),
	and the one-roll props Any Seven, Any Craps, Yo and Hi-Lo.

	Place and Hardway bets can be set on any roll but only resolve once a
	point is on the board (the house rule most tables use for a bet placed on
	the come-out). Big 6/8 isn't modeled: Place already covers 6 and 8 on
	better terms. Horn isn't modeled either: a player wanting that coverage
	can already bet Any Craps and Yo separately.

	Pure rules and money: the table screen only shows this state.
**/
class Craps {
	public static inline var MIN_BET = 1;

	public var purse(default, null):Int;

	/** Null on the come-out; the number to make (or seven-out on) once set. **/
	public var point(default, null):Null<Int> = null;

	public var passLine(default, null) = 0;
	public var passOdds(default, null) = 0;
	public var dontPass(default, null) = 0;
	public var dontPassOdds(default, null) = 0;

	/** Established Come/Don't Come points, each with its own odds. **/
	public final come:Array<PointBet> = [];

	public final dontCome:Array<PointBet> = [];

	/** A Come/Don't Come bet waiting for the next roll to give it a point. **/
	public var comePending(default, null) = 0;

	public var dontComePending(default, null) = 0;

	/** One-roll bet; cleared (win or lose) every roll. **/
	public var field(default, null) = 0;

	public final place = [for (n in [4, 5, 6, 8, 9, 10]) n => 0];
	public final hardway = [for (n in [4, 6, 8, 10]) n => 0];

	public var anySeven(default, null) = 0;
	public var anyCraps(default, null) = 0;
	public var yo(default, null) = 0;
	public var hiLo(default, null) = 0;

	final rng:rng.IRng;

	/** Sovereigns paid out since the last roll (also returned in RollResult.payout). **/
	var lastPayout = 0;

	public function new(rng:rng.IRng, purse:Int) {
		this.rng = rng;
		this.purse = purse;
	}

	/** Sets the purse when the player steps up to the table. **/
	public function seatPurse(amount:Int):Void {
		if (amount < 0) throw 'seatPurse(): negative amount $amount';
		purse = amount;
	}

	public function credit(amount:Int):Void {
		if (amount < 0) throw 'credit(): negative amount $amount';
		purse += amount;
	}

	public var working(get, never):Bool;

	inline function get_working():Bool return point != null;

	/** Refunds every unresolved wager (nothing has won or lost yet) and clears the table for the next shooter. **/
	public function leaveTable():Void {
		pay(passLine + passOdds + dontPass + dontPassOdds);
		passLine = passOdds = dontPass = dontPassOdds = 0;
		for (b in come) pay(b.amount + b.odds);
		come.resize(0);
		for (b in dontCome) pay(b.amount + b.odds);
		dontCome.resize(0);
		pay(comePending + dontComePending);
		comePending = dontComePending = 0;
		for (n in place.keys()) {
			pay(place.get(n));
			place.set(n, 0);
		}
		for (n in hardway.keys()) {
			pay(hardway.get(n));
			hardway.set(n, 0);
		}
		pay(field + anySeven + anyCraps + yo + hiLo);
		field = anySeven = anyCraps = yo = hiLo = 0;
		point = null;
	}

	// --- Betting -------------------------------------------------------

	public function betPassLine(amount:Int):Void {
		if (point != null) throw "Pass line only bets on the come-out";
		if (passLine > 0) throw "Pass line is already bet";
		check(amount);
		take(amount);
		passLine = amount;
	}

	public function betDontPass(amount:Int):Void {
		if (point != null) throw "Don't Pass only bets on the come-out";
		if (dontPass > 0) throw "Don't Pass is already bet";
		check(amount);
		take(amount);
		dontPass = amount;
	}

	public function betPassOdds(amount:Int):Void {
		if (point == null) throw "No point to take odds on";
		if (passLine == 0) throw "No Pass line bet to back";
		if (passOdds + amount > passLine * maxOddsMultiple(point)) throw 'Odds are capped at ${maxOddsMultiple(point)}x the line';
		check(amount);
		take(amount);
		passOdds += amount;
	}

	public function betDontPassOdds(amount:Int):Void {
		if (point == null) throw "No point to lay odds against";
		if (dontPass == 0) throw "No Don't Pass bet to back";
		if (dontPassOdds + amount > dontPass * maxOddsMultiple(point)) throw 'Odds are capped at ${maxOddsMultiple(point)}x the line';
		check(amount);
		take(amount);
		dontPassOdds += amount;
	}

	public function betCome(amount:Int):Void {
		if (point == null) throw "Come bets need a point on the board";
		check(amount);
		take(amount);
		comePending += amount;
	}

	public function betDontCome(amount:Int):Void {
		if (point == null) throw "Don't Come bets need a point on the board";
		check(amount);
		take(amount);
		dontComePending += amount;
	}

	public function betComeOdds(comePoint:Int, amount:Int):Void {
		var b = findPointBet(come, comePoint);
		if (b == null) throw 'No Come bet on $comePoint';
		if (b.odds + amount > b.amount * maxOddsMultiple(comePoint)) throw 'Odds are capped at ${maxOddsMultiple(comePoint)}x the bet';
		check(amount);
		take(amount);
		b.odds += amount;
	}

	public function betDontComeOdds(comePoint:Int, amount:Int):Void {
		var b = findPointBet(dontCome, comePoint);
		if (b == null) throw 'No Don\'t Come bet on $comePoint';
		if (b.odds + amount > b.amount * maxOddsMultiple(comePoint)) throw 'Odds are capped at ${maxOddsMultiple(comePoint)}x the bet';
		check(amount);
		take(amount);
		b.odds += amount;
	}

	public function betField(amount:Int):Void {
		check(amount);
		take(amount);
		field += amount;
	}

	public function betPlace(number:Int, amount:Int):Void {
		if (!place.exists(number)) throw 'Not a place number: $number';
		check(amount);
		take(amount);
		place.set(number, place.get(number) + amount);
	}

	/** Takes a Place bet down, returning its stake (no win or loss). **/
	public function clearPlace(number:Int):Void {
		if (!place.exists(number)) throw 'Not a place number: $number';
		var amount = place.get(number);
		if (amount > 0) {
			pay(amount);
			place.set(number, 0);
		}
	}

	public function betHardway(number:Int, amount:Int):Void {
		if (!hardway.exists(number)) throw 'Not a hardway number: $number';
		check(amount);
		take(amount);
		hardway.set(number, hardway.get(number) + amount);
	}

	public function clearHardway(number:Int):Void {
		if (!hardway.exists(number)) throw 'Not a hardway number: $number';
		var amount = hardway.get(number);
		if (amount > 0) {
			pay(amount);
			hardway.set(number, 0);
		}
	}

	public function betAnySeven(amount:Int):Void {
		check(amount);
		take(amount);
		anySeven += amount;
	}

	public function betAnyCraps(amount:Int):Void {
		check(amount);
		take(amount);
		anyCraps += amount;
	}

	public function betYo(amount:Int):Void {
		check(amount);
		take(amount);
		yo += amount;
	}

	public function betHiLo(amount:Int):Void {
		check(amount);
		take(amount);
		hiLo += amount;
	}

	// --- Rolling ---------------------------------------------------------

	/** Throws the dice and settles every bet at once (§7.7: the RNG decides, then the table animates to match). **/
	public function roll():RollResult {
		lastPayout = 0;
		var d1 = rng.between(1, 6), d2 = rng.between(1, 6);
		var total = d1 + d2;
		var events:Array<String> = [];

		resolveField(total, events);
		resolveProps(total, events);
		resolveHardways(d1, d2, total, events);

		if (point == null) resolveComeOut(total, events) else resolvePoint(total, events);

		return {die1: d1, die2: d2, total: total, point: point, events: events, payout: lastPayout};
	}

	function resolveComeOut(total:Int, events:Array<String>):Void {
		if (total == 7 || total == 11) {
			if (passLine > 0) {
				pay(passLine * 2);
				events.push('Pass line wins on $total.');
				passLine = 0;
			}
			if (dontPass > 0) {
				events.push("Don't Pass loses.");
				dontPass = 0;
			}
		} else if (total == 2 || total == 3) {
			if (passLine > 0) {
				events.push('Craps $total: Pass line loses.');
				passLine = 0;
			}
			if (dontPass > 0) {
				pay(dontPass * 2);
				events.push("Don't Pass wins.");
				dontPass = 0;
			}
		} else if (total == 12) {
			if (passLine > 0) {
				events.push("Craps 12: Pass line loses.");
				passLine = 0;
			}
			if (dontPass > 0) {
				pay(dontPass);
				events.push("Don't Pass pushes on the bar-12.");
				dontPass = 0;
			}
		} else {
			point = total;
			events.push('Point is $total.');
		}
	}

	function resolvePoint(total:Int, events:Array<String>):Void {
		// Check bets that already had a point before this roll first, so a Come
		// bet that only just got its point this roll can't also resolve on it.
		resolveComeHit(total, events);
		resolveDontComeHit(total, events);
		resolveComePending(total, events);
		resolveDontComePending(total, events);
		resolvePlaceHit(total, events);

		if (total == 7) {
			if (passLine > 0) {
				events.push("Seven out: Pass line loses.");
				passLine = 0;
				passOdds = 0;
			}
			if (dontPass > 0) {
				var ratio = oddsRatio(point);
				var oddsProfit = Std.int(dontPassOdds * ratio.den / ratio.num);
				pay(dontPass * 2 + dontPassOdds + oddsProfit);
				events.push("Seven out: Don't Pass wins.");
				dontPass = 0;
				dontPassOdds = 0;
			}
			resolveSevenOutCome(events);
			resolveSevenOutDontCome(events);
			resolvePlaceLoseAll(events);
			point = null;
		} else if (total == point) {
			if (passLine > 0) {
				var ratio = oddsRatio(point);
				var oddsProfit = Std.int(passOdds * ratio.num / ratio.den);
				pay(passLine * 2 + passOdds + oddsProfit);
				events.push("Point made! Pass line wins.");
				passLine = 0;
				passOdds = 0;
			}
			if (dontPass > 0) {
				events.push("Point made: Don't Pass loses.");
				dontPass = 0;
				dontPassOdds = 0;
			}
			point = null;
		}
	}

	function resolveComePending(total:Int, events:Array<String>):Void {
		if (comePending == 0) return;
		if (total == 7 || total == 11) {
			pay(comePending * 2);
			events.push('Come bet wins on $total.');
			comePending = 0;
		} else if (total == 2 || total == 3 || total == 12) {
			events.push('Come bet craps out on $total.');
			comePending = 0;
		} else {
			come.push({point: total, amount: comePending, odds: 0});
			events.push('Come point is $total.');
			comePending = 0;
		}
	}

	function resolveDontComePending(total:Int, events:Array<String>):Void {
		if (dontComePending == 0) return;
		if (total == 7 || total == 11) {
			events.push('Don\'t Come loses on $total.');
			dontComePending = 0;
		} else if (total == 2 || total == 3) {
			pay(dontComePending * 2);
			events.push("Don't Come wins.");
			dontComePending = 0;
		} else if (total == 12) {
			pay(dontComePending);
			events.push("Don't Come pushes on the bar-12.");
			dontComePending = 0;
		} else {
			dontCome.push({point: total, amount: dontComePending, odds: 0});
			events.push('Don\'t Come point is $total.');
			dontComePending = 0;
		}
	}

	/** An established Come point repeats: it wins, with any odds behind it. **/
	function resolveComeHit(total:Int, events:Array<String>):Void {
		var i = 0;
		while (i < come.length) {
			var b = come[i];
			if (b.point == total) {
				var ratio = oddsRatio(b.point);
				var oddsProfit = Std.int(b.odds * ratio.num / ratio.den);
				pay(b.amount * 2 + b.odds + oddsProfit);
				events.push('Come $total wins.');
				come.splice(i, 1);
			} else i++;
		}
	}

	/** An established Don't Come point repeats before a seven: it loses. **/
	function resolveDontComeHit(total:Int, events:Array<String>):Void {
		var i = 0;
		while (i < dontCome.length) {
			var b = dontCome[i];
			if (b.point == total) {
				events.push('Don\'t Come $total loses.');
				dontCome.splice(i, 1);
			} else i++;
		}
	}

	function resolveSevenOutCome(events:Array<String>):Void {
		if (come.length > 0) events.push('Seven out: Come bets lose.');
		come.resize(0);
	}

	function resolveSevenOutDontCome(events:Array<String>):Void {
		for (b in dontCome) {
			var ratio = oddsRatio(b.point);
			var oddsProfit = Std.int(b.odds * ratio.den / ratio.num);
			pay(b.amount * 2 + b.odds + oddsProfit);
		}
		if (dontCome.length > 0) events.push("Seven out: Don't Come bets win.");
		dontCome.resize(0);
	}

	function resolvePlaceHit(total:Int, events:Array<String>):Void {
		if (!place.exists(total)) return;
		var amount = place.get(total);
		if (amount == 0) return;
		var ratio = placeRatio(total);
		var profit = Std.int(amount * ratio.num / ratio.den);
		pay(amount + profit);
		events.push('Place $total wins.');
	}

	function resolvePlaceLoseAll(events:Array<String>):Void {
		var any = false;
		for (n in place.keys()) if (place.get(n) > 0) any = true;
		if (any) events.push("Seven out: Place bets lose.");
		for (n in place.keys()) place.set(n, 0);
	}

	function resolveField(total:Int, events:Array<String>):Void {
		if (field == 0) return;
		if (total == 2 || total == 12) {
			pay(field * 3);
			events.push('Field $total pays double.');
		} else if (total == 3 || total == 4 || total == 9 || total == 10 || total == 11) {
			pay(field * 2);
			events.push('Field $total wins.');
		} else events.push("Field loses.");
		field = 0;
	}

	function resolveProps(total:Int, events:Array<String>):Void {
		if (anySeven > 0) {
			if (total == 7) {
				pay(anySeven * 5);
				events.push("Any Seven wins.");
			} else events.push("Any Seven loses.");
			anySeven = 0;
		}
		if (anyCraps > 0) {
			if (total == 2 || total == 3 || total == 12) {
				pay(anyCraps * 8);
				events.push("Any Craps wins.");
			} else events.push("Any Craps loses.");
			anyCraps = 0;
		}
		if (yo > 0) {
			if (total == 11) {
				pay(yo * 16);
				events.push("Yo-leven wins!");
			} else events.push("Yo loses.");
			yo = 0;
		}
		if (hiLo > 0) {
			if (total == 2 || total == 12) {
				pay(hiLo * 16);
				events.push("Hi-Lo wins.");
			} else events.push("Hi-Lo loses.");
			hiLo = 0;
		}
	}

	function resolveHardways(d1:Int, d2:Int, total:Int, events:Array<String>):Void {
		for (n in hardway.keys()) {
			var amount = hardway.get(n);
			if (amount == 0) continue;
			if (total == 7) {
				events.push("Hardways lose on seven.");
				hardway.set(n, 0);
			} else if (total == n) {
				if (d1 == d2) {
					pay(amount * (hardwayOdds(n) + 1));
					events.push('Hard $n!');
				} else events.push('$n the easy way: hardway loses.');
				hardway.set(n, 0);
			}
		}
	}

	// --- Helpers -----------------------------------------------------------

	function findPointBet(list:Array<PointBet>, forPoint:Int):Null<PointBet> {
		for (b in list) if (b.point == forPoint) return b;
		return null;
	}

	function check(amount:Int):Void {
		if (amount < MIN_BET) throw 'Bet must be at least $MIN_BET';
		if (amount > purse) throw 'Not enough in the purse ($purse) for $amount';
	}

	function take(amount:Int):Void purse -= amount;

	function pay(amount:Int):Void {
		purse += amount;
		lastPayout += amount;
	}

	/** True odds ratio (win : bet) for the point numbers, used by both lines and Come bets. **/
	public static function oddsRatio(point:Int):{num:Int, den:Int} {
		return switch point {
			case 4 | 10: {num: 2, den: 1};
			case 5 | 9: {num: 3, den: 2};
			case 6 | 8: {num: 6, den: 5};
			default: throw 'Not a point number: $point';
		}
	}

	/** 3-4-5x: the odds multiple allowed behind a line or Come bet on this point. **/
	public static function maxOddsMultiple(point:Int):Int {
		return switch point {
			case 4 | 10: 3;
			case 5 | 9: 4;
			case 6 | 8: 5;
			default: throw 'Not a point number: $point';
		}
	}

	public static function placeRatio(number:Int):{num:Int, den:Int} {
		return switch number {
			case 4 | 10: {num: 9, den: 5};
			case 5 | 9: {num: 7, den: 5};
			case 6 | 8: {num: 7, den: 6};
			default: throw 'Not a place number: $number';
		}
	}

	/** X in the hardway's X:1 payout. **/
	public static function hardwayOdds(number:Int):Int return (number == 6 || number == 8) ? 9 : 7;
}
