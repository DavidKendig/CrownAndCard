// SPDX-License-Identifier: AGPL-3.0-or-later
//
// A tiny DLL around stb_vorbis (v1.22, MIT or public domain; see stb_vorbis.c
// and stb_vorbis.commit) so the launcher can play the Ogg Vorbis menu loop.
// Built by launcher/build.ps1 and embedded in the launcher exe.

#define STB_VORBIS_NO_STDIO          // decode from memory only
#define STB_VORBIS_NO_PUSHDATA_API
#include "stb_vorbis.c"

#ifdef _WIN32
#define CCV_EXPORT __declspec(dllexport)
#else
#define CCV_EXPORT __attribute__((visibility("default")))
#endif

// Opens Ogg Vorbis data held in memory. The data must stay alive until ccv_close.
// Returns NULL if the data isn't valid Ogg Vorbis.
CCV_EXPORT void *ccv_open(const unsigned char *data, int length, int *channels, int *sampleRate)
{
    int error = 0;
    stb_vorbis *v = stb_vorbis_open_memory(data, length, &error, NULL);
    if (v == NULL)
        return NULL;
    stb_vorbis_info info = stb_vorbis_get_info(v);
    *channels = info.channels;
    *sampleRate = (int)info.sample_rate;
    return v;
}

// Decodes up to `shortCount` interleaved 16-bit samples. Returns frames (samples
// per channel) written; 0 means the end of the stream.
CCV_EXPORT int ccv_read(void *v, int channels, short *buffer, int shortCount)
{
    return stb_vorbis_get_samples_short_interleaved((stb_vorbis *)v, channels, buffer, shortCount);
}

// Jumps back to the first sample, for seamless looping. Returns 1 on success.
CCV_EXPORT int ccv_rewind(void *v)
{
    return stb_vorbis_seek_start((stb_vorbis *)v);
}

CCV_EXPORT void ccv_close(void *v)
{
    stb_vorbis_close((stb_vorbis *)v);
}
