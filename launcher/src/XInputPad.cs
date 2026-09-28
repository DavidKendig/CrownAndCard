// SPDX-License-Identifier: AGPL-3.0-or-later
using System;
using System.Runtime.InteropServices;

namespace CrownAndCard.Launcher;

/**
	Reads Xbox-style controllers through XInput (built into Windows 10 and 11),
	so the launcher can be driven from the couch: A or Start plays, LB and RB
	switch tabs, Y toggles the music.
**/
sealed class XInputPad
{
	public const ushort DPadUp = 0x0001, DPadDown = 0x0002, DPadLeft = 0x0004, DPadRight = 0x0008;
	public const ushort Start = 0x0010, Back = 0x0020, LB = 0x0100, RB = 0x0200;
	public const ushort A = 0x1000, B = 0x2000, X = 0x4000, Y = 0x8000;

	ushort previous;

	/** True while any controller is connected (as of the last Poll). **/
	public bool Connected { get; private set; }

	/** Buttons that went down since the last Poll, across all connected controllers. **/
	public ushort Pressed { get; private set; }

	public void Poll()
	{
		ushort now = 0;
		bool any = false;
		for (int user = 0; user < 4; user++)
		{
			try
			{
				if (XInputGetState(user, out var state) == 0)
				{
					any = true;
					now |= state.Buttons;
				}
			}
			catch (DllNotFoundException)
			{
				break; // no XInput on this system
			}
		}
		Connected = any;
		Pressed = (ushort)(now & ~previous);
		previous = now;
	}

	public bool WasPressed(ushort button) => (Pressed & button) != 0;

	/** XInput bit for each button of the browser's "standard" gamepad layout, in its order. **/
	static readonly ushort[] StandardButtons =
	[
		A, B, X, Y, LB, RB, 0 /* LT */, 0 /* RT */, Back, Start, 0x0040 /* L3 */, 0x0080 /* R3 */, DPadUp, DPadDown, DPadLeft, DPadRight,
	];

	/**
		The first connected controller as compact JSON in the browser's standard
		gamepad layout (so the game reads it like a Gamepad API pad): c = connected,
		b = button bits by standard index, a = sticks (y down is positive, as in
		browsers), t = triggers. The game uses this when the browser can't see the
		controller, for example while Steam's desktop layout owns it.
	**/
	public static string Snapshot()
	{
		for (int user = 0; user < 4; user++)
		{
			State s;
			try
			{
				if (XInputGetState(user, out s) != 0) continue;
			}
			catch (DllNotFoundException)
			{
				break;
			}
			int bits = 0;
			for (int i = 0; i < StandardButtons.Length; i++)
				if (StandardButtons[i] != 0 && (s.Buttons & StandardButtons[i]) != 0) bits |= 1 << i;
			if (s.LeftTrigger > 30) bits |= 1 << 6;
			if (s.RightTrigger > 30) bits |= 1 << 7;
			static string Axis(int v) => Math.Max(-1.0, Math.Min(1.0, v / 32767.0)).ToString("0.###", System.Globalization.CultureInfo.InvariantCulture);
			static string Trigger(byte v) => (v / 255.0).ToString("0.###", System.Globalization.CultureInfo.InvariantCulture);
			return $"{{\"c\":1,\"b\":{bits},\"a\":[{Axis(s.ThumbLX)},{Axis(-s.ThumbLY)},{Axis(s.ThumbRX)},{Axis(-s.ThumbRY)}],\"t\":[{Trigger(s.LeftTrigger)},{Trigger(s.RightTrigger)}]}}";
		}
		return "{\"c\":0}";
	}

	[StructLayout(LayoutKind.Sequential)]
	struct State
	{
		public uint PacketNumber;
		public ushort Buttons;
		public byte LeftTrigger;
		public byte RightTrigger;
		public short ThumbLX;
		public short ThumbLY;
		public short ThumbRX;
		public short ThumbRY;
	}

	[DllImport("xinput1_4.dll")]
	static extern int XInputGetState(int userIndex, out State state);
}
