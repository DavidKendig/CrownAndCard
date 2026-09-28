// SPDX-License-Identifier: AGPL-3.0-or-later
package games.roulette;

enum abstract BetKind(String) to String {
	/** One number. **/
	var Straight = "straight";

	/** Two adjacent numbers. **/
	var Split = "split";

	/** A row of three (1-2-3, 4-5-6, ...). **/
	var Street = "street";

	/** A 2x2 block of four numbers, or the 0-1-2-3 "basket". **/
	var Corner = "corner";

	/** Two adjacent streets (six numbers). **/
	var SixLine = "six-line";

	/** 1-12, 13-24 or 25-36. **/
	var Dozen = "dozen";

	/** One of the three vertical columns of twelve. **/
	var Column = "column";

	var Red = "red";
	var Black = "black";
	var Odd = "odd";
	var Even = "even";

	/** 1-18. **/
	var Low = "low";

	/** 19-36. **/
	var High = "high";
}

typedef Bet = {
	kind:BetKind,
	/** Pocket numbers covered (0-36); unused (empty) for Dozen/Column/even-money bets. **/
	numbers:Array<Int>,
	/** 1, 2 or 3 for a Dozen or Column bet; unused otherwise. **/
	group:Int,
	amount:Int,
};

typedef BetOutcome = {bet:Bet, won:Bool, partaged:Bool, payout:Int};

typedef SpinResult = {
	pocket:Int,
	/** Total returned across every bet (stake included for winners), after La Partage. **/
	payout:Int,
	results:Array<BetOutcome>,
};

/**
	The Grand Salon's single-zero wheel (§6.4): European rules, with French
	La Partage returning half the stake on an even-money bet when the ball
	falls in 0. Inside bets (straight, split, street, corner, six-line, and
	the 0-1-2-3 "basket", which is just a Corner including zero) and outside
	bets (dozens, columns, red/black, odd/even, low/high) are all supported
	by the engine; the seated table's layout board doesn't yet offer every
	inside shape through the pad (§9's racetrack UI is a later pass).

	The pocket is chosen first (§7.7); the wheel and ball are then
	choreographed to land on it.
**/
class Roulette {
	public static final RED_NUMBERS = [1, 3, 5, 7, 9, 12, 14, 16, 18, 19, 21, 23, 25, 27, 30, 32, 34, 36];

	public static inline var MIN_BET = 1;

	public var purse(default, null):Int;

	final rng:rng.IRng;

	public function new(rng:rng.IRng, purse:Int) {
		this.rng = rng;
		this.purse = purse;
	}

	/** Sets the purse when the player steps up to the table. **/
	public function seatPurse(amount:Int):Void {
		if (amount < 0) throw 'seatPurse(): negative amount $amount';
		purse = amount;
	}

	public static function isRed(n:Int):Bool return n > 0 && RED_NUMBERS.indexOf(n) >= 0;

	/** True for the six bets that pay 1:1 and so qualify for La Partage. **/
	public static function isEvenMoney(kind:BetKind):Bool {
		return switch kind {
			case Red | Black | Odd | Even | Low | High: true;
			default: false;
		}
	}

	/** Payout odds (X:1) for a bet kind. **/
	public static function odds(kind:BetKind):Int {
		return switch kind {
			case Straight: 35;
			case Split: 17;
			case Street: 11;
			case Corner: 8;
			case SixLine: 5;
			case Dozen | Column: 2;
			case Red | Black | Odd | Even | Low | High: 1;
		}
	}

	// --- Bet builders --------------------------------------------------

	public static function straight(n:Int, amount:Int):Bet return {kind: Straight, numbers: [n], group: 0, amount: amount};

	public static function split(a:Int, b:Int, amount:Int):Bet return {kind: Split, numbers: [a, b], group: 0, amount: amount};

	/** `row` 1-12, the row starting at `(row - 1) * 3 + 1`. **/
	public static function street(row:Int, amount:Int):Bet {
		var a = (row - 1) * 3 + 1;
		return {kind: Street, numbers: [a, a + 1, a + 2], group: 0, amount: amount};
	}

	/** The 2x2 block whose top-left number is `topLeft` (must not be in the rightmost column). **/
	public static function corner(topLeft:Int, amount:Int):Bet {
		return {kind: Corner, numbers: [topLeft, topLeft + 1, topLeft + 3, topLeft + 4], group: 0, amount: amount};
	}

	/** The 0-1-2-3 corner, the one basket bet on a single-zero wheel. **/
	public static function basket(amount:Int):Bet return {kind: Corner, numbers: [0, 1, 2, 3], group: 0, amount: amount};

	/** `row` 1-11: that street and the one below it, six numbers. **/
	public static function sixLine(row:Int, amount:Int):Bet {
		var a = (row - 1) * 3 + 1;
		return {kind: SixLine, numbers: [a, a + 1, a + 2, a + 3, a + 4, a + 5], group: 0, amount: amount};
	}

	/** `which` 1, 2 or 3 for the first, second or third dozen. **/
	public static function dozen(which:Int, amount:Int):Bet return {kind: Dozen, numbers: [], group: which, amount: amount};

	/** `which` 1, 2 or 3 for that column. **/
	public static function column(which:Int, amount:Int):Bet return {kind: Column, numbers: [], group: which, amount: amount};

	/** Red, Black, Odd, Even, Low or High. **/
	public static function outside(kind:BetKind, amount:Int):Bet return {kind: kind, numbers: [], group: 0, amount: amount};

	// --- Spinning --------------------------------------------------------

	/** Spins the wheel and settles every bet in `bets` at once. Stakes are taken up front. **/
	public function spin(bets:Array<Bet>):SpinResult {
		stake(bets);
		var pocket = rng.between(0, 36);
		var results:Array<BetOutcome> = [];
		var payout = 0;
		for (b in bets) {
			if (wins(b, pocket)) {
				var back = b.amount + b.amount * odds(b.kind);
				payout += back;
				results.push({bet: b, won: true, partaged: false, payout: back});
			} else if (isEvenMoney(b.kind) && pocket == 0) {
				var back = Std.int(b.amount / 2);
				payout += back;
				results.push({bet: b, won: false, partaged: true, payout: back});
			} else results.push({bet: b, won: false, partaged: false, payout: 0});
		}
		purse += payout;
		return {pocket: pocket, payout: payout, results: results};
	}

	function stake(bets:Array<Bet>):Void {
		var total = 0;
		for (b in bets) {
			if (b.amount < MIN_BET) throw 'Bet must be at least $MIN_BET';
			total += b.amount;
		}
		if (total > purse) throw 'Not enough in the purse ($purse) for $total';
		purse -= total;
	}

	static function wins(b:Bet, pocket:Int):Bool {
		return switch b.kind {
			case Straight | Split | Street | Corner | SixLine: b.numbers.indexOf(pocket) >= 0;
			case Dozen: pocket != 0 && Std.int((pocket - 1) / 12) + 1 == b.group;
			case Column: pocket != 0 && (pocket - 1) % 3 + 1 == b.group;
			case Red: isRed(pocket);
			case Black: pocket != 0 && !isRed(pocket);
			case Odd: pocket != 0 && pocket % 2 == 1;
			case Even: pocket != 0 && pocket % 2 == 0;
			case Low: pocket >= 1 && pocket <= 18;
			case High: pocket >= 19 && pocket <= 36;
		}
	}
}
