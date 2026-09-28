// SPDX-License-Identifier: AGPL-3.0-or-later
package haxen;

import js.Browser;
import js.html.CanvasElement;
import js.html.CanvasRenderingContext2D;
import js.html.Element;
import js.html.InputElement;
import js.html.KeyboardEvent;
import js.html.MouseEvent;
import js.html.SelectElement;
import world.Fixtures;
import world.GridMap.Prop;
import world.MapData;

private enum Tool {
	Select;
	Brush;
	Rect;
	Fill;
	PropTool;
	GuestTool;
	LightTool;
	LampTool;
	FixtureTool;
	StartTool;
}

private enum Sel {
	SProp(i:Int);
	SFixture(i:Int);
	SGuest(i:Int);
	SLight(i:Int);
	SLamp(i:Int);
	SStart;
}

private enum Drag {
	Pan(sx:Float, sy:Float, vx:Float, vy:Float);
	Paint;
	CellRect(x0:Int, y0:Int, x1:Int, y1:Int);
	NewProp(x0:Float, y0:Float, x1:Float, y1:Float);
	Move(dx:Float, dy:Float);
	Corner(i:Int, cx:Int, cy:Int);
}

/**
	Haxen: the Crown & Card map editor (§13.6). Opens the manor or a custom
	map, edits rooms, walls, props, fixtures, guests, lights and the start
	point on a top-down plan, checks the map with the game's own rules, and
	saves maps the game can play.
**/
class Haxen {
	static final TOOLS:Array<{tool:Tool, label:String, key:String, help:String}> = [
		{tool: Select, label: "Sel", key: "V", help: "Select: click to pick; drag to move; drag a prop's corner to resize. Delete removes, Ctrl+D duplicates, arrows nudge."},
		{tool: Brush, label: "Brush", key: "B", help: "Brush: paint cells with the chosen room (or Wall). Right-drag or Space-drag pans."},
		{tool: Rect, label: "Rect", key: "R", help: "Rectangle: drag to fill a block of cells with the chosen room."},
		{tool: Fill, label: "Fill", key: "F", help: "Fill: click to repaint a connected area of the same room."},
		{tool: PropTool, label: "Prop", key: "P", help: "Prop: drag out a box (a table, a desk, a pillar). Set its height and textures under Selection."},
		{tool: GuestTool, label: "Guest", key: "G", help: "Guest: click to place a character."},
		{tool: LightTool, label: "Light", key: "L", help: "Light: click to place a point light."},
		{tool: LampTool, label: "Lamp", key: "C", help: "Chandelier: click to place a candle chandelier sprite."},
		{tool: FixtureTool, label: "Fix", key: "X", help: "Fixture: pick a set piece below, then click to place its anchor."},
		{tool: StartTool, label: "Start", key: "S", help: "Start: click to move where the player begins."},
	];

	static final ROOM_COLORS = ["#8c3a44", "#2f7a4a", "#3a4a8a", "#a8842c", "#6a3a88", "#2a7a80", "#a85a78", "#6a7030", "#8a5a30", "#4a6aa0", "#9a4a2a", "#3a8a6a"];
	static final KEY_CHARS = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789";
	static final SNAPS = [0.0, 0.05, 0.1, 0.25, 0.5, 1.0];
	static inline var WALL = "#";
	static inline var UNDO_LIMIT = 200;

	final doc = Browser.document;
	final canvas:CanvasElement;
	final ctx:CanvasRenderingContext2D;
	final store:HaxenStore;
	var map:MapFile;
	var savedAs:Null<String> = null;
	var dirty = false;
	final undoStack:Array<String> = [];
	final redoStack:Array<String> = [];
	var tool = Select;
	var paintKey = WALL;
	var fixtureType = "frontDesk";
	var sel:Null<Sel> = null;
	var zoom = 20.0;
	var viewX = 8.0;
	var viewY = 6.0;
	var snap = 0.1;
	var problems:Array<Problem> = [];
	var drag:Null<Drag> = null;
	var dragStart = "";
	var spaceDown = false;
	var mouseX = 0.0;
	var mouseY = 0.0;
	var drawQueued = false;
	var checkTimer = -1;

	/** Fit the view on the next draw (the canvas may not have a size yet). **/
	var fitPending = true;

	static function main() new Haxen();

	function new() {
		canvas = cast doc.getElementById("canvas");
		ctx = canvas.getContext2d();
		var params = new js.html.URLSearchParams(Browser.location.search);
		store = new HaxenStore(params.get("api"));
		map = MapData.blank("Untitled");
		buildTools();
		bindTop();
		bindCanvas();
		bindKeys();
		var snapSelect:SelectElement = cast doc.createElement("select");
		for (s in SNAPS) addOption(snapSelect, s == 0 ? "off" : Std.string(s) + " m", Std.string(s));
		snapSelect.value = Std.string(snap);
		snapSelect.onchange = _ -> snap = Std.parseFloat(snapSelect.value);
		var snapLabel = doc.getElementById("snaplabel");
		snapLabel.textContent = "Snap ";
		snapLabel.appendChild(snapSelect);
		Browser.window.addEventListener("resize", () -> invalidate());
		Browser.window.addEventListener("beforeunload", (e:js.html.Event) -> if (dirty) {
			e.preventDefault();
			Reflect.setField(e, "returnValue", "");
		});
		loaded(map, null);
		var open = params.get("open");
		if (open != null) openSaved(open) else showOpen();
	}

	// --- Document ---

	function loaded(m:MapFile, name:Null<String>):Void {
		map = m;
		savedAs = name;
		dirty = false;
		undoStack.resize(0);
		redoStack.resize(0);
		sel = null;
		paintKey = map.sectors.length > 0 ? map.sectors[0].key : WALL;
		fitPending = true;
		refreshAll();
	}

	/** Records the map before a change, for undo. **/
	function change(apply:Void->Void):Void {
		pushUndo(MapData.stringify(map));
		apply();
		changed();
	}

	function pushUndo(snapshot:String):Void {
		undoStack.push(snapshot);
		if (undoStack.length > UNDO_LIMIT) undoStack.shift();
		redoStack.resize(0);
	}

	function changed():Void {
		dirty = true;
		scheduleCheck();
		refreshDoc();
		refreshMapPanel();
		invalidate();
	}

	function undo():Void {
		if (undoStack.length == 0) return;
		redoStack.push(MapData.stringify(map));
		map = MapData.parse(undoStack.pop());
		afterHistory();
	}

	function redo():Void {
		if (redoStack.length == 0) return;
		undoStack.push(MapData.stringify(map));
		map = MapData.parse(redoStack.pop());
		afterHistory();
	}

	function afterHistory():Void {
		if (!selectionValid()) sel = null;
		dirty = true;
		refreshAll();
	}

	function refreshAll():Void {
		refreshDoc();
		refreshRooms();
		refreshMapPanel();
		refreshSelection();
		scheduleCheck();
		invalidate();
	}

	function refreshDoc():Void {
		doc.getElementById("docname").textContent = map.name + (savedAs == null ? "  (not saved)" : dirty ? "  ·  unsaved changes" : "  ·  saved in " + store.where);
		(cast doc.getElementById("undo") : js.html.ButtonElement).disabled = undoStack.length == 0;
		(cast doc.getElementById("redo") : js.html.ButtonElement).disabled = redoStack.length == 0;
		doc.title = (dirty ? "* " : "") + map.name + " · Haxen";
	}

