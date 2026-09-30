// SPDX-License-Identifier: AGPL-3.0-or-later
using System;
using System.Globalization;
using System.Runtime.InteropServices;

namespace CrownAndCard.Launcher;

/**
	The Mac build's controller reader, with the same API as ../src/XInputPad.cs
	(named for it so the shared code needs no change). It reads Apple's
	GameController framework, which sees Xbox, PlayStation and Switch pads, so
	the launcher can be driven from the couch (A or Start plays, LB and RB switch
	tabs, Y toggles the music) and can stream the pad to the browser build.
**/
sealed class XInputPad
{
	public const ushort DPadUp = 0x0001, DPadDown = 0x0002, DPadLeft = 0x0004, DPadRight = 0x0008;
	public const ushort Start = 0x0010, Back = 0x0020, LB = 0x0100, RB = 0x0200;
	public const ushort A = 0x1000, B = 0x2000, X = 0x4000, Y = 0x8000;
	const ushort L3 = 0x0040, R3 = 0x0080;

	ushort previous;

	/** True while any controller is connected (as of the last Poll). **/
	public bool Connected { get; private set; }

	/** Buttons that went down since the last Poll, across all connected controllers. **/
	public ushort Pressed { get; private set; }

	public void Poll()
	{
		ushort now = 0;
		bool any = false;
		GameController.ForEachPad(pad =>
		{
			any = true;
			now |= pad.Buttons;
			return true;
		});
		Connected = any;
		Pressed = (ushort)(now & ~previous);
		previous = now;
	}

	public bool WasPressed(ushort button) => (Pressed & button) != 0;

	/** XInput bit for each button of the browser's "standard" gamepad layout, in its order. **/
	static readonly ushort[] StandardButtons =
	[
		A, B, X, Y, LB, RB, 0 /* LT */, 0 /* RT */, Back, Start, L3, R3, DPadUp, DPadDown, DPadLeft, DPadRight,
	];

	/**
		The first connected controller as compact JSON in the browser's standard
		gamepad layout (see ../src/XInputPad.cs): c = connected, b = button bits
		by standard index, a = sticks (y down is positive), t = triggers.
	**/
	public static string Snapshot()
	{
		string? json = null;
		GameController.ForEachPad(s =>
		{
			int bits = 0;
			for (int i = 0; i < StandardButtons.Length; i++)
				if (StandardButtons[i] != 0 && (s.Buttons & StandardButtons[i]) != 0) bits |= 1 << i;
			if (s.LeftTrigger > 0.12f) bits |= 1 << 6;
			if (s.RightTrigger > 0.12f) bits |= 1 << 7;
			static string F(float v) => Math.Max(-1f, Math.Min(1f, v)).ToString("0.###", CultureInfo.InvariantCulture);
			json = $"{{\"c\":1,\"b\":{bits},\"a\":[{F(s.LX)},{F(-s.LY)},{F(s.RX)},{F(-s.RY)}],\"t\":[{F(s.LeftTrigger)},{F(s.RightTrigger)}]}}";
			return false; // the first pad only
		});
		return json ?? "{\"c\":0}";
	}

	/** One pad's state: XInput-style button bits, sticks (y up is positive, as GameController reports) and triggers 0–1. **/
	struct PadState
	{
		public ushort Buttons;
		public float LX, LY, RX, RY, LeftTrigger, RightTrigger;
	}

	/** GameController.framework through the Objective-C runtime. **/
	static class GameController
	{
		static readonly object Gate = new();
		static bool loaded, available;
		static IntPtr controllerClass;

		static bool EnsureLoaded()
		{
			lock (Gate)
			{
				if (loaded)
					return available;
				loaded = true;
				try
				{
					NativeLibrary.Load("/System/Library/Frameworks/GameController.framework/GameController");
					controllerClass = ObjC.objc_getClass("GCController");
					available = controllerClass != IntPtr.Zero;
					// Keep reading the pad while another window (the game in a browser) is in front.
					if (available && ObjC.Responds(controllerClass, "setShouldMonitorBackgroundEvents:"))
						ObjC.SendBool(controllerClass, ObjC.sel_registerName("setShouldMonitorBackgroundEvents:"), true);
				}
				catch (Exception e)
				{
					Log.Write("Controller support unavailable: " + e.Message);
					available = false;
				}
				return available;
			}
		}

		/** Calls `visit` for each connected pad with an extended (Xbox-style) profile until it returns false. **/
		public static void ForEachPad(Func<PadState, bool> visit)
		{
			if (!EnsureLoaded())
				return;
			var pool = ObjC.objc_autoreleasePoolPush();
			try
			{
				var controllers = ObjC.Get(controllerClass, "controllers");
				var count = (long)ObjC.Get(controllers, "count");
				for (long i = 0; i < count; i++)
				{
					var controller = ObjC.Send(controllers, ObjC.sel_registerName("objectAtIndex:"), (nuint)i);
					var pad = ObjC.Get(controller, "extendedGamepad");
					if (pad == IntPtr.Zero)
						continue;
					if (!visit(Read(pad)))
						break;
				}
			}
			finally
			{
				ObjC.objc_autoreleasePoolPop(pool);
			}
		}

		static PadState Read(IntPtr pad)
		{
			var s = new PadState();
			void Button(string name, ushort bit)
			{
				var b = ObjC.Get(pad, name);
				if (b != IntPtr.Zero && ObjC.SendReturnsBool(b, ObjC.sel_registerName("isPressed")))
					s.Buttons |= bit;
			}
			Button("buttonA", A);
			Button("buttonB", B);
			Button("buttonX", X);
			Button("buttonY", Y);
			Button("leftShoulder", LB);
			Button("rightShoulder", RB);
			Button("buttonMenu", Start);
			if (ObjC.Responds(pad, "buttonOptions")) Button("buttonOptions", Back);
			if (ObjC.Responds(pad, "leftThumbstickButton")) Button("leftThumbstickButton", L3);
			if (ObjC.Responds(pad, "rightThumbstickButton")) Button("rightThumbstickButton", R3);
			var dpad = ObjC.Get(pad, "dpad");
			foreach (var (name, bit) in new[] { ("up", DPadUp), ("down", DPadDown), ("left", DPadLeft), ("right", DPadRight) })
			{
				var b = ObjC.Get(dpad, name);
				if (b != IntPtr.Zero && ObjC.SendReturnsBool(b, ObjC.sel_registerName("isPressed")))
					s.Buttons |= bit;
			}
			float Value(IntPtr input) => input == IntPtr.Zero ? 0 : ObjC.SendReturnsFloat(input, ObjC.sel_registerName("value"));
			var left = ObjC.Get(pad, "leftThumbstick");
			var right = ObjC.Get(pad, "rightThumbstick");
			s.LX = Value(ObjC.Get(left, "xAxis"));
			s.LY = Value(ObjC.Get(left, "yAxis"));
			s.RX = Value(ObjC.Get(right, "xAxis"));
			s.RY = Value(ObjC.Get(right, "yAxis"));
			s.LeftTrigger = Value(ObjC.Get(pad, "leftTrigger"));
			s.RightTrigger = Value(ObjC.Get(pad, "rightTrigger"));
			return s;
		}
	}
}
