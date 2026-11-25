// A small streaming GIF encoder: one frame in memory at a time, so it is safe inside a share extension.
//
// Each frame gets its own palette (median cut over a 15-bit histogram). From the second frame on, a pixel is
// only drawn again when it has moved more than `tolerance` away from what was last drawn there; everything else
// is written as "see-through", which the LZW stage squeezes to almost nothing. That is what keeps clips that
// came from video (where every pixel flickers a little) to a sensible size.
#ifndef GSGifWriter_h
#define GSGifWriter_h

#include <stddef.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef struct GSGifWriter GSGifWriter;

// tolerance: 0-255 per channel. dither: 0 = flat colours, 1 = error diffusion (smoother gradients, larger file).
// Returns NULL when the file cannot be created or the size is not one a GIF can have.
GSGifWriter *GSGifWriterOpen(const char *path, int width, int height, int tolerance, int dither);

// pixels: width x height, 4 bytes each in memory order B, G, R, X. Returns 0 on success.
int GSGifWriterAddFrame(GSGifWriter *writer, const uint8_t *bgra, size_t bytesPerRow, int delayCentiseconds);

// Finishes the file and frees the writer. Returns 0 when everything was written.
int GSGifWriterClose(GSGifWriter *writer);

long long GSGifWriterBytesWritten(const GSGifWriter *writer);

#ifdef __cplusplus
}
#endif

#endif
