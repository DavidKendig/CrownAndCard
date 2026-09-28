// SPDX-License-Identifier: AGPL-3.0-or-later
using System;
using System.IO;
using System.Runtime.InteropServices;
using System.Threading;

namespace CrownAndCard.Launcher;

/**
	Plays the menu loop on repeat, seamlessly.

	- The music is `music\menu-loop-dark.ogg` next to the launcher (in a dev
	  checkout, `res\audio\music\menu-loop-dark.ogg`).
	- Decoding: stb_vorbis, built into `cc_vorbis.dll`, which ships next to the
	  launcher and loads the ordinary way. Nothing is unpacked or loaded from
	  elsewhere: that pattern looks like malware to behavior-based antivirus.
	- Output: the Windows waveOut API, streamed from a background thread.
	- Fades in and out when `Playing` changes; `Volume` follows the audio settings.
**/
sealed class MusicPlayer : IDisposable
{
	const string MusicFile = "menu-loop-dark.ogg";
	const int BufferMilliseconds = 100;
	const int BufferCount = 4;
	const float FadeSeconds = 0.8f;

	/** Target loudness, 0–1 (linear amplitude). **/
	public float Volume { get; set; }

	/** When false the music fades out and the stream pauses where it is. **/
	public bool Playing { get; set; }

	/** Why playback stopped, if it failed after starting (for example, no audio device). **/
	public string? Error { get; private set; }

	readonly Thread thread;
	volatile bool running = true;

	MusicPlayer(float volume, bool playing)
	{
		Volume = volume;
		Playing = playing;
		thread = new Thread(Run) { IsBackground = true, Name = "MenuMusic", Priority = ThreadPriority.AboveNormal };
		thread.Start();
	}

	/** Starts the music, or returns null (and logs why) if this PC can't play it. **/
	public static MusicPlayer? TryStart(float volume, bool playing)
	{
		try
		{
			NativeVorbis.EnsureAvailable();
			return new MusicPlayer(volume, playing);
		}
		catch (Exception e)
		{
			Log.Write("Menu music unavailable: " + e.Message);
			return null;
		}
	}

	/** Decodes the whole loop once (for `--check-audio`). Returns frames, channels and rate. **/
	public static (long Frames, int Channels, int Rate) DecodeAll()
	{
		NativeVorbis.EnsureAvailable();
		using var ogg = new NativeVorbis.OggStream(ReadMusic());
		var buffer = new short[4096 * ogg.Channels];
		long frames = 0;
		int n;
		while ((n = ogg.Read(buffer, 0, buffer.Length)) > 0)
			frames += n;
		return (frames, ogg.Channels, ogg.SampleRate);
	}

	void Run()
	{
		try
		{
			StreamMusic();
		}
		catch (Exception e)
		{
			Error = e.Message;
			Log.Write("Menu music stopped: " + e.Message);
		}
	}

