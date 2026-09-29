// SPDX-License-Identifier: AGPL-3.0-or-later

class TestMain {
	static function main() {
		utest.UTest.run([
			new rng.ChaCha20Test(),
			new rng.ChaChaRngTest(),
			new rng.Xoshiro128ssTest(),
			new rng.DistributionTest(),
			new cards.CardTest(),
			new cards.ShoeTest(),
			new world.GridMapTest(),
			new world.FoyerTest(),
			new world.ConservatoryTest(),
			new world.CardRoomTest(),
			new world.MapDataTest(),
			new core.GuestRegisterTest(),
			new games.BlackjackTest(),
			new games.SpadesTest(),
			new games.PokerTest(),
			new games.ParlourTest(),
			new games.MahjongTest(),
			new games.CrapsTest(),
			new games.RouletteTest(),
			new games.BettingLayoutTest(),
			new games.WheelMotionTest(),
			new games.SlotsTest(),
			new games.LeverPhysicsTest(),
			new games.EgyptianRatScrewTest(),
			new games.DurakTest(),
			new games.GinRummyTest(),
			new games.HeartsTest(),
			new games.EuchreTest(),
			new games.CanastaTest(),
			new games.BridgeTest(),
			new net.NetPokerTest(),
		]);
	}
}
