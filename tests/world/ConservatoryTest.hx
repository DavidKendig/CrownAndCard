// SPDX-License-Identifier: AGPL-3.0-or-later
package world;
import utest.Assert;

class ConservatoryTest extends utest.Test {
	function room():GridMap {
		var sector:GridMap.Sector={name:"Conservatory",floorZ:0,ceilZ:7,floorTex:"marble",ceilTex:"glass",wallTex:"glass",upperTex:"glass",shade:4};
		var map=new GridMap([for(_ in 0...22) "vvvvvvvvvvvvvvvvvvvv"],["v"=>sector]);
		map.props.push({x0:2,y0:16,x1:14,y1:19,baseZ:3.26,height:3.4,topTex:"ivory",sideTex:"stone",kind:"walkway",walkable:true});
		Conservatory.furnish(map);return map;
	}
	function testGalleryHasNoStairsAndSixPlants() {
		var map=room();
		Assert.equals(1,[for(p in map.props) if(p.kind=="galleryDeck") p].length);
		Assert.equals(0,[for(p in map.props) if(p.walkable==true && p.kind!="galleryDeck") p].length);
		Assert.equals(4,[for(p in map.props) if(p.kind=="galleryRail") p].length);
		Assert.equals(6,map.plants.length);
	}
	function testWalkBelowWithoutMountingGallery() {
		var map=room(),moved=map.slide(6,15,0,2,.25,0);
		Assert.floatEquals(17,moved.y);Assert.floatEquals(0,moved.z);
		Assert.floatEquals(3.4,map.floorAt(6,17,3.4));
	}
	function testAllFourRailsBlockUpperPlayer() {
		var map=room();
		for(delta in [{x:0.,y:-5.},{x:0.,y:5.},{x:-15.,y:0.},{x:15.,y:0.}]) {
			var moved=map.slide(6,17,delta.x,delta.y,.25,3.4);
			Assert.isTrue(moved.x>2.3 && moved.x<13.7 && moved.y>16.3 && moved.y<18.7);
			Assert.floatEquals(3.4,moved.z);
		}
	}
}