	void StreamMusic()
	{
		using var ogg = new NativeVorbis.OggStream(ReadMusic());
		int channels = ogg.Channels, rate = ogg.SampleRate;
		int framesPerBuffer = rate * BufferMilliseconds / 1000;
		int bytesPerBuffer = framesPerBuffer * channels * 2;
		var pcm = new short[framesPerBuffer * channels];
		float gain = 0;
		float fadeStep = 1f / (rate * FadeSeconds);

		var format = new WaveOut.Format
		{
			FormatTag = 1, // PCM
			Channels = (short)channels,
			SamplesPerSec = rate,
			AvgBytesPerSec = rate * channels * 2,
			BlockAlign = (short)(channels * 2),
			BitsPerSample = 16,
		};
		using var done = new AutoResetEvent(false);
		WaveOut.Check(WaveOut.waveOutOpen(out var device, new IntPtr(-1), ref format, done.SafeWaitHandle.DangerousGetHandle(), IntPtr.Zero, WaveOut.CALLBACK_EVENT), "waveOutOpen");
		var headers = new IntPtr[BufferCount];
		try
		{
			for (int i = 0; i < BufferCount; i++)
			{
				var header = new WaveOut.Header { Data = Marshal.AllocHGlobal(bytesPerBuffer), BufferLength = bytesPerBuffer };
				headers[i] = Marshal.AllocHGlobal(Marshal.SizeOf<WaveOut.Header>());
				Marshal.StructureToPtr(header, headers[i], false);
				WaveOut.Check(WaveOut.waveOutPrepareHeader(device, headers[i], Marshal.SizeOf<WaveOut.Header>()), "waveOutPrepareHeader");
				Fill(headers[i]);
				WaveOut.Check(WaveOut.waveOutWrite(device, headers[i], Marshal.SizeOf<WaveOut.Header>()), "waveOutWrite");
			}
			while (running)
			{
				done.WaitOne(BufferMilliseconds);
				foreach (var h in headers)
				{
					var flags = Marshal.ReadInt32(h, WaveOut.FlagsOffset);
					if ((flags & WaveOut.WHDR_DONE) == 0)
						continue;
					Marshal.WriteInt32(h, WaveOut.FlagsOffset, flags & ~WaveOut.WHDR_DONE);
					Fill(h);
					WaveOut.Check(WaveOut.waveOutWrite(device, h, Marshal.SizeOf<WaveOut.Header>()), "waveOutWrite");
				}
			}
		}
		finally
		{
			WaveOut.waveOutReset(device);
			foreach (var h in headers)
			{
				if (h == IntPtr.Zero)
					continue;
				WaveOut.waveOutUnprepareHeader(device, h, Marshal.SizeOf<WaveOut.Header>());
				Marshal.FreeHGlobal(Marshal.PtrToStructure<WaveOut.Header>(h).Data);
				Marshal.FreeHGlobal(h);
			}
			WaveOut.waveOutClose(device);
		}

		void Fill(IntPtr headerPtr)
		{
			float target = Playing ? Math.Max(0, Math.Min(1, Volume)) : 0;
			if (gain == 0 && target == 0)
			{
				// Faded out: send silence and keep the song where it was.
				Array.Clear(pcm, 0, pcm.Length);
			}
			else
			{
				int got = 0, emptyReads = 0;
				while (got < framesPerBuffer)
				{
					int n = ogg.Read(pcm, got * channels, (framesPerBuffer - got) * channels);
					if (n > 0)
					{
						got += n;
						emptyReads = 0;
						continue;
					}
					if (++emptyReads > 1 || !ogg.Rewind()) // end of the loop: start over
					{
						Array.Clear(pcm, got * channels, (framesPerBuffer - got) * channels);
						break;
					}
				}
				for (int f = 0; f < framesPerBuffer; f++)
				{
					if (gain < target) gain = Math.Min(target, gain + fadeStep);
					else if (gain > target) gain = Math.Max(target, gain - fadeStep);
					for (int c = 0; c < channels; c++)
						pcm[f * channels + c] = (short)(pcm[f * channels + c] * gain);
				}
			}
			var data = Marshal.PtrToStructure<WaveOut.Header>(headerPtr).Data;
			Marshal.Copy(pcm, 0, data, pcm.Length);
		}
	}

	/** The menu loop: `music\` next to the launcher, or the repo's `res\audio\music\` in a dev checkout. **/
	static byte[] ReadMusic()
	{
		var installed = Path.Combine(Paths.ExeDir, "music", MusicFile);
		if (File.Exists(installed))
			return File.ReadAllBytes(installed);
		for (var d = new DirectoryInfo(Paths.ExeDir); d != null; d = d.Parent)
		{
			var dev = Path.Combine(d.FullName, "res", "audio", "music", MusicFile);
			if (File.Exists(dev))
				return File.ReadAllBytes(dev);
		}
		throw new FileNotFoundException("The menu music isn't installed (music\\" + MusicFile + ")");
	}

	public void Dispose()
	{
		running = false;
		thread.Join(1000);
	}

	/** Wraps the four functions of cc_vorbis.dll (stb_vorbis), which sits next to the launcher. **/
	static class NativeVorbis
	{
		const string Dll = "cc_vorbis.dll";

		[DllImport(Dll, CallingConvention = CallingConvention.Cdecl)]
		static extern IntPtr ccv_open(IntPtr data, int length, out int channels, out int sampleRate);

