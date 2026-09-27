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
		]);
	}
}
