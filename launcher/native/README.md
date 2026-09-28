# Native decoder for the launcher's menu music

| File | License | Notes |
|---|---|---|
| `stb_vorbis.c` | **Third party:** MIT or public domain (Unlicense), your choice; see the end of the file | stb_vorbis v1.22 by Sean Barrett and contributors, from https://github.com/nothings/stb at the commit in `stb_vorbis.commit`. Unmodified. |
| `cc_vorbis.c` | AGPL-3.0-or-later (this project) | A four-function DLL wrapper (`ccv_open`, `ccv_read`, `ccv_rewind`, `ccv_close`) used by `src/MusicPlayer.cs`. |

`build.ps1` compiles these with MSVC into a 64-bit `cc_vorbis.dll` (static C runtime, so it needs no redistributable) and copies it next to the launcher exe, where it ships as an ordinary file. It used to be embedded in the exe and unpacked at run time, but behavior-based antivirus flags that pattern.

NVorbis was considered instead, as a pure C# decoder. The releases that run on .NET Framework 4.8 without extra DLLs (0.9.x) are under the Microsoft Public License, which isn't compatible with the AGPL, and the MIT-licensed releases (0.10+) need `System.Memory`.