	function message(text:String, bad = false):Void {
		var m = doc.getElementById("message");
		m.textContent = text;
		m.className = bad ? "bad" : "";
	}

	// --- Top bar ---

	function bindTop():Void {
		click("new", () -> {
			if (!discardOk()) return;
			loaded(MapData.blank("Untitled"), null);
			message("New map. Paint rooms, then save.");
		});
		click("open", showOpen);
		click("save", () -> save(null));
		click("saveas", () -> {
			var name = Browser.window.prompt("Save the map as:", map.name);
			if (name != null) save(StringTools.trim(name));
		});
		click("export", exportFile);
		click("import", () -> (cast doc.getElementById("file") : InputElement).click());
		var file:InputElement = cast doc.getElementById("file");
		file.onchange = _ -> {
			if (file.files.length == 0) return;
			var reader = new js.html.FileReader();
			reader.onload = _ -> {
				try {
					var m = MapData.parse(reader.result);
					if (!discardOk()) return;
					loaded(m, null);
					dirty = true;
					refreshDoc();
					message('Imported "${m.name}". Save it to keep it.');
				} catch (e:Dynamic) message('That file isn\'t a map: $e', true);
				file.value = "";
			};
			reader.readAsText(file.files[0]);
		};
		click("undo", undo);
		click("redo", redo);
		click("fit", () -> {
			fit();
			invalidate();
		});
		click("play", playtest);
	}

	function click(id:String, f:Void->Void):Void doc.getElementById(id).onclick = _ -> f();

	function discardOk():Bool return !dirty || Browser.window.confirm("Discard the unsaved changes to this map?");

	function save(asName:Null<String>, ?then:Void->Void):Void {
		var name = asName != null ? asName : map.name;
		if (!MapData.validName(name) || name.toLowerCase() == "manor") {
			message("Map names are 1-40 letters, digits, spaces, dashes or underscores (and not \"manor\").", true);
			return;
		}
		store.list((names, _) -> {
			if (name != savedAs && names.indexOf(name) >= 0 && !Browser.window.confirm('A map called "$name" already exists. Replace it?')) return;
			if (map.name != name) change(() -> map.name = name);
			store.save(name, MapData.stringify(map), error -> {
				if (error != null) {
					message('Couldn\'t save: $error.', true);
					return;
				}
				savedAs = name;
				dirty = false;
				refreshDoc();
				refreshMapPanel();
				var errors = [for (p in problems) if (p.error) p].length;
				message('Saved "$name" in ${store.where}.' + (errors > 0 ? ' It has $errors problem${errors == 1 ? "" : "s"} to fix before it can be played.' : ""), errors > 0);
				if (then != null) then();
			});
		});
	}

	function exportFile():Void {
		var blob = new js.html.Blob([MapData.stringify(map)], {type: "application/json"});
		var a:js.html.AnchorElement = cast doc.createElement("a");
		a.href = js.html.URL.createObjectURL(blob);
		a.download = map.name + ".json";
		a.click();
		message('Downloaded ${map.name}.json.');
	}

	function playtest():Void {
		problems = MapData.check(map);
		refreshProblems();
		if (MapData.hasErrors(problems)) {
			message("Fix the problems listed on the right before play testing.", true);
			return;
		}
		save(null, () -> store.playtest(map.name, error -> message(error == null ? 'Starting the game on "${map.name}"...' : 'Couldn\'t start the game: $error.', error != null)));
	}

	// --- Open dialog ---

	function showOpen():Void {
		var dialog = doc.getElementById("dialog");
		dialog.innerHTML = "";
		var h = doc.createElement("h3");
		h.textContent = "OPEN A MAP";
		dialog.appendChild(h);
		item(dialog, "Dodriec Manor", "The game's own map. Opens a copy to change.", "Open a copy", () -> {
			if (!discardOk()) return;
			var m = MapData.parse(haxe.Resource.getString("manor"));
			m.name = "Dodriec Manor copy";
			loaded(m, null);
			dirty = true;
			refreshDoc();
			closeModal();
			message("Opened a copy of Dodriec Manor. Save it under a new name to keep your changes.");
		});
		item(dialog, "Blank map", "A single room inside four walls.", "New", () -> {
			if (!discardOk()) return;
			loaded(MapData.blank("Untitled"), null);
			closeModal();
		});
		var saved = doc.createElement("h3");
		saved.style.marginTop = "14px";
		saved.textContent = "SAVED IN " + store.where.toUpperCase();
		dialog.appendChild(saved);
		var list = doc.createDivElement();
		list.className = "hint";
		list.textContent = "Loading...";
		dialog.appendChild(list);
		store.list((names, error) -> {
			list.textContent = error != null ? 'Couldn\'t list maps: $error.' : names.length == 0 ? "No saved maps yet." : "";
			list.className = names.length == 0 ? "hint" : "";
			for (n in names) {
				var row = item(list, n, "", "Open", () -> {
					if (!discardOk()) return;
					openSaved(n);
				});
				var del = doc.createButtonElement();
				del.textContent = "Delete";
				del.onclick = _ -> if (Browser.window.confirm('Delete the map "$n"? This can\'t be undone.')) store.remove(n, e -> {
					if (e != null) message('Couldn\'t delete: $e.', true) else {
						row.remove();
						message('Deleted "$n".');
					}
				});
				row.appendChild(del);
			}
		});
		var close = doc.createButtonElement();
		close.textContent = "Close";
		close.style.marginTop = "12px";
		close.onclick = _ -> closeModal();
		dialog.appendChild(close);
		doc.getElementById("modal").className = "open";
	}

	function item(parent:Element, title:String, detail:String, action:String, f:Void->Void):Element {
		var row = doc.createDivElement();
		row.className = "map-item";
		var label = doc.createSpanElement();
		label.innerHTML = StringTools.htmlEscape(title) + (detail == "" ? "" : '<br><small style="color:var(--muted)">${StringTools.htmlEscape(detail)}</small>');
		row.appendChild(label);
		var b = doc.createButtonElement();
		b.textContent = action;
		b.onclick = _ -> f();
		row.appendChild(b);
		parent.appendChild(row);
		return row;
	}

	function closeModal():Void doc.getElementById("modal").className = "";

	function openSaved(name:String):Void {
		store.load(name, (text, error) -> {
			if (text == null) {
				message('Couldn\'t open "$name": $error.', true);
				return;
			}
			try {
				loaded(MapData.parse(text), name);
				closeModal();
				message('Opened "$name".');
			} catch (e:Dynamic) message('"$name" isn\'t a readable map: $e', true);
		});
	}

	// --- Tools ---

	function buildTools():Void {
		var box = doc.getElementById("tools");
		for (t in TOOLS) {
			var b = doc.createButtonElement();
			b.innerHTML = '${t.label}<br><small>${t.key}</small>';
			b.title = t.help;
			b.onclick = _ -> setTool(t.tool);
			b.id = "tool-" + t.key;
			box.appendChild(b);
		}
		setTool(Select);
	}

