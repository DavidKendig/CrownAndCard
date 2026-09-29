// SPDX-License-Identifier: AGPL-3.0-or-later
package world;

typedef PlantPlacement = {x:Float,y:Float,z:Float,palm:Bool};

/** Gallery collision and furniture, derived from an authored conservatory walkway. */
class Conservatory {
	public static function furnish(map:GridMap):Void {
		for(deck in map.props.copy()) {
			var room=map.sectorAtWorld((deck.x0+deck.x1)/2,(deck.y0+deck.y1)/2);
			if(deck.kind!="walkway" || room==null || room.wallTex!="glass") continue;
			deck.kind="galleryDeck"; deck.hidden=true; deck.walkable=true;
			deck.topTex=deck.sideTex="grateMetal";
			deck.baseZ=deck.height-.14;
			var x0=deck.x0,x1=deck.x1,y0=deck.y0,y1=deck.y1,z=deck.height;
			rail(map,x0+.12,y0+.12,x1-.12,y0+.12,z);
			rail(map,x0+.12,y0+.12,x0+.12,y1-.12,z);
			rail(map,x0+.12,y1-.12,x1-.12,y1-.12,z);
			rail(map,x1-.12,y0,x1-.12,y1-.12,z);
			// The gallery is enclosed on all sides; access will be added later.
			planter(map,x0+1,y0-10,room.floorZ,true);
			planter(map,x1-1,y0-10,room.floorZ,true);
			planter(map,x0+1,y0-4,room.floorZ,false);
			planter(map,x0+5,y1-1,room.floorZ,true);
			planter(map,x0+1,y1-1,z,false);
			planter(map,x0+6,y1-1,z,false);
		}
	}

	static function rail(map:GridMap,x0:Float,y0:Float,x1:Float,y1:Float,z:Float):Void {
		function bar(a:Float,b:Float,c:Float,d:Float,base:Float,top:Float,tex:String,hidden:Bool=false) {
			map.props.push({x0:a-.045,y0:b-.045,x1:c+.045,y1:d+.045,baseZ:base,height:top,
				topTex:tex,sideTex:tex,hidden:hidden,solid:hidden,kind:hidden?"galleryRail":"galleryDetail"});
		}
		bar(x0,y0,x1,y1,z,z+1.1,"grateMetal",true);
		bar(x0,y0,x1,y1,z+1.04,z+1.14,"banisterWood");
		bar(x0,y0,x1,y1,z+.42,z+.47,"grateMetal");
		var count=Std.int(Math.ceil(Math.max(x1-x0,y1-y0)/.25));
		for(i in 0...count+1) {
			var t=count==0?0.:i/count,x=x0+(x1-x0)*t,y=y0+(y1-y0)*t;
			bar(x,y,x,y,z,z+1.1,"grateMetal");
		}
	}

	static function planter(map:GridMap,x:Float,y:Float,z:Float,palm:Bool):Void {
		var room=map.sectorAtWorld(x,y);
		if(room==null || room.wallTex!="glass") return;
		map.props.push({x0:x-.43,y0:y-.43,x1:x+.43,y1:y+.43,baseZ:z,height:z+.76,topTex:"soil",sideTex:"planterCeramic",kind:"planter"});
		for(side in 0...4) {
			var a=side<2;
			var off=side%2==0?-.44:.38;
			map.props.push({x0:x+(a?off:-.44),y0:y+(a?-.44:off),x1:x+(a?off+.06:.44),y1:y+(a ? .44 : off+.06),
				baseZ:z+.72,height:z+.82,topTex:"brass",sideTex:"brass",solid:false});
		}
		map.plants.push({x:x,y:y,z:z+.73,palm:palm});
	}
}
