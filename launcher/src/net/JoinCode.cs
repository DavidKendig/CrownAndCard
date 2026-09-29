// SPDX-License-Identifier: AGPL-3.0-or-later
using System;
using System.Net;
using System.Net.Sockets;
using System.Text;

namespace CrownAndCard.Launcher;

/**
	The code a host shares so friends can join (GAME_DESIGN.md §13.13): the
	host's IPv4 address, its port and a random session key, 10 bytes written
	as 16 Crockford base32 characters in groups of four (XXXX-XXXX-XXXX-XXXX).
	Reading is forgiving: case, spaces and dashes don't matter, and O/I/L read
	as 0/1/1.
**/
static class JoinCode
{
	const string Alphabet = "0123456789ABCDEFGHJKMNPQRSTVWXYZ";

	public static string Encode(IPAddress address, int port, uint key)
	{
		if (address.AddressFamily != AddressFamily.InterNetwork)
			throw new ArgumentException("Join codes carry IPv4 addresses");
		var bytes = new byte[10];
		Array.Copy(address.GetAddressBytes(), bytes, 4);
		bytes[4] = (byte)(port >> 8);
		bytes[5] = (byte)port;
		bytes[6] = (byte)(key >> 24);
		bytes[7] = (byte)(key >> 16);
		bytes[8] = (byte)(key >> 8);
		bytes[9] = (byte)key;
		var sb = new StringBuilder(19);
		int buffer = 0, bits = 0;
		foreach (var b in bytes)
		{
			buffer = (buffer << 8) | b;
			bits += 8;
			while (bits >= 5)
			{
				bits -= 5;
				if (sb.Length is 4 or 9 or 14)
					sb.Append('-');
				sb.Append(Alphabet[(buffer >> bits) & 31]);
			}
		}
		return sb.ToString();
	}

	public static bool TryDecode(string? code, out IPEndPoint endpoint, out uint key)
	{
		endpoint = new IPEndPoint(IPAddress.Any, 0);
		key = 0;
		if (code == null)
			return false;
		var bytes = new byte[10];
		int buffer = 0, bits = 0, count = 0, chars = 0;
		foreach (var raw in code.ToUpperInvariant())
		{
			if (raw is '-' or ' ')
				continue;
			var c = raw switch { 'O' => '0', 'I' or 'L' => '1', _ => raw };
			int v = Alphabet.IndexOf(c);
			if (v < 0 || ++chars > 16)
				return false;
			buffer = (buffer << 5) | v;
			bits += 5;
			if (bits >= 8)
			{
				bits -= 8;
				bytes[count++] = (byte)(buffer >> bits);
			}
		}
		if (chars != 16)
			return false;
		int port = (bytes[4] << 8) | bytes[5];
		if (port == 0)
			return false;
		endpoint = new IPEndPoint(new IPAddress([bytes[0], bytes[1], bytes[2], bytes[3]]), port);
		key = ((uint)bytes[6] << 24) | ((uint)bytes[7] << 16) | ((uint)bytes[8] << 8) | bytes[9];
		return true;
	}
}