	function setTool(t:Tool):Void {
		tool = t;
		for (d in TOOLS) doc.getElementById("tool-" + d.key).className = d.tool == t ? "on" : "";
		for (d in TOOLS) if (d.tool == t) message(d.help);
		canvas.style.cursor = t == Select ? "default" : "crosshair";
		refreshSelection();
	}

	// --- Canvas input ---

	function bindCanvas():Void {
		canvas.oncontextmenu = e -> e.preventDefault();
		canvas.onmousedown = (e:MouseEvent) -> onDown(e);
		Browser.window.addEventListener("mousemove", (e:MouseEvent) -> onMove(e));
		Browser.window.addEventListener("mouseup", (e:MouseEvent) -> onUp(e));
		canvas.addEventListener("wheel", (e:js.html.WheelEvent) -> {
			e.preventDefault();
			var wx = worldX(e.offsetX), wy = worldY(e.offsetY);
			zoom = Math.max(3, Math.min(160, zoom * (e.deltaY < 0 ? 1.15 : 1 / 1.15)));
			// Keep the point under the cursor still.
			viewX = wx - (e.offsetX - canvas.clientWidth / 2) / zoom;
			viewY = wy + (e.offsetY - canvas.clientHeight / 2) / zoom;
			invalidate();
		}, {passive: false});
	}

	function onDown(e:MouseEvent):Void {
		var x = worldX(e.offsetX), y = worldY(e.offsetY);
		if (e.button == 1 || e.button == 2 || spaceDown) {
			drag = Pan(e.clientX, e.clientY, viewX, viewY);
			return;
		}
		if (e.button != 0) return;
		dragStart = MapData.stringify(map);
		var cx = Math.floor(x), cy = Math.floor(y);
		switch tool {
			case Select:
				var corner = cornerAt(e.offsetX, e.offsetY);
				if (corner != null) {
					drag = corner;
					return;
				}
				sel = hitTest(x, y);
				refreshSelection();
				if (sel != null) {
					var p = position(sel);
					drag = Move(x - p.x, y - p.y);
				}
				invalidate();
			case Brush:
				drag = Paint;
				paintCell(cx, cy);
			case Rect:
				drag = CellRect(cx, cy, cx, cy);
			case Fill:
				flood(cx, cy);
				commitDrag();
			case PropTool:
				var sx = snapped(x), sy = snapped(y);
				drag = NewProp(sx, sy, sx, sy);
			case GuestTool:
				place(() -> {
					map.guests.push({name: 'Guest ${map.guests.length + 1}', x: snapped(x), y: snapped(y), facing: 90, art: "masked_guest"});
					SGuest(map.guests.length - 1);
				});
			case LightTool:
				place(() -> {
					map.lights.push({x: snapped(x), y: snapped(y), z: 3, radius: 7, power: 9});
					SLight(map.lights.length - 1);
				});
			case LampTool:
				place(() -> {
					map.chandeliers.push({x: snapped(x), y: snapped(y), z: 3, width: 1.5});
					SLamp(map.chandeliers.length - 1);
				});
			case FixtureTool:
				place(() -> {
					map.fixtures.push({type: fixtureType, x: snapped(x), y: snapped(y)});
					SFixture(map.fixtures.length - 1);
				});
			case StartTool:
				place(() -> {
					map.start.x = snapped(x);
					map.start.y = snapped(y);
					SStart;
				});
		}
	}

	function place(add:Void->Sel):Void {
		sel = add();
		commitDrag();
		refreshSelection();
	}

	function onMove(e:MouseEvent):Void {
		var rect = canvas.getBoundingClientRect();
		mouseX = e.clientX - rect.left;
		mouseY = e.clientY - rect.top;
		var x = worldX(mouseX), y = worldY(mouseY);
		updateStatus(x, y);
		switch drag {
			case null:
			case Pan(sx, sy, vx, vy):
				viewX = vx - (e.clientX - sx) / zoom;
				viewY = vy + (e.clientY - sy) / zoom;
			case Paint:
				paintCell(Math.floor(x), Math.floor(y));
			case CellRect(x0, y0, _, _):
				drag = CellRect(x0, y0, Math.floor(x), Math.floor(y));
			case NewProp(x0, y0, _, _):
				drag = NewProp(x0, y0, snapped(x), snapped(y));
			case Move(dx, dy):
				if (sel != null) moveTo(sel, snapped(x - dx), snapped(y - dy));
			case Corner(i, cx, cy):
				var p = map.props[i];
				if (cx == 0) p.x0 = Math.min(snapped(x), p.x1 - .05) else p.x1 = Math.max(snapped(x), p.x0 + .05);
				if (cy == 0) p.y0 = Math.min(snapped(y), p.y1 - .05) else p.y1 = Math.max(snapped(y), p.y0 + .05);
		}
		if (drag != null) invalidate();
	}

	function onUp(e:MouseEvent):Void {
		switch drag {
			case null:
				return;
			case Pan(_, _, _, _):
				drag = null;
				return;
			case CellRect(x0, y0, x1, y1):
				for (cy in Std.int(Math.min(y0, y1))...Std.int(Math.max(y0, y1)) + 1)
					for (cx in Std.int(Math.min(x0, x1))...Std.int(Math.max(x0, x1)) + 1) setCell(cx, cy, paintKey);
			case NewProp(x0, y0, x1, y1):
				var ax = Math.min(x0, x1), bx = Math.max(x0, x1), ay = Math.min(y0, y1), by = Math.max(y0, y1);
				if (bx - ax >= .05 && by - ay >= .05) {
					map.props.push({x0: ax, y0: ay, x1: bx, y1: by, height: .9, baseZ: 0, topTex: "tableWood", sideTex: "tableWood", solid: true});
					sel = SProp(map.props.length - 1);
				}
			default:
		}
		drag = null;
		commitDrag();
		refreshSelection();
	}

	/** Ends a drag: records the pre-drag map for undo if anything changed. **/
	function commitDrag():Void {
		drag = null;
		if (dragStart != "" && MapData.stringify(map) != dragStart) {
			pushUndo(dragStart);
			changed();
			refreshRooms();
		}
		dragStart = "";
		invalidate();
	}

