// SPDX-License-Identifier: AGPL-3.0-or-later
using System;
using System.IO;
using System.Runtime.InteropServices;
using System.Threading;

namespace CrownAndCard.Launcher;

/**
	The Mac build's menu music, with the same API as ../src/MusicPlayer.cs.

	- The music is `menu-loop-dark.ogg` in the app's Resources/music (in a dev
	  checkout, `res/audio/music/`).
	- Decoding: the same stb_vorbis wrapper (../native/cc_vorbis.c), built as
	  libcc_vorbis.dylib next to the launcher.
	- Output: a CoreAudio AudioQueue, which calls back for each buffer on its own thread.
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

	readonly NativeVorbis.OggStream ogg;
	readonly int channels, framesPerBuffer;
	readonly short[] pcm;
	readonly float fadeStep;
	float gain;
	GCHandle self;
	IntPtr queue;
	volatile bool running = true;

	/** Held while filling a buffer, so the decoder isn't closed under the audio thread. **/
	readonly object gate = new();

	unsafe MusicPlayer(float volume, bool playing)
	{
		Volume = volume;
		Playing = playing;
		ogg = new NativeVorbis.OggStream(ReadMusic());
		channels = ogg.Channels;
		int rate = ogg.SampleRate;
		framesPerBuffer = rate * BufferMilliseconds / 1000;
		pcm = new short[framesPerBuffer * channels];
		fadeStep = 1f / (rate * FadeSeconds);

		var format = new AudioQueue.StreamDescription
		{
			SampleRate = rate,
			FormatID = AudioQueue.FormatLinearPCM,
			FormatFlags = AudioQueue.FlagIsSignedInteger | AudioQueue.FlagIsPacked,
			BytesPerPacket = (uint)(channels * 2),
			FramesPerPacket = 1,
			BytesPerFrame = (uint)(channels * 2),
			ChannelsPerFrame = (uint)channels,
			BitsPerChannel = 16,
		};
		self = GCHandle.Alloc(this);
		try
		{
			AudioQueue.Check(AudioQueue.AudioQueueNewOutput(ref format, &OnBufferDone, GCHandle.ToIntPtr(self), IntPtr.Zero, IntPtr.Zero, 0, out queue), "AudioQueueNewOutput");
			for (int i = 0; i < BufferCount; i++)
			{
				AudioQueue.Check(AudioQueue.AudioQueueAllocateBuffer(queue, (uint)(pcm.Length * 2), out var buffer), "AudioQueueAllocateBuffer");
				Fill(buffer);
			}
			AudioQueue.Check(AudioQueue.AudioQueueStart(queue, IntPtr.Zero), "AudioQueueStart");
		}
		catch
		{
			Release();
			throw;
		}
	}

	/** Starts the music, or returns null (and logs why) if this Mac can't play it. **/
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

	[UnmanagedCallersOnly]
	static void OnBufferDone(IntPtr user, IntPtr queue, IntPtr buffer)
	{
		if (GCHandle.FromIntPtr(user).Target is not MusicPlayer player)
			return;
		try
		{
			lock (player.gate)
				if (player.running)
					player.Fill(buffer);
		}
		catch (Exception e)
		{
			player.Error = e.Message;
			player.running = false;
			Log.Write("Menu music stopped: " + e.Message);
		}
	}

	/** Decodes (or silences) the next stretch into `buffer` and queues it. **/
	void Fill(IntPtr buffer)
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
		var data = Marshal.ReadIntPtr(buffer, AudioQueue.BufferDataOffset);
		Marshal.Copy(pcm, 0, data, pcm.Length);
		Marshal.WriteInt32(buffer, AudioQueue.BufferByteSizeOffset, pcm.Length * 2);
		AudioQueue.Check(AudioQueue.AudioQueueEnqueueBuffer(queue, buffer, 0, IntPtr.Zero), "AudioQueueEnqueueBuffer");
	}

	/** The menu loop: in the app's Resources/music, next to the launcher, or the repo's res/audio/music/ in a dev checkout. **/
	static byte[] ReadMusic()
	{
		foreach (var installed in new[]
		{
			Path.Combine(Paths.ExeDir, "..", "Resources", "music", MusicFile),
			Path.Combine(Paths.ExeDir, "music", MusicFile),
		})
			if (File.Exists(installed))
				return File.ReadAllBytes(installed);
		for (var d = new DirectoryInfo(Paths.ExeDir); d != null; d = d.Parent)
		{
			var dev = Path.Combine(d.FullName, "res", "audio", "music", MusicFile);
			if (File.Exists(dev))
				return File.ReadAllBytes(dev);
		}
		throw new FileNotFoundException("The menu music isn't installed (Resources/music/" + MusicFile + ")");
	}

	void Release()
	{
		running = false;
		if (queue != IntPtr.Zero)
		{
			AudioQueue.AudioQueueStop(queue, true);
			AudioQueue.AudioQueueDispose(queue, true);
			queue = IntPtr.Zero;
		}
		lock (gate)
		{
			if (self.IsAllocated)
				self.Free();
			ogg.Dispose();
		}
	}

	int disposed;

	public void Dispose()
	{
		if (Interlocked.Exchange(ref disposed, 1) == 0)
			Release();
	}

	/** Wraps the four functions of libcc_vorbis.dylib (stb_vorbis), which sits next to the launcher. **/
	static class NativeVorbis
	{
		const string Lib = "cc_vorbis";

		[DllImport(Lib, CallingConvention = CallingConvention.Cdecl)]
		static extern IntPtr ccv_open(IntPtr data, int length, out int channels, out int sampleRate);

		[DllImport(Lib, CallingConvention = CallingConvention.Cdecl)]
		static extern int ccv_read(IntPtr v, int channels, IntPtr buffer, int shortCount);

		[DllImport(Lib, CallingConvention = CallingConvention.Cdecl)]
		static extern int ccv_rewind(IntPtr v);

		[DllImport(Lib, CallingConvention = CallingConvention.Cdecl)]
		static extern void ccv_close(IntPtr v);

		/** Fails early with a clear message instead of a DllNotFoundException on the audio thread. **/
		public static void EnsureAvailable()
		{
			if (!File.Exists(Path.Combine(Paths.ExeDir, "libcc_vorbis.dylib")))
				throw new FileNotFoundException("libcc_vorbis.dylib isn't next to the launcher");
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

	/** The parts of CoreAudio's AudioQueue API the player needs. **/
	static unsafe class AudioQueue
	{
		const string Lib = "/System/Library/Frameworks/AudioToolbox.framework/AudioToolbox";

		public const uint FormatLinearPCM = 0x6C70636D; // 'lpcm'
		public const uint FlagIsSignedInteger = 0x4;
		public const uint FlagIsPacked = 0x8;

		// AudioQueueBuffer: UInt32 capacity; (pad) void *mAudioData; UInt32 mAudioDataByteSize; ...
		public const int BufferDataOffset = 8;
		public const int BufferByteSizeOffset = 16;

		[StructLayout(LayoutKind.Sequential)]
		public struct StreamDescription
		{
			public double SampleRate;
			public uint FormatID;
			public uint FormatFlags;
			public uint BytesPerPacket;
			public uint FramesPerPacket;
			public uint BytesPerFrame;
			public uint ChannelsPerFrame;
			public uint BitsPerChannel;
			public uint Reserved;
		}

		[DllImport(Lib)]
		public static extern int AudioQueueNewOutput(ref StreamDescription format, delegate* unmanaged<IntPtr, IntPtr, IntPtr, void> callback,
			IntPtr userData, IntPtr runLoop, IntPtr runLoopMode, uint flags, out IntPtr queue);

		[DllImport(Lib)]
		public static extern int AudioQueueAllocateBuffer(IntPtr queue, uint byteSize, out IntPtr buffer);

		[DllImport(Lib)]
		public static extern int AudioQueueEnqueueBuffer(IntPtr queue, IntPtr buffer, uint packetDescriptionCount, IntPtr packetDescriptions);

		[DllImport(Lib)]
		public static extern int AudioQueueStart(IntPtr queue, IntPtr startTime);

		[DllImport(Lib)]
		public static extern int AudioQueueStop(IntPtr queue, [MarshalAs(UnmanagedType.I1)] bool immediate);

		[DllImport(Lib)]
		public static extern int AudioQueueDispose(IntPtr queue, [MarshalAs(UnmanagedType.I1)] bool immediate);

		public static void Check(int status, string call)
		{
			if (status != 0)
				throw new InvalidOperationException($"{call} failed (OSStatus {status}); is an audio device available?");
		}
	}
}
