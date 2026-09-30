// SPDX-License-Identifier: AGPL-3.0-or-later
using System;
using System.Diagnostics;
using System.IO;
using System.Runtime.InteropServices;

namespace CrownAndCard.Launcher;

/** Small Mac-only helpers the shared code and the Mac UI use. **/
static class MacPlatform
{
	/** The main display's size in points ("1512x982"), for session reports. Set by the UI once a window is up. **/
	public static string PrimaryScreen { get; set; } = "unknown";

	/** Shows a folder in Finder. **/
	public static void OpenFolder(string? dir)
	{
		if (dir == null || !Directory.Exists(dir))
			return;
		Open(dir);
	}

	/** Opens a file, folder or URL the way Finder would (`open`). **/
	public static void Open(string target)
	{
		try
		{
			var psi = new ProcessStartInfo("/usr/bin/open") { UseShellExecute = false };
			psi.ArgumentList.Add(target);
			Process.Start(psi);
		}
		catch (Exception e)
		{
			Log.Write($"Couldn't open {target}: {e.Message}");
		}
	}
}

/** The few Objective-C runtime calls the Mac build needs (GameController for the controller). **/
static class ObjC
{
	const string Lib = "/usr/lib/libobjc.A.dylib";

	[DllImport(Lib)]
	public static extern IntPtr objc_getClass(string name);

	[DllImport(Lib)]
	public static extern IntPtr sel_registerName(string name);

	[DllImport(Lib)]
	public static extern IntPtr objc_autoreleasePoolPush();

	[DllImport(Lib)]
	public static extern void objc_autoreleasePoolPop(IntPtr pool);

	[DllImport(Lib, EntryPoint = "objc_msgSend")]
	public static extern IntPtr Send(IntPtr receiver, IntPtr selector);

	[DllImport(Lib, EntryPoint = "objc_msgSend")]
	public static extern IntPtr Send(IntPtr receiver, IntPtr selector, nuint arg);

	[DllImport(Lib, EntryPoint = "objc_msgSend")]
	public static extern IntPtr Send(IntPtr receiver, IntPtr selector, IntPtr arg);

	[DllImport(Lib, EntryPoint = "objc_msgSend")]
	public static extern void SendBool(IntPtr receiver, IntPtr selector, [MarshalAs(UnmanagedType.I1)] bool arg);

	[DllImport(Lib, EntryPoint = "objc_msgSend")]
	[return: MarshalAs(UnmanagedType.I1)]
	public static extern bool SendReturnsBool(IntPtr receiver, IntPtr selector);

	[DllImport(Lib, EntryPoint = "objc_msgSend")]
	[return: MarshalAs(UnmanagedType.I1)]
	public static extern bool SendReturnsBool(IntPtr receiver, IntPtr selector, IntPtr arg);

	[DllImport(Lib, EntryPoint = "objc_msgSend")]
	public static extern float SendReturnsFloat(IntPtr receiver, IntPtr selector);

	/** Sends a message with no arguments, by selector name. **/
	public static IntPtr Get(IntPtr receiver, string selector) =>
		receiver == IntPtr.Zero ? IntPtr.Zero : Send(receiver, sel_registerName(selector));

	public static bool Responds(IntPtr receiver, string selector) =>
		receiver != IntPtr.Zero && SendReturnsBool(receiver, sel_registerName("respondsToSelector:"), sel_registerName(selector));
}