	function bindKeys():Void {
		Browser.window.addEventListener("keydown", (e:KeyboardEvent) -> {
			var target:Element = cast e.target;
			var typing = target != null && (target.tagName == "INPUT" || target.tagName == "SELECT" || target.tagName == "TEXTAREA");
			var ctrl = e.ctrlKey || e.metaKey;
			if (ctrl && e.key.toLowerCase() == "s") {
				e.preventDefault();
				save(null);
				return;
			}
			if (typing) return;
			if (ctrl) {
				switch e.key.toLowerCase() {
					case "z": e.shiftKey ? redo() : undo();
					case "y": redo();
					case "o": showOpen();
					case "d": duplicate();
					default: return;
				}
				e.preventDefault();
				return;
			}
			if (e.key == " ") {
				spaceDown = true;
				e.preventDefault();
				return;
			}
			if (e.key == "Delete" || e.key == "Backspace") {
				deleteSelection();
				return;
			}
			if (e.key == "Escape") {
				sel = null;
				closeModal();
				refreshSelection();
				invalidate();
				return;
			}
			if (e.key == "Home") {
				fit();
				invalidate();
				return;
			}
			if (e.key == "+" || e.key == "=") zoomBy(1.25);
			if (e.key == "-") zoomBy(1 / 1.25);
			if (StringTools.startsWith(e.key, "Arrow") && sel != null) {
				var step = (snap > 0 ? snap : .05) * (e.shiftKey ? 10 : 1);
				var p = position(sel);
				var dx = e.key == "ArrowLeft" ? -step : e.key == "ArrowRight" ? step : 0;
				var dy = e.key == "ArrowDown" ? -step : e.key == "ArrowUp" ? step : 0;
				var s = sel;
				change(() -> moveTo(s, round(p.x + dx), round(p.y + dy)));
				refreshSelection();
				e.preventDefault();
				return;
			}
			for (t in TOOLS) if (e.key.toUpperCase() == t.key) setTool(t.tool);
		});
		Browser.window.addEventListener("keyup", (e:KeyboardEvent) -> if (e.key == " ") spaceDown = false);
	}

	function zoomBy(f:Float):Void {
		zoom = Math.max(3, Math.min(160, zoom * f));
		invalidate();
	}

	// --- Cells ---

	inline function width():Int return map.rows[0].length;

	inline function height():Int return map.rows.length;

	function cellKey(cx:Int, cy:Int):String {
		if (cx < 0 || cy < 0 || cx >= width() || cy >= height()) return WALL;
		return map.rows[height() - 1 - cy].charAt(cx);
	}

	function setCell(cx:Int, cy:Int, key:String):Void {
		if (cx < 0 || cy < 0 || cx >= width() || cy >= height()) return;
		var r = height() - 1 - cy;
		var row = map.rows[r];
		if (row.charAt(cx) == key) return;
		map.rows[r] = row.substr(0, cx) + key + row.substr(cx + 1);
	}

	function paintCell(cx:Int, cy:Int):Void {
		setCell(cx, cy, paintKey);
		invalidate();
	}

	function flood(cx:Int, cy:Int):Void {
		var from = cellKey(cx, cy);
		if (from == paintKey || cx < 0 || cy < 0 || cx >= width() || cy >= height()) return;
		var stack = [[cx, cy]];
		while (stack.length > 0) {
			var c = stack.pop();
			if (cellKey(c[0], c[1]) != from || c[0] < 0 || c[1] < 0 || c[0] >= width() || c[1] >= height()) continue;
			setCell(c[0], c[1], paintKey);
			stack.push([c[0] + 1, c[1]]);
			stack.push([c[0] - 1, c[1]]);
			stack.push([c[0], c[1] + 1]);
			stack.push([c[0], c[1] - 1]);
		}
	}

	// --- Selection ---

	function selectionValid():Bool {
		return switch sel {
			case null: true;
			case SProp(i): i < map.props.length;
			case SFixture(i): i < map.fixtures.length;
			case SGuest(i): i < map.guests.length;
			case SLight(i): i < map.lights.length;
			case SLamp(i): i < map.chandeliers.length;
			case SStart: true;
		}
	}

	function position(s:Sel):{x:Float, y:Float} {
		return switch s {
			case SProp(i): {x: map.props[i].x0, y: map.props[i].y0};
			case SFixture(i): {x: map.fixtures[i].x, y: map.fixtures[i].y};
			case SGuest(i): {x: map.guests[i].x, y: map.guests[i].y};
			case SLight(i): {x: map.lights[i].x, y: map.lights[i].y};
			case SLamp(i): {x: map.chandeliers[i].x, y: map.chandeliers[i].y};
			case SStart: {x: map.start.x, y: map.start.y};
		}
	}

	function moveTo(s:Sel, x:Float, y:Float):Void {
		switch s {
			case SProp(i):
				var p = map.props[i], w = p.x1 - p.x0, h = p.y1 - p.y0;
				p.x0 = x;
				p.y0 = y;
				p.x1 = round(x + w);
				p.y1 = round(y + h);
			case SFixture(i):
				map.fixtures[i].x = x;
				map.fixtures[i].y = y;
			case SGuest(i):
				var g = map.guests[i];
				if (g.walkTo != null) g.walkTo = {x: round(g.walkTo.x + x - g.x), y: round(g.walkTo.y + y - g.y)};
				g.x = x;
				g.y = y;
			case SLight(i):
				map.lights[i].x = x;
				map.lights[i].y = y;
			case SLamp(i):
				map.chandeliers[i].x = x;
				map.chandeliers[i].y = y;
			case SStart:
				map.start.x = x;
				map.start.y = y;
		}
	}

	function hitTest(x:Float, y:Float):Null<Sel> {
		var r = Math.max(.35, 8 / zoom);
		inline function near(px:Float, py:Float) return (px - x) * (px - x) + (py - y) * (py - y) <= r * r;
		if (near(map.start.x, map.start.y)) return SStart;
		var i = map.guests.length;
		while (i-- > 0) if (near(map.guests[i].x, map.guests[i].y)) return SGuest(i);
		i = map.chandeliers.length;
		while (i-- > 0) if (near(map.chandeliers[i].x, map.chandeliers[i].y)) return SLamp(i);
		i = map.lights.length;
		while (i-- > 0) if (near(map.lights[i].x, map.lights[i].y)) return SLight(i);
		i = map.fixtures.length;
		while (i-- > 0) {
			var f = map.fixtures[i], k = Fixtures.get(f.type);
			if (k != null && x >= f.x + k.x0 && x <= f.x + k.x1 && y >= f.y + k.y0 && y <= f.y + k.y1) return SFixture(i);
		}
		var best = -1, bestArea = Math.POSITIVE_INFINITY;
		for (j in 0...map.props.length) {
			var p = map.props[j];
			if (x >= p.x0 && x <= p.x1 && y >= p.y0 && y <= p.y1) {
				var area = (p.x1 - p.x0) * (p.y1 - p.y0);
				if (area < bestArea) {
					bestArea = area;
					best = j;
				}
			}
		}
		return best >= 0 ? SProp(best) : null;
	}

	/** A resize handle of the selected prop under the mouse. **/
	function cornerAt(sx:Float, sy:Float):Null<Drag> {
		switch sel {
			case SProp(i):
				var p = map.props[i];
				for (cx in 0...2) for (cy in 0...2) {
					var hx = screenX(cx == 0 ? p.x0 : p.x1), hy = screenY(cy == 0 ? p.y0 : p.y1);
					if (Math.abs(hx - sx) <= 6 && Math.abs(hy - sy) <= 6) return Corner(i, cx, cy);
				}
			default:
		}
		return null;
	}

	function deleteSelection():Void {
		var s = sel;
		if (s == null || s == SStart) return;
		change(() -> switch s {
			case SProp(i): map.props.splice(i, 1);
			case SFixture(i): map.fixtures.splice(i, 1);
			case SGuest(i): map.guests.splice(i, 1);
			case SLight(i): map.lights.splice(i, 1);
			case SLamp(i): map.chandeliers.splice(i, 1);
			default:
		});
		sel = null;
		refreshSelection();
	}

