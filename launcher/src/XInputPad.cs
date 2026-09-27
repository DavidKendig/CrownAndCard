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
