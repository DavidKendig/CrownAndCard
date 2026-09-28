// SPDX-License-Identifier: AGPL-3.0-or-later
package core;
import utest.Assert;
class GuestRegisterTest extends utest.Test {
	function testVersionedPageRoundTrip() {
		var page=GuestRegister.decode('{"version":1,"checkIns":3,"rooms":["Entrance Hall","Rotunda"]}');
		Assert.equals(3,page.checkIns); Assert.equals("Rotunda",page.rooms[1]);
		Assert.same(page,GuestRegister.decode(haxe.Json.stringify(page)));
	}
	function testPurseIsOptionalAndRoundTrips() {
		var old=GuestRegister.decode('{"version":1,"checkIns":1,"rooms":[]}');
		Assert.isNull(old.sovereigns);
		var page=GuestRegister.decode('{"version":1,"checkIns":2,"rooms":[],"sovereigns":1185,"marker":500}');
		Assert.equals(1185,page.sovereigns); Assert.equals(500,page.marker);
	}
	function testRejectsCorruptOrFuturePages() {
		for(raw in ['null','{}','{"version":2,"checkIns":0,"rooms":[]}','{"version":1,"checkIns":-1,"rooms":[]}',
			'{"version":1,"checkIns":1,"rooms":[2]}','not json','{"version":1,"checkIns":1,"rooms":[],"sovereigns":-5}',
			'{"version":1,"checkIns":1,"rooms":[],"marker":"lots"}'])
			Assert.raises(()->GuestRegister.decode(raw));
	}
}