	function duplicate():Void {
		var s = sel;
		if (s == null) return;
		change(() -> {
			var off = 1.0;
			switch s {
				case SProp(i):
					var p:Prop = Reflect.copy(map.props[i]);
					p.x0 += off;
					p.x1 += off;
					map.props.push(p);
					sel = SProp(map.props.length - 1);
				case SFixture(i):
					map.fixtures.push({type: map.fixtures[i].type, x: map.fixtures[i].x + off, y: map.fixtures[i].y});
					sel = SFixture(map.fixtures.length - 1);
				case SGuest(i):
					var g:GuestDef = Reflect.copy(map.guests[i]);
					g.x += off;
					g.walkTo = g.walkTo == null ? null : {x: g.walkTo.x + off, y: g.walkTo.y};
					map.guests.push(g);
					sel = SGuest(map.guests.length - 1);
				case SLight(i):
					var l:LightDef = Reflect.copy(map.lights[i]);
					l.x += off;
					map.lights.push(l);
					sel = SLight(map.lights.length - 1);
				case SLamp(i):
					var c:ChandelierDef = Reflect.copy(map.chandeliers[i]);
					c.x += off;
					map.chandeliers.push(c);
					sel = SLamp(map.chandeliers.length - 1);
				case SStart:
			}
		});
		refreshSelection();
	}

	// --- Side panel: selection ---

	function refreshSelection():Void {
		var box = doc.getElementById("selection");
		box.innerHTML = "";
		if (!selectionValid()) sel = null;
		switch sel {
			case null:
				if (tool == FixtureTool) {
					var s:SelectElement = cast doc.createElement("select");
					for (k in Fixtures.KINDS) addOption(s, k.label, k.type);
					s.value = fixtureType;
					s.onchange = _ -> {
						fixtureType = s.value;
						refreshSelection();
					};
					row(box, "Place", s);
					hint(box, Fixtures.get(fixtureType).description);
				} else hint(box, "Nothing selected. Use the Select tool (V) to pick something on the plan.");
			case SProp(i):
				var p = map.props[i];
				hint(box, "Prop: a box standing on the floor.");
				num(box, "West x", p.x0, v -> p.x0 = v);
				num(box, "South y", p.y0, v -> p.y0 = v);
				num(box, "East x", p.x1, v -> p.x1 = v);
				num(box, "North y", p.y1, v -> p.y1 = v);
				num(box, "Base (m)", p.baseZ == null ? 0 : p.baseZ, v -> p.baseZ = v);
				num(box, "Top (m)", p.height, v -> p.height = v);
				pick(box, "Top texture", MapData.TEXTURES, p.topTex, v -> p.topTex = v);
				pick(box, "Side texture", MapData.TEXTURES, p.sideTex, v -> p.sideTex = v);
				check(box, "Solid", p.solid != false, v -> p.solid = v);
				check(box, "Walk on top", p.walkable == true, v -> p.walkable = v);
				check(box, "Invisible", p.hidden == true, v -> p.hidden = v);
			case SFixture(i):
				var f = map.fixtures[i];
				var k = Fixtures.get(f.type);
				pick(box, "Fixture", [for (kk in Fixtures.KINDS) kk.type], f.type, v -> f.type = v, [for (kk in Fixtures.KINDS) kk.label]);
				num(box, "Anchor x", f.x, v -> f.x = v);
				num(box, "Anchor y", f.y, v -> f.y = v);
				if (k != null) hint(box, k.description);
			case SGuest(i):
				var g = map.guests[i];
				text(box, "Name", g.name, v -> g.name = v);
				pick(box, "Art", MapData.ARTS, g.art, v -> g.art = v);
				num(box, "x", g.x, v -> g.x = v);
				num(box, "y", g.y, v -> g.y = v);
				num(box, "Facing (°)", g.facing, v -> g.facing = v, 15);
				check(box, "Turns slowly", g.spins == true, v -> g.spins = v ? true : null);
				check(box, "Walks", g.walkTo != null, v -> g.walkTo = v ? {x: g.x, y: g.y + 3} : null);
				if (g.walkTo != null) {
					num(box, "Walk to x", g.walkTo.x, v -> g.walkTo.x = v);
					num(box, "Walk to y", g.walkTo.y, v -> g.walkTo.y = v);
				}
				hint(box, "Facing: 0° east, 90° north, 180° west, -90° south.");
			case SLight(i):
				var l = map.lights[i];
				num(box, "x", l.x, v -> l.x = v);
				num(box, "y", l.y, v -> l.y = v);
				num(box, "Height (m)", l.z, v -> l.z = v);
				num(box, "Radius (m)", l.radius, v -> l.radius = v, .5);
				num(box, "Power", l.power, v -> l.power = v, .5);
			case SLamp(i):
				var c = map.chandeliers[i];
				num(box, "x", c.x, v -> c.x = v);
				num(box, "y", c.y, v -> c.y = v);
				num(box, "Height (m)", c.z, v -> c.z = v);
				num(box, "Width (m)", c.width, v -> c.width = v);
				hint(box, "A decorative candle chandelier. Add a Light near it to light the room.");
			case SStart:
				hint(box, "Where the player begins.");
				num(box, "x", map.start.x, v -> map.start.x = v);
				num(box, "y", map.start.y, v -> map.start.y = v);
				num(box, "Facing (°)", map.start.facing, v -> map.start.facing = v, 15);
		}
	}

	function row(box:Element, label:String, input:Element):Void {
		var r = doc.createDivElement();
		r.className = "row";
		var l = doc.createLabelElement();
		l.textContent = label;
		r.appendChild(l);
		r.appendChild(input);
		box.appendChild(r);
	}

	function hint(box:Element, text:String):Void {
		var d = doc.createDivElement();
		d.className = "hint";
		d.textContent = text;
		box.appendChild(d);
	}

	function num(box:Element, label:String, value:Float, set:Float->Void, step = 0.05):Void {
		var input = doc.createInputElement();
		input.type = "number";
		input.step = Std.string(step);
		input.value = Std.string(round(value));
		input.onchange = _ -> {
			var v = Std.parseFloat(input.value);
			if (Math.isNaN(v)) return;
			change(() -> set(v));
		};
		row(box, label, input);
	}

	function text(box:Element, label:String, value:String, set:String->Void):Void {
		var input = doc.createInputElement();
		input.type = "text";
		input.value = value;
		input.onchange = _ -> change(() -> set(input.value));
		row(box, label, input);
	}

	function check(box:Element, label:String, value:Bool, set:Bool->Void):Void {
		var input = doc.createInputElement();
		input.type = "checkbox";
		input.checked = value;
		input.onchange = _ -> {
			change(() -> set(input.checked));
			refreshSelection();
		};
		row(box, label, input);
	}

	function pick(box:Element, label:String, values:Array<String>, value:String, set:String->Void, ?labels:Array<String>):Void {
		var s:SelectElement = cast doc.createElement("select");
		for (i in 0...values.length) addOption(s, labels == null ? values[i] : labels[i], values[i]);
		if (values.indexOf(value) < 0) addOption(s, value + " (unknown)", value);
		s.value = value;
		s.onchange = _ -> {
			change(() -> set(s.value));
			refreshSelection();
		};
		row(box, label, s);
	}

