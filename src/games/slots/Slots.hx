// SPDX-License-Identifier: AGPL-3.0-or-later
package games.slots;

/** A reel stop. Suits echo the Order's own cards; Blank pays nothing. **/
enum abstract Symbol(String) to String {
	var Crown = "Crown";
	var Seven = "Seven";
	var Bell = "Bell";
	var Bar = "Bar";
	var Club = "Club";
	var Diamond = "Diamond";
	var Heart = "Heart";
	var Spade = "Spade";
	var Cherry = "Cherry";
	var Blank = "Blank";
}

typedef SpinResult = {
	/** The three stops, left reel to right. **/
	symbols:Array<Symbol>,
	/** Total returned per Sovereign bet; 0 is a total loss. **/
	multiplier:Int,
	/** `multiplier * bet`, already credited to the purse. **/
	payout:Int,
};

/**
	The Clockwork Gallery's one-armed bandit (§6.4): a single payline on
	three identical authored reel strips. The strips weight each symbol by
	how many times it appears (a "virtual reel"), so the paytable and the
	strip together fix the RTP; SlotsTest brute-forces every stop and checks
	it lands in the 92-96% band the design calls for (§7.9). The plaque in
	`RTP` is exact, not a sampled estimate, since the strip is short enough
	to enumerate completely.

	The stop is chosen first (§7.7); the table only spins the reels down
	onto it.
**/
class Slots {
	/** One authored strip, shared by all three reels; only the counts matter. **/
	public static final REEL:Array<Symbol> = [
		Crown, Seven, Seven, Bell, Bell, Bell, Bar, Bar, Bar, Bar, Club, Club, Club, Diamond, Diamond, Diamond, Heart,
		Heart, Heart, Spade, Spade, Spade, Cherry, Cherry, Cherry, Cherry, Cherry, Cherry, Cherry, Cherry, Cherry, Blank,
		Blank,
	];

	static final SUITS = [Club, Diamond, Heart, Spade];

	public static final BETS = [1, 2, 3, 5, 10];

	/** The exact house RTP for this paytable and strip (the brass plaque), verified by SlotsTest. **/
	public static inline var RTP = 0.9447;

	public var purse(default, null):Int;

	final rng:rng.IRng;

	public function new(rng:rng.IRng, purse:Int) {
		this.rng = rng;
		this.purse = purse;
	}

	/** Sets the purse when the player steps up to the machine. **/
	public function seatPurse(amount:Int):Void {
		if (amount < 0) throw 'seatPurse(): negative amount $amount';
		purse = amount;
	}

	public function canBet(bet:Int):Bool return BETS.indexOf(bet) >= 0 && bet <= purse;

	/** Pulls the lever: stakes the bet, spins, and pays out any win. **/
	public function spin(bet:Int):SpinResult {
		if (!canBet(bet)) throw 'Bet $bet is not allowed now (purse $purse)';
		purse -= bet;
		var symbols = [for (_ in 0...3) REEL[rng.below(REEL.length)]];
		var mult = payoutMultiplier(symbols[0], symbols[1], symbols[2]);
		var payout = bet * mult;
		purse += payout;
		return {symbols: symbols, multiplier: mult, payout: payout};
	}

	/** The paytable: total return per Sovereign bet for these three stops. **/
	public static function payoutMultiplier(a:Symbol, b:Symbol, c:Symbol):Int {
		if (a == Crown && b == Crown && c == Crown) return 150;
		if (a == Seven && b == Seven && c == Seven) return 45;
		if (a == Bell && b == Bell && c == Bell) return 20;
		if (a == Bar && b == Bar && c == Bar) return 12;
		if (a == b && b == c && SUITS.indexOf(a) >= 0) return 8;
		if (a == Cherry && b == Cherry && c == Cherry) return 10;
		if (a == Cherry && b == Cherry) return 5;
		if (a == Cherry) return 2;
		return 0;
	}
}
