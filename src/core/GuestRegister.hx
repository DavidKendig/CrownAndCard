// SPDX-License-Identifier: AGPL-3.0-or-later
package core;

typedef Checkpoint = {
	var version:Int;
	var checkIns:Int;
	var rooms:Array<String>;

	/** The purse and Pemberton's marker (§10.1, §10.3); absent on pages from before the tables opened. **/
	@:optional var sovereigns:Int;
	@:optional var marker:Int;
}

/** Explicit check-ins only. Launcher storage survives its random per-run web origin. */
class GuestRegister {
	public var checkpoint(default,null):Checkpoint = {version:1,checkIns:0,rooms:[]};
	public var ready(default,null) = false;
	public var busy(default,null) = false;
	final endpoint:Null<String>;
	static inline var KEY = "crown-and-card.guest-register.v1";

	public function new(api:Null<String>) {
		endpoint = api != null && (StringTools.startsWith(api,"http://127.0.0.1:") || StringTools.startsWith(api,"http://localhost:"))
			? (StringTools.endsWith(api,"/") ? api : api+"/")+"save" : null;
	}

	public static function decode(raw:String):Checkpoint {
		var value:Dynamic = haxe.Json.parse(raw);
		if (value == null || value.version != 1 || !Std.isOfType(value.checkIns,Int) || value.checkIns < 0 || !Std.isOfType(value.rooms,Array))
			throw "Invalid Guest Register";
		for (room in (cast value.rooms:Array<Dynamic>)) if (!Std.isOfType(room,String)) throw "Invalid room";
		for (field in ["sovereigns","marker"]) {
			var amount:Dynamic = Reflect.field(value,field);
			if (amount != null && (!Std.isOfType(amount,Int) || amount < 0)) throw 'Invalid $field';
		}
		return cast value;
	}

	public function load(done:Null<String>->Void):Void {
		read((raw,error) -> {
			if (error != null) { done(error); return; }
			try { if (raw != null && raw != "null") checkpoint=decode(raw); ready=true; done(null); }
			catch (_:Dynamic) { done("The Guest Register could not be read. Your saved page has been kept."); }
		});
	}

	/** The saved purse, or a fresh invitation stake for a new member. **/
	public function wallet():Wallet {
		return new Wallet(checkpoint.sovereigns == null ? Wallet.STARTING_STAKE : checkpoint.sovereigns,
			checkpoint.marker == null ? 0 : checkpoint.marker);
	}

	public function checkIn(rooms:Array<String>,wallet:Wallet,done:Null<String>->Void):Void {
		if (!ready || busy) { done("The Guest Register is not ready."); return; }
		busy=true;
		var next:Checkpoint={version:1,checkIns:checkpoint.checkIns+1,rooms:rooms.copy(),sovereigns:wallet.sovereigns,marker:wallet.marker};
		write(haxe.Json.stringify(next), error -> {
			busy=false; if (error == null) checkpoint=next; done(error);
		});
	}

	function read(done:(Null<String>,Null<String>)->Void):Void {
		#if js
		if (endpoint != null) {
			js.Browser.window.fetch(endpoint).then(r -> {
				if (!r.ok) throw "load";
				return r.text();
			}).then(raw -> { done(raw,null); }).catchError(_ -> done(null,"Cannot open the Guest Register. Please restart from the launcher."));
		} else {
			try { done(js.Browser.getLocalStorage().getItem(KEY),null); }
			catch (_:Dynamic) { done(null,"Browser storage is unavailable."); }
		}
		#else
		try { var path=savePath(); done(sys.FileSystem.exists(path)?sys.io.File.getContent(path):null,null); }
		catch (_:Dynamic) { done(null,"Cannot read the Guest Register."); }
		#end
	}

	function write(raw:String,done:Null<String>->Void):Void {
		#if js
		if (endpoint != null) {
			js.Browser.window.fetch(endpoint,{method:"POST",body:raw,headers:{"Content-Type":"application/json"}}).then(r -> {
				if (!r.ok) throw "save"; done(null);
			}).catchError(_ -> done("Check-in failed. Your previous saved page has been kept."));
		} else {
			try { js.Browser.getLocalStorage().setItem(KEY,raw); done(null); }
			catch (_:Dynamic) { done("Check-in failed. Browser storage is unavailable."); }
		}
		#else
		try {
			var path=savePath(); sys.FileSystem.createDirectory(haxe.io.Path.directory(path));
			sys.io.File.saveContent(path+".tmp",raw);
			if (sys.FileSystem.exists(path)) sys.io.File.copy(path,path+".bak");
			try { sys.FileSystem.rename(path+".tmp",path); }
			catch (_:Dynamic) {
				// Windows rename may refuse to replace a file. Keep the backup and copy the validated page.
				try { sys.io.File.copy(path+".tmp",path); }
				catch (e:Dynamic) { if(sys.FileSystem.exists(path+".bak")) sys.io.File.copy(path+".bak",path); throw e; }
				sys.FileSystem.deleteFile(path+".tmp");
			}
			done(null);
		} catch (_:Dynamic) { done("Check-in failed. Please check that saves are writable."); }
		#end
	}

	#if sys
	static function savePath():String {
		var root=Sys.getEnv("LOCALAPPDATA");
		if (root==null) root=Sys.getEnv("HOME");
		if (root==null) root=".";
		return haxe.io.Path.join([root,"CrownAndCard","saves","guest-register.json"]);
	}
	#end
}