	function addOption(s:SelectElement, label:String, value:String):Void {
		var o:js.html.OptionElement = cast doc.createElement("option");
		o.textContent = label;
		o.value = value;
		s.appendChild(o);
	}

	// --- Side panel: rooms ---

	function roomColor(key:String):String {
		if (key == WALL) return "#2a2420";
		for (i in 0...map.sectors.length) if (map.sectors[i].key == key) return ROOM_COLORS[i % ROOM_COLORS.length];
		return "#ff00ff";
	}

	function refreshRooms():Void {
		var box = doc.getElementById("rooms");
		box.innerHTML = "";
		var entries = [{key: WALL, name: "Wall (solid)"}].concat([for (s in map.sectors) {key: s.key, name: s.name}]);
		for (e in entries) {
			var r = doc.createDivElement();
			r.className = "room" + (e.key == paintKey ? " on" : "");
			r.innerHTML = '<span class="swatch" style="background:${roomColor(e.key)}"></span><span class="key">${StringTools.htmlEscape(e.key)}</span><span>${StringTools.htmlEscape(e.name)}</span>';
			r.onclick = _ -> {
				paintKey = e.key;
				if (tool != Brush && tool != Rect && tool != Fill) setTool(Brush);
				refreshRooms();
			};
			box.appendChild(r);
		}
		refreshRoomEditor();
		click("addroom", addRoom);
		click("delroom", deleteRoom);
	}

	function refreshRoomEditor():Void {
		var box = doc.getElementById("roomedit");
		box.innerHTML = "";
		var s = null;
		for (x in map.sectors) if (x.key == paintKey) s = x;
		if (s == null) return;
		var room:SectorDef = s;
		text(box, "Key", room.key, v -> renameKey(room, v));
		text(box, "Name", room.name, v -> room.name = v);
		num(box, "Floor (m)", room.floorZ, v -> room.floorZ = v, .1);
		num(box, "Ceiling (m)", room.ceilZ, v -> room.ceilZ = v, .1);
		pick(box, "Floor", MapData.TEXTURES, room.floorTex, v -> room.floorTex = v);
		pick(box, "Ceiling", MapData.TEXTURES, room.ceilTex, v -> room.ceilTex = v);
		pick(box, "Walls", MapData.TEXTURES, room.wallTex, v -> room.wallTex = v);
		pick(box, "Upper walls", MapData.TEXTURES, room.upperTex, v -> room.upperTex = v);
		num(box, "Shade (0-31)", room.shade, v -> room.shade = Math.max(0, Math.min(31, v)), 1);
		hint(box, "Shade darkens the whole room: 0 is brightest. Walls above 3 m use the upper texture.");
	}

	function renameKey(room:SectorDef, v:String):Void {
		if (v.length != 1 || v == WALL) {
			message("A room's key is a single character other than #.", true);
			return;
		}
		for (s in map.sectors) if (s != room && s.key == v) {
			message('Another room already uses "$v".', true);
			return;
		}
		var old = room.key;
		map.rows = [for (r in map.rows) r.split(old).join(v)];
		room.key = v;
		paintKey = v;
		refreshRooms();
	}

	function addRoom():Void {
		var used = [for (s in map.sectors) s.key];
		var key = null;
		for (i in 0...KEY_CHARS.length) if (used.indexOf(KEY_CHARS.charAt(i)) < 0) {
			key = KEY_CHARS.charAt(i);
			break;
		}
		if (key == null) {
			message("That's every key character in use.", true);
			return;
		}
		var k:String = key;
		change(() -> map.sectors.push({key: k, name: 'Room ${map.sectors.length + 1}', floorZ: 0, ceilZ: 3.5, floorTex: "parquet", ceilTex: "coffer", wallTex: "damask",
			upperTex: "damaskUpper", shade: 8}));
		paintKey = k;
		setTool(Brush);
		refreshRooms();
	}

	function deleteRoom():Void {
		var idx = -1;
		for (i in 0...map.sectors.length) if (map.sectors[i].key == paintKey) idx = i;
		if (idx < 0) return;
		var s = map.sectors[idx];
		if (!Browser.window.confirm('Delete the room "${s.name}"? Its cells become wall.')) return;
		change(() -> {
			map.rows = [for (r in map.rows) r.split(s.key).join(WALL)];
			map.sectors.splice(idx, 1);
		});
		paintKey = WALL;
		refreshRooms();
	}

	// --- Side panel: map ---

	function refreshMapPanel():Void {
		var box = doc.getElementById("mapedit");
		box.innerHTML = "";
		text(box, "Name", map.name, v -> map.name = StringTools.trim(v));
		var w = doc.createInputElement(), h = doc.createInputElement();
		for (i in [w, h]) {
			i.type = "number";
			i.min = "3";
			i.max = Std.string(MapData.MAX_SIZE);
		}
		w.value = Std.string(width());
		h.value = Std.string(height());
		var size = doc.createDivElement();
		size.className = "row";
		var l = doc.createLabelElement();
		l.textContent = "Size (m)";
		size.appendChild(l);
		size.appendChild(w);
		size.appendChild(doc.createTextNode("×"));
		size.appendChild(h);
		var b = doc.createButtonElement();
		b.textContent = "Resize";
		b.onclick = _ -> resize(Std.parseInt(w.value), Std.parseInt(h.value));
		size.appendChild(b);
		box.appendChild(size);
		hint(box, "The map grows and shrinks at its north and east edges, so nothing already placed moves.");
		hint(box, '${map.sectors.length} rooms · ${map.props.length} props · ${map.fixtures.length} fixtures · ${map.guests.length} guests · ${map.lights.length} lights');
	}

	function resize(w:Null<Int>, h:Null<Int>):Void {
		if (w == null || h == null || w < 3 || h < 3 || w > MapData.MAX_SIZE || h > MapData.MAX_SIZE) {
			message('Sizes run from 3 to ${MapData.MAX_SIZE} m.', true);
			return;
		}
		var lost = false;
		for (r in 0...height()) for (c in 0...width()) {
			var cy = height() - 1 - r;
			if ((c >= w || cy >= h) && map.rows[r].charAt(c) != WALL) lost = true;
		}
		if (lost && !Browser.window.confirm("Shrinking cuts off painted rooms along the north or east edge. Continue?")) return;
		change(() -> {
			var rows = [];
			var oldH = height();
			// Rows are listed north first; keep the south rows so y coordinates don't change.
			for (i in 0...h) {
				var cy = h - 1 - i;
				var src = cy < oldH ? map.rows[oldH - 1 - cy] : "";
				var line = src.length >= w ? src.substr(0, w) : src + StringTools.rpad("", WALL, w - src.length);
				rows.push(line);
			}
			map.rows = rows;
		});
		refreshMapPanel();
	}

	// --- Problems ---

	function scheduleCheck():Void {
		if (checkTimer >= 0) Browser.window.clearTimeout(checkTimer);
		checkTimer = Browser.window.setTimeout(() -> {
			checkTimer = -1;
			problems = try MapData.check(map) catch (e:Dynamic) [{error: true, message: 'The map can\'t be built: $e'}];
			refreshProblems();
			invalidate();
		}, 250);
	}