		[DllImport(Dll, CallingConvention = CallingConvention.Cdecl)]
		static extern int ccv_read(IntPtr v, int channels, IntPtr buffer, int shortCount);

		[DllImport(Dll, CallingConvention = CallingConvention.Cdecl)]
		static extern int ccv_rewind(IntPtr v);

		[DllImport(Dll, CallingConvention = CallingConvention.Cdecl)]
		static extern void ccv_close(IntPtr v);

		/** Fails early with a clear message instead of a DllNotFoundException on the audio thread. **/
		public static void EnsureAvailable()
		{
			if (IntPtr.Size != 8)
				throw new PlatformNotSupportedException("the music decoder is 64-bit only");
			if (!File.Exists(Path.Combine(Paths.ExeDir, Dll)))
				throw new FileNotFoundException(Dll + " isn't next to the launcher");
		}

		/** One open Ogg Vorbis stream, decoding from a private copy of the file in unmanaged memory. **/
		public sealed class OggStream : IDisposable
		{
			readonly IntPtr data;
			readonly IntPtr handle;
			public int Channels { get; }
			public int SampleRate { get; }

			public OggStream(byte[] ogg)
			{
				data = Marshal.AllocHGlobal(ogg.Length);
				Marshal.Copy(ogg, 0, data, ogg.Length);
				handle = ccv_open(data, ogg.Length, out var channels, out var rate);
				if (handle == IntPtr.Zero)
				{
					Marshal.FreeHGlobal(data);
					throw new InvalidDataException("The menu loop isn't valid Ogg Vorbis");
				}
				Channels = channels;
				SampleRate = rate;
			}

			/** Decodes into `buffer` from `offset` (in samples). Returns frames decoded; 0 at the end. **/
			public int Read(short[] buffer, int offset, int count)
			{
				var pin = GCHandle.Alloc(buffer, GCHandleType.Pinned);
				try
				{
					return ccv_read(handle, Channels, pin.AddrOfPinnedObject() + offset * 2, count);
				}
				finally
				{
					pin.Free();
				}
			}

			public bool Rewind() => ccv_rewind(handle) != 0;

			public void Dispose()
			{
				ccv_close(handle);
				Marshal.FreeHGlobal(data);
			}
		}
	}

	/** The parts of the Windows waveOut API the player needs. **/
	static class WaveOut
	{
		public const int CALLBACK_EVENT = 0x00050000;
		public const int WHDR_DONE = 0x1;
		public static readonly int FlagsOffset = (int)Marshal.OffsetOf<Header>(nameof(Header.Flags));

		[StructLayout(LayoutKind.Sequential, Pack = 2)]
		public struct Format
		{
			public short FormatTag;
			public short Channels;
			public int SamplesPerSec;
			public int AvgBytesPerSec;
			public short BlockAlign;
			public short BitsPerSample;
			public short Size;
		}

		[StructLayout(LayoutKind.Sequential)]
		public struct Header
		{
			public IntPtr Data;
			public int BufferLength;
			public int BytesRecorded;
			public IntPtr User;
			public int Flags;
			public int Loops;
			public IntPtr Next;
			public IntPtr Reserved;
		}

		[DllImport("winmm.dll")]
		public static extern int waveOutOpen(out IntPtr device, IntPtr deviceId, ref Format format, IntPtr callback, IntPtr instance, int flags);

		[DllImport("winmm.dll")]
		public static extern int waveOutPrepareHeader(IntPtr device, IntPtr header, int size);

		[DllImport("winmm.dll")]
		public static extern int waveOutUnprepareHeader(IntPtr device, IntPtr header, int size);

		[DllImport("winmm.dll")]
		public static extern int waveOutWrite(IntPtr device, IntPtr header, int size);

		[DllImport("winmm.dll")]
		public static extern int waveOutReset(IntPtr device);

		[DllImport("winmm.dll")]
		public static extern int waveOutClose(IntPtr device);

		public static void Check(int result, string call)
		{
			if (result != 0)
				throw new InvalidOperationException($"{call} failed (MMRESULT {result}); is an audio device available?");
		}
	}
}
