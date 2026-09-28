// SPDX-License-Identifier: AGPL-3.0-or-later
package core;

/** The player's Sovereigns (§10.1) and any marker owed to Pemberton (§10.3). Saved at check-in. **/
class Wallet {
	/** The invitation stake every new member starts with. **/
	public static inline var STARTING_STAKE = 1000;

	/** What Pemberton advances each time the purse runs dry. **/
	public static inline var MARKER_ADVANCE = 500;

	public var sovereigns:Int;
	public var marker:Int;

	public function new(sovereigns:Int = STARTING_STAKE, marker:Int = 0) {
		this.sovereigns = sovereigns;
		this.marker = marker;
	}

	/** Pemberton's marker: a loan that keeps the player at the tables (no soft-locks). **/
	public function takeMarker():Void {
		sovereigns += MARKER_ADVANCE;
		marker += MARKER_ADVANCE;
	}
}