	function refreshProblems():Void {
		var box = doc.getElementById("problems");
		box.innerHTML = "";
		if (problems.length == 0) {
			var ok = doc.createDivElement();
			ok.className = "hint";
			ok.style.color = "var(--good)";
			ok.textContent = "No problems. This map can be played.";
			box.appendChild(ok);
			return;
		}
		for (p in problems) {
			var d = doc.createDivElement();
			d.className = "problem" + (p.error ? "" : " warn");
			d.textContent = (p.error ? "" : "Warning: ") + p.message;
			if (p.x != null) {
				d.title = "Show on the plan";
				d.onclick = _ -> {
					viewX = p.x;
					viewY = p.y;
					zoom = Math.max(zoom, 24);
					invalidate();
				};
			}
			box.appendChild(d);
		}
	}

	// --- View ---

	inline function screenX(x:Float):Float return (x - viewX) * zoom + canvas.clientWidth / 2;

	inline function screenY(y:Float):Float return (viewY - y) * zoom + canvas.clientHeight / 2;

	inline function worldX(sx:Float):Float return (sx - canvas.clientWidth / 2) / zoom + viewX;

	inline function worldY(sy:Float):Float return viewY - (sy - canvas.clientHeight / 2) / zoom;

	function snapped(v:Float):Float return snap <= 0 ? round(v) : round(Math.round(v / snap) * snap);

	static function round(v:Float):Float return Math.round(v * 1000) / 1000;

	function fit():Void {
		var cw = Math.max(200, canvas.clientWidth), ch = Math.max(200, canvas.clientHeight);
		viewX = width() / 2;
		viewY = height() / 2;
		zoom = Math.max(3, Math.min(60, Math.min(cw / (width() + 2), ch / (height() + 2))));
	}

	function updateStatus(x:Float, y:Float):Void {
		var cx = Math.floor(x), cy = Math.floor(y);
		var key = cellKey(cx, cy);
		var room = key == WALL ? "wall" : "?";
		for (s in map.sectors) if (s.key == key) room = s.name;
		doc.getElementById("cursor").textContent = 'x ${Math.round(x * 100) / 100}  y ${Math.round(y * 100) / 100}  ·  cell ${cx}, ${cy}  ·  $room';
		doc.getElementById("zoom").textContent = '${Math.round(zoom)} px/m';
	}

	function invalidate():Void {
		if (drawQueued) return;
		drawQueued = true;
		Browser.window.requestAnimationFrame(_ -> {
			drawQueued = false;
			draw();
		});
	}

	function draw():Void {
		var dpr = Browser.window.devicePixelRatio;
		var cw = canvas.clientWidth, ch = canvas.clientHeight;
		if (fitPending && cw > 0 && ch > 0) {
			fitPending = false;
			fit();
		}
		if (canvas.width != Std.int(cw * dpr) || canvas.height != Std.int(ch * dpr)) {
			canvas.width = Std.int(cw * dpr);
			canvas.height = Std.int(ch * dpr);
		}
		ctx.setTransform(dpr, 0, 0, dpr, 0, 0);
		ctx.fillStyle = "#0a0d18";
		ctx.fillRect(0, 0, cw, ch);

		// Cells.
		var x0 = Std.int(Math.max(0, Math.floor(worldX(0)))), x1 = Std.int(Math.min(width() - 1, Math.floor(worldX(cw))));
		var y0 = Std.int(Math.max(0, Math.floor(worldY(ch)))), y1 = Std.int(Math.min(height() - 1, Math.floor(worldY(0))));
		for (cy in y0...y1 + 1) for (cx in x0...x1 + 1) {
			ctx.fillStyle = roomColor(cellKey(cx, cy));
			ctx.fillRect(Math.floor(screenX(cx)), Math.floor(screenY(cy + 1)), Math.ceil(zoom) + 1, Math.ceil(zoom) + 1);
		}
		// Room edges and the grid.
		if (zoom >= 7) {
			ctx.lineWidth = 1;
			for (cx in x0...x1 + 2) {
				ctx.strokeStyle = cx % 5 == 0 ? "rgba(255,255,255,.12)" : "rgba(255,255,255,.05)";
				line(screenX(cx), screenY(y0), screenX(cx), screenY(y1 + 1));
			}
			for (cy in y0...y1 + 2) {
				ctx.strokeStyle = cy % 5 == 0 ? "rgba(255,255,255,.12)" : "rgba(255,255,255,.05)";
				line(screenX(x0), screenY(cy), screenX(x1 + 1), screenY(cy));
			}
		}
		ctx.strokeStyle = "rgba(244,219,165,.55)";
		ctx.lineWidth = 1.5;
		for (cy in y0...y1 + 1) for (cx in x0...x1 + 1) {
			var k = cellKey(cx, cy);
			if (k != cellKey(cx + 1, cy)) line(screenX(cx + 1), screenY(cy), screenX(cx + 1), screenY(cy + 1));
			if (k != cellKey(cx, cy + 1)) line(screenX(cx), screenY(cy + 1), screenX(cx + 1), screenY(cy + 1));
		}
		// Room names at each room's middle.
		if (zoom >= 8) {
			ctx.font = "12px Segoe UI, sans-serif";
			ctx.textAlign = "center";
			for (s in map.sectors) {
				var sx = 0.0, sy = 0.0, n = 0;
				for (r in 0...height()) for (c in 0...width()) if (map.rows[r].charAt(c) == s.key) {
					sx += c + .5;
					sy += height() - r - .5;
					n++;
				}
				if (n == 0) continue;
				ctx.fillStyle = "rgba(239,230,210,.45)";
				ctx.fillText(s.name, screenX(sx / n), screenY(sy / n));
			}
		}

		// Props.
		for (i in 0...map.props.length) {
			var p = map.props[i];
			var rx = screenX(p.x0), ry = screenY(p.y1), rw = (p.x1 - p.x0) * zoom, rh = (p.y1 - p.y0) * zoom;
			ctx.fillStyle = texColor(p.topTex, p.hidden == true ? .12 : p.solid == false ? .45 : .8);
			ctx.fillRect(rx, ry, rw, rh);
			ctx.strokeStyle = p.walkable == true ? "#c8e0ff" : "rgba(0,0,0,.6)";
			ctx.lineWidth = 1;
			ctx.setLineDash(p.hidden == true ? [3, 3] : []);
			ctx.strokeRect(rx + .5, ry + .5, rw, rh);
			ctx.setLineDash([]);
		}
		// Fixtures.
		for (f in map.fixtures) {
			var k = Fixtures.get(f.type);
			if (k == null) continue;
			ctx.strokeStyle = "#f4dba5";
			ctx.fillStyle = "rgba(200,163,94,.18)";
			ctx.lineWidth = 1.5;
			ctx.setLineDash([5, 3]);
			if (k.round) {
				ctx.beginPath();
				ctx.arc(screenX(f.x), screenY(f.y), k.x1 * zoom, 0, Math.PI * 2);
				ctx.fill();
				ctx.stroke();
			} else {
				ctx.fillRect(screenX(f.x + k.x0), screenY(f.y + k.y1), (k.x1 - k.x0) * zoom, (k.y1 - k.y0) * zoom);
				ctx.strokeRect(screenX(f.x + k.x0), screenY(f.y + k.y1), (k.x1 - k.x0) * zoom, (k.y1 - k.y0) * zoom);
			}
			ctx.setLineDash([]);
			dot(f.x, f.y, 3, "#f4dba5");
			if (zoom >= 6) label(k.label, f.x, f.y + (k.round ? 0 : (k.y0 + k.y1) / 2), "#f4dba5");
		}
		// Lights, chandeliers, guests, start.
		for (l in map.lights) {
			ctx.strokeStyle = "rgba(255,220,120,.25)";
			ctx.setLineDash([2, 4]);
			ctx.beginPath();
			ctx.arc(screenX(l.x), screenY(l.y), l.radius * zoom, 0, Math.PI * 2);
			ctx.stroke();
			ctx.setLineDash([]);
			dot(l.x, l.y, 5, "#ffe08a");
		}
		for (c in map.chandeliers) {
			ctx.fillStyle = "#e8c070";
			ctx.save();
			ctx.translate(screenX(c.x), screenY(c.y));
			ctx.rotate(Math.PI / 4);
			ctx.fillRect(-5, -5, 10, 10);
			ctx.restore();
		}
		for (g in map.guests) {
			if (g.walkTo != null) {
				ctx.strokeStyle = "rgba(168,224,160,.6)";
				ctx.setLineDash([4, 3]);
				line(screenX(g.x), screenY(g.y), screenX(g.walkTo.x), screenY(g.walkTo.y));
				ctx.setLineDash([]);
			}
			arrow(g.x, g.y, g.facing, g.art == "hooded_keeper" ? "#b0a0e0" : "#a8e0a0");
			if (zoom >= 26) label(g.name, g.x, g.y - .55, "rgba(239,230,210,.8)");
		}
		arrow(map.start.x, map.start.y, map.start.facing, "#f4dba5", true);

		// Problems with a place.
		for (p in problems) if (p.x != null) {
			ctx.strokeStyle = p.error ? "#f09080" : "#e8c070";
			ctx.lineWidth = 2;
			var sx = screenX(p.x), sy = screenY(p.y);
			line(sx - 6, sy - 6, sx + 6, sy + 6);
			line(sx - 6, sy + 6, sx + 6, sy - 6);
		}

		// Selection.
		if (sel != null && selectionValid()) {
			ctx.strokeStyle = "#ffffff";
			ctx.lineWidth = 1.5;
			switch sel {
				case SProp(i):
					var p = map.props[i];
					ctx.strokeRect(screenX(p.x0) - 2, screenY(p.y1) - 2, (p.x1 - p.x0) * zoom + 4, (p.y1 - p.y0) * zoom + 4);
					ctx.fillStyle = "#ffffff";
					for (cx in [p.x0, p.x1]) for (cy in [p.y0, p.y1]) ctx.fillRect(screenX(cx) - 4, screenY(cy) - 4, 8, 8);
				case SFixture(i):
					var f = map.fixtures[i], k = Fixtures.get(f.type);
					if (k != null) ctx.strokeRect(screenX(f.x + k.x0) - 3, screenY(f.y + k.y1) - 3, (k.x1 - k.x0) * zoom + 6, (k.y1 - k.y0) * zoom + 6);
				default:
					var p = position(sel);
					ctx.beginPath();
					ctx.arc(screenX(p.x), screenY(p.y), 11, 0, Math.PI * 2);
					ctx.stroke();
			}
		}

		// Drag previews.
		switch drag {
			case CellRect(ax, ay, bx, by):
				ctx.strokeStyle = "#ffffff";
				ctx.setLineDash([4, 3]);
				var lx = Math.min(ax, bx), hx = Math.max(ax, bx) + 1, ly = Math.min(ay, by), hy = Math.max(ay, by) + 1;
				ctx.strokeRect(screenX(lx), screenY(hy), (hx - lx) * zoom, (hy - ly) * zoom);
				ctx.setLineDash([]);
			case NewProp(ax, ay, bx, by):
				ctx.strokeStyle = "#ffffff";
				ctx.setLineDash([4, 3]);
				ctx.strokeRect(screenX(Math.min(ax, bx)), screenY(Math.max(ay, by)), Math.abs(bx - ax) * zoom, Math.abs(by - ay) * zoom);
				ctx.setLineDash([]);
			default:
		}
		// North marker.
		ctx.fillStyle = "rgba(239,230,210,.6)";
		ctx.font = "11px Segoe UI, sans-serif";
		ctx.textAlign = "left";
		ctx.fillText("N ↑", 10, 18);
	}

	function line(ax:Float, ay:Float, bx:Float, by:Float):Void {
		ctx.beginPath();
		ctx.moveTo(ax, ay);
		ctx.lineTo(bx, by);
		ctx.stroke();
	}

	function dot(x:Float, y:Float, r:Float, color:String):Void {
		ctx.fillStyle = color;
		ctx.beginPath();
		ctx.arc(screenX(x), screenY(y), r, 0, Math.PI * 2);
		ctx.fill();
	}

	function label(text:String, x:Float, y:Float, color:String):Void {
		ctx.font = "11px Segoe UI, sans-serif";
		ctx.textAlign = "center";
		ctx.fillStyle = "rgba(0,0,0,.7)";
		ctx.fillText(text, screenX(x) + 1, screenY(y) + 4);
		ctx.fillStyle = color;
		ctx.fillText(text, screenX(x), screenY(y) + 3);
	}

	/** A body circle with a facing pointer; the start point is drawn as a bold arrow. **/
	function arrow(x:Float, y:Float, facingDeg:Float, color:String, bold = false):Void {
		var a = facingDeg * Math.PI / 180;
		var sx = screenX(x), sy = screenY(y);
		var r = Math.max(5, .25 * zoom);
		ctx.fillStyle = color;
		ctx.strokeStyle = "rgba(0,0,0,.7)";
		ctx.lineWidth = 1;
		ctx.beginPath();
		if (bold) {
			var len = Math.max(12, .6 * zoom);
			ctx.moveTo(sx + Math.cos(a) * len, sy - Math.sin(a) * len);
			ctx.lineTo(sx + Math.cos(a + 2.5) * len * .6, sy - Math.sin(a + 2.5) * len * .6);
			ctx.lineTo(sx + Math.cos(a - 2.5) * len * .6, sy - Math.sin(a - 2.5) * len * .6);
			ctx.closePath();
		} else ctx.arc(sx, sy, r, 0, Math.PI * 2);
		ctx.fill();
		ctx.stroke();
		if (!bold) {
			ctx.strokeStyle = color;
			ctx.lineWidth = 2;
			line(sx, sy, sx + Math.cos(a) * r * 1.9, sy - Math.sin(a) * r * 1.9);
		}
	}

	static function texColor(tex:String, alpha:Float):String {
		var rgb = switch tex {
			case "stone", "ivory", "marble": "210,204,190";
			case "brass", "flame": "200,163,94";
			case "carpet", "velvet": "140,40,50";
			case "felt": "40,110,60";
			case "tableWood", "parquet": "120,74,40";
			case "green", "greenUpper": "60,100,70";
			default: "150,140,160";
		}
		return 'rgba($rgb,$alpha)';
	}
}
