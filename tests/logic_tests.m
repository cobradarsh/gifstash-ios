// Tests for the parts that do not need an iPhone: links, the feed, the GIF encoder and the video-to-GIF step.
// Runs on the build machine (macOS).   logic_tests [--live] [output folder]
#import <AVFoundation/AVFoundation.h>
#import <CoreGraphics/CoreGraphics.h>
#import <Foundation/Foundation.h>
#import <ImageIO/ImageIO.h>
#import "GSCommon.h"
#import "GSGifMaker.h"
#import "GSGifWriter.h"
#import "GSImporter.h"
#import "GSStore.h"
#import "GSTweet.h"

static int gFailures = 0;
static int gChecks = 0;

#define CHECK(condition, ...) do { \
    gChecks++; \
    if (!(condition)) { gFailures++; printf("  FAIL %s:%d  %s  -- %s\n", __FILE__, __LINE__, #condition, [[NSString stringWithFormat:__VA_ARGS__] UTF8String]); } \
} while (0)

#pragma mark - Links

static void TestLinks(void) {
    printf("== links\n");
    NSArray<NSArray *> *cases = @[
        @[@"https://x.com/someone/status/1577855540407197696", @"1577855540407197696", @0],
        @[@"https://twitter.com/someone/status/1577855540407197696?s=20&t=abc", @"1577855540407197696", @0],
        @[@"Look at this https://x.com/a_b/status/1993111222333444555/video/2 lol", @"1993111222333444555", @2],
        @[@"https://mobile.twitter.com/i/web/status/1349129669258448897", @"1349129669258448897", @0],
        @[@"https://x.com/i/status/1349129669258448897", @"1349129669258448897", @0],
        @[@"x.com/user/status/1349129669258448897/photo/1", @"1349129669258448897", @1],
        @[@"https://fxtwitter.com/user/status/1349129669258448897", @"1349129669258448897", @0],
        @[@"https://vxtwitter.com/user/statuses/1349129669258448897.", @"1349129669258448897", @0],
    ];
    for (NSArray *c in cases) {
        GSLink *link = [GSTweet linkInText:c[0]];
        CHECK([link.tweetID isEqualToString:c[1]], @"%@ -> %@", c[0], link.tweetID);
        CHECK(link.mediaPosition == [c[2] integerValue], @"%@ -> position %ld", c[0], (long)link.mediaPosition);
    }
    for (NSString *text in @[@"https://dropbox.com/user/status/1349129669258448897", @"https://example.com/x.com/status",
                             @"hello", @"", @"https://x.com/someone", @"https://notx.com/a/status/1349129669258448897"]) {
        GSLink *link = [GSTweet linkInText:text];
        CHECK(link.tweetID == nil, @"%@ -> %@", text, link.tweetID);
    }
    GSLink *direct = [GSTweet linkInText:@"https://video.twimg.com/tweet_video/FeWabc123.mp4"];
    CHECK([direct.directVideoURL.host isEqualToString:@"video.twimg.com"], @"direct %@", direct.directVideoURL);
    CHECK(direct.isUsable, @"direct usable");
    GSLink *withQuery = [GSTweet linkInText:@"see https://video.twimg.com/ext_tw_video/1/pu/vid/480x600/a.mp4?tag=12)"];
    CHECK([withQuery.directVideoURL.query isEqualToString:@"tag=12"], @"query %@", withQuery.directVideoURL);
    GSLink *shortLink = [GSTweet linkInText:@"Funny https://t.co/AbC123xyz"];
    CHECK([shortLink.shortURL.absoluteString isEqualToString:@"https://t.co/AbC123xyz"], @"short %@", shortLink.shortURL);
    CHECK(![GSTweet linkInText:@"no link here"].isUsable, @"nothing usable");

    for (NSString *tweetID in @[@"1577855540407197696", @"20", @"1993111222333444555"]) {
        NSString *token = [GSTweet embedTokenForID:tweetID];
        NSCharacterSet *allowed = [NSCharacterSet characterSetWithCharactersInString:@"123456789abcdefghijklmnopqrstuvwxyz"];
        CHECK(token.length >= 6 && [token stringByTrimmingCharactersInSet:allowed].length == 0, @"token of %@ = %@", tweetID, token);
        printf("  token %s = %s\n", tweetID.UTF8String, token.UTF8String);
    }
}

#pragma mark - The feed

static id JSON(NSString *text) {
    return [NSJSONSerialization JSONObjectWithData:[text dataUsingEncoding:NSUTF8StringEncoding] options:0 error:NULL];
}

static void TestFeed(void) {
    printf("== feed\n");
    NSError *error = nil;
    GSTweet *gif = [GSTweet tweetFromEmbedJSON:JSON(@"{\"__typename\":\"Tweet\",\"id_str\":\"111\",\"text\":\"so true https://t.co/abc\","
        @"\"user\":{\"screen_name\":\"catposter\"},\"mediaDetails\":[{\"type\":\"photo\",\"media_url_https\":\"https://pbs.twimg.com/media/a.jpg\"},"
        @"{\"type\":\"animated_gif\",\"media_url_https\":\"https://pbs.twimg.com/tweet_video_thumb/g.jpg\","
        @"\"original_info\":{\"width\":498,\"height\":280},"
        @"\"video_info\":{\"aspect_ratio\":[249,140],\"variants\":[{\"bitrate\":0,\"content_type\":\"video/mp4\",\"url\":\"https://video.twimg.com/tweet_video/g.mp4\"}]}}]}")
                                       tweetID:@"111" error:&error];
    CHECK(gif != nil, @"%@", error);
    CHECK(gif.media.count == 1, @"count %lu", (unsigned long)gif.media.count);
    CHECK([gif.media.firstObject.kind isEqualToString:@"gif"], @"kind %@", gif.media.firstObject.kind);
    CHECK(gif.media.firstObject.position == 2, @"position %ld", (long)gif.media.firstObject.position);
    CHECK(gif.media.firstObject.width == 498 && gif.media.firstObject.height == 280, @"size");
    CHECK([gif.media.firstObject.videoURL.absoluteString isEqualToString:@"https://video.twimg.com/tweet_video/g.mp4"], @"url");
    CHECK([gif.author isEqualToString:@"catposter"], @"author %@", gif.author);
    CHECK([gif.text isEqualToString:@"so true"], @"text '%@'", gif.text);

    GSTweet *video = [GSTweet tweetFromEmbedJSON:JSON(@"{\"id_str\":\"222\",\"text\":\"https://t.co/abc\",\"mediaDetails\":[{\"type\":\"video\","
        @"\"video_info\":{\"duration_millis\":30030,\"variants\":["
        @"{\"content_type\":\"application/x-mpegURL\",\"url\":\"https://video.twimg.com/v/pl/a.m3u8\"},"
        @"{\"bitrate\":632000,\"content_type\":\"video/mp4\",\"url\":\"https://video.twimg.com/v/vid/320x400/a.mp4?tag=12\"},"
        @"{\"bitrate\":2176000,\"content_type\":\"video/mp4\",\"url\":\"https://video.twimg.com/v/vid/720x900/c.mp4?tag=12\"},"
        @"{\"bitrate\":9000000,\"content_type\":\"video/mp4\",\"url\":\"https://video.twimg.com/v/vid/2160x2700/d.mp4?tag=12\"},"
        @"{\"bitrate\":950000,\"content_type\":\"video/mp4\",\"url\":\"https://video.twimg.com/v/vid/480x600/b.mp4?tag=12\"}]}}]}")
                                         tweetID:@"222" error:&error];
    CHECK(video.media.count == 1, @"%@", error);
    CHECK([video.media.firstObject.videoURL.absoluteString containsString:@"720x900"], @"picked %@", video.media.firstObject.videoURL);
    CHECK(video.media.firstObject.width == 720 && video.media.firstObject.height == 900, @"size from the link");
    CHECK(fabs(video.media.firstObject.duration - 30.03) < 0.001, @"duration");
    CHECK(video.text == nil, @"text '%@'", video.text);

    GSTweet *quoted = [GSTweet tweetFromEmbedJSON:JSON(@"{\"id_str\":\"333\",\"text\":\"this\",\"quoted_tweet\":{\"mediaDetails\":[{\"type\":\"animated_gif\","
        @"\"video_info\":{\"variants\":[{\"bitrate\":0,\"content_type\":\"video/mp4\",\"url\":\"https://video.twimg.com/tweet_video/q.mp4\"}]}}]}}")
                                          tweetID:@"333" error:&error];
    CHECK(quoted.media.count == 1, @"quoted %@", error);

    GSTweet *block = [GSTweet tweetFromEmbedJSON:JSON(@"{\"id_str\":\"444\",\"video\":{\"poster\":\"https://pbs.twimg.com/p.jpg\",\"durationMs\":5000,"
        @"\"variants\":[{\"type\":\"video/mp4\",\"src\":\"https://video.twimg.com/v/vid/320x400/a.mp4\"},"
        @"{\"type\":\"video/mp4\",\"src\":\"https://video.twimg.com/v/vid/480x600/b.mp4\"}]}}") tweetID:@"444" error:&error];
    CHECK([block.media.firstObject.videoURL.absoluteString containsString:@"480x600"], @"video block %@", block.media.firstObject.videoURL);

    error = nil;
    GSTweet *gone = [GSTweet tweetFromEmbedJSON:JSON(@"{\"__typename\":\"TweetTombstone\",\"tombstone\":{\"text\":{\"text\":\"Age-restricted adult content.\"}}}")
                                        tweetID:@"555" error:&error];
    CHECK(gone == nil && error.code == GSErrorRestricted, @"tombstone %@", error);
    error = nil;
    GSTweet *words = [GSTweet tweetFromEmbedJSON:JSON(@"{\"id_str\":\"666\",\"text\":\"only words\"}") tweetID:@"666" error:&error];
    CHECK(words == nil && error.code == GSErrorNoMedia, @"no media %@", error);
    error = nil;
    CHECK([GSTweet tweetFromEmbedJSON:JSON(@"{}") tweetID:@"777" error:&error] == nil && error != nil, @"empty answer");
}

#pragma mark - Pictures for the encoder

enum { kW = 200, kH = 150 };

/// A still, slightly noisy backdrop with a square that moves and changes colour.
static void DrawFrame(uint8_t *bgra, int width, int height, int index, int noise) {
    uint32_t seed = 12345u + (uint32_t)index * 977u;
    for (int y = 0; y < height; y++) {
        for (int x = 0; x < width; x++) {
            int r = 40 + x * 180 / width, g = 60 + y * 150 / height, b = 120 + (x + y) * 60 / (width + height);
            if (noise) {
                seed = seed * 1664525u + 1013904223u;
                const int n = (int)((seed >> 24) % (2 * noise + 1)) - noise;
                r += n; g += n; b -= n;
            }
            const int boxX = 10 + index * 9, boxY = 30 + index * 4;
            if (x >= boxX && x < boxX + 40 && y >= boxY && y < boxY + 40) {
                r = 250 - index * 12; g = 40 + index * 10; b = 60;
            }
            uint8_t *p = bgra + ((size_t)y * width + x) * 4;
            p[0] = (uint8_t)MAX(0, MIN(255, b));
            p[1] = (uint8_t)MAX(0, MIN(255, g));
            p[2] = (uint8_t)MAX(0, MIN(255, r));
            p[3] = 255;
        }
    }
}

typedef struct { size_t frames; double seconds; double meanError; int worstError; size_t width, height; BOOL ok; } GifReport;

/// Reads a GIF back with ImageIO, laying each frame over the ones before, and compares with what went in.
static GifReport ReadGIF(NSURL *url, void (^expected)(int index, uint8_t *bgra, int width, int height), int width, int height) {
    GifReport report = { 0 };
    CGImageSourceRef source = CGImageSourceCreateWithURL((__bridge CFURLRef)url, NULL);
    if (!source) return report;
    report.frames = CGImageSourceGetCount(source);
    CGColorSpaceRef space = CGColorSpaceCreateDeviceRGB();
    uint8_t *canvas = calloc((size_t)width * height, 4);
    uint8_t *want = calloc((size_t)width * height, 4);
    CGContextRef context = CGBitmapContextCreate(canvas, (size_t)width, (size_t)height, 8, (size_t)width * 4, space,
                                                 kCGImageAlphaPremultipliedFirst | kCGBitmapByteOrder32Little);
    double total = 0;
    size_t samples = 0;
    report.ok = YES;
    for (size_t i = 0; i < report.frames; i++) {
        NSDictionary *properties = CFBridgingRelease(CGImageSourceCopyPropertiesAtIndex(source, i, NULL));
        NSDictionary *gif = properties[(__bridge id)kCGImagePropertyGIFDictionary];
        NSNumber *delay = gif[(__bridge id)kCGImagePropertyGIFUnclampedDelayTime] ?: gif[(__bridge id)kCGImagePropertyGIFDelayTime];
        report.seconds += delay.doubleValue;
        CGImageRef image = CGImageSourceCreateImageAtIndex(source, i, NULL);
        if (!image) { report.ok = NO; break; }
        report.width = CGImageGetWidth(image);
        report.height = CGImageGetHeight(image);
        if (report.width != (size_t)width || report.height != (size_t)height) { report.ok = NO; CGImageRelease(image); break; }
        CGContextDrawImage(context, CGRectMake(0, 0, width, height), image);
        CGImageRelease(image);
        if (expected) {
            expected((int)i, want, width, height);
            for (size_t k = 0; k < (size_t)width * height * 4; k++) {
                if ((k & 3) == 3) continue;
                const int d = abs((int)canvas[k] - (int)want[k]);
                total += d;
                samples++;
                if (d > report.worstError) report.worstError = d;
            }
        }
    }
    report.meanError = samples ? total / samples : 0;
    CGContextRelease(context);
    CGColorSpaceRelease(space);
    free(canvas);
    free(want);
    CFRelease(source);
    return report;
}

static void TestWriter(NSURL *folder) {
    printf("== GIF encoder\n");
    const int frames = 14;
    uint8_t *buffer = malloc(kW * kH * 4);
    struct { const char *name; int tolerance, dither, noise; double meanLimit; } runs[] = {
        { "exact", 0, 0, 0, 6.0 },
        { "tolerant-noisy", 7, 0, 3, 9.0 },
        { "dither-noisy", 5, 1, 3, 12.0 },
    };
    for (int r = 0; r < 3; r++) {
        NSURL *url = [folder URLByAppendingPathComponent:[NSString stringWithFormat:@"writer-%s.gif", runs[r].name]];
        GSGifWriter *writer = GSGifWriterOpen(url.fileSystemRepresentation, kW, kH, runs[r].tolerance, runs[r].dither);
        CHECK(writer != NULL, @"open %s", runs[r].name);
        if (!writer) continue;
        for (int i = 0; i < frames; i++) {
            DrawFrame(buffer, kW, kH, i, runs[r].noise);
            CHECK(GSGifWriterAddFrame(writer, buffer, kW * 4, 5 + (i % 3)) == 0, @"frame %d", i);
        }
        // Two frames with nothing new in them, then the first one again.
        CHECK(GSGifWriterAddFrame(writer, buffer, kW * 4, 9) == 0, @"same frame");
        const long long before = GSGifWriterBytesWritten(writer);
        CHECK(GSGifWriterAddFrame(writer, buffer, kW * 4, 9) == 0, @"same frame again");
        const long long stillFrame = GSGifWriterBytesWritten(writer) - before;
        CHECK(stillFrame < 64, @"a frame with nothing new takes %lld bytes", stillFrame);
        CHECK(GSGifWriterClose(writer) == 0, @"close");

        const int noise = runs[r].noise;
        GifReport report = ReadGIF(url, ^(int index, uint8_t *bgra, int width, int height) {
            DrawFrame(bgra, width, height, MIN(index, frames - 1), noise);
        }, kW, kH);
        NSNumber *size = nil;
        [url getResourceValue:&size forKey:NSURLFileSizeKey error:NULL];
        printf("  %-15s %zu frames, %.2f s, %lld bytes, mean error %.2f, worst %d\n", runs[r].name, report.frames, report.seconds,
               size.longLongValue, report.meanError, report.worstError);
        CHECK(report.ok, @"readable at the right size (%zu x %zu)", report.width, report.height);
        CHECK(report.frames == (size_t)frames + 2, @"frames %zu", report.frames);
        double seconds = 0.18;
        for (int i = 0; i < frames; i++) seconds += (5 + (i % 3)) / 100.0;
        CHECK(fabs(report.seconds - seconds) < 0.001, @"seconds %.3f, expected %.3f", report.seconds, seconds);
        CHECK(report.meanError < runs[r].meanLimit, @"mean error %.2f", report.meanError);
    }

    // Few colours: small palettes and short codes.
    NSURL *flat = [folder URLByAppendingPathComponent:@"writer-flat.gif"];
    GSGifWriter *writer = GSGifWriterOpen(flat.fileSystemRepresentation, 64, 48, 0, 0);
    uint8_t *small = malloc(64 * 48 * 4);
    for (int i = 0; i < 4; i++) {
        for (int k = 0; k < 64 * 48; k++) {
            const int on = ((k % 64) / 8 + (k / 64) / 8 + i) % (i + 1) == 0;
            small[k * 4] = on ? 255 : 0; small[k * 4 + 1] = on ? 255 : 0; small[k * 4 + 2] = on ? 255 : 0; small[k * 4 + 3] = 255;
        }
        CHECK(GSGifWriterAddFrame(writer, small, 64 * 4, 10) == 0, @"flat frame %d", i);
    }
    CHECK(GSGifWriterClose(writer) == 0, @"close flat");
    GifReport flatReport = ReadGIF(flat, ^(int index, uint8_t *bgra, int width, int height) {
        for (int k = 0; k < width * height; k++) {
            const int on = ((k % width) / 8 + (k / width) / 8 + index) % (index + 1) == 0;
            bgra[k * 4] = on ? 255 : 0; bgra[k * 4 + 1] = on ? 255 : 0; bgra[k * 4 + 2] = on ? 255 : 0; bgra[k * 4 + 3] = 255;
        }
    }, 64, 48);
    CHECK(flatReport.ok && flatReport.frames == 4 && flatReport.worstError == 0, @"flat: %zu frames, worst %d", flatReport.frames, flatReport.worstError);

    // A large busy picture, so that the code table fills and restarts many times.
    const int bigW = 640, bigH = 480;
    uint8_t *big = malloc((size_t)bigW * bigH * 4);
    NSURL *busy = [folder URLByAppendingPathComponent:@"writer-busy.gif"];
    writer = GSGifWriterOpen(busy.fileSystemRepresentation, bigW, bigH, 0, 0);
    for (int i = 0; i < 3; i++) {
        DrawFrame(big, bigW, bigH, i, 40);
        CHECK(GSGifWriterAddFrame(writer, big, (size_t)bigW * 4, 4) == 0, @"busy frame %d", i);
    }
    CHECK(GSGifWriterClose(writer) == 0, @"close busy");
    GifReport busyReport = ReadGIF(busy, ^(int index, uint8_t *bgra, int width, int height) { DrawFrame(bgra, width, height, index, 40); }, bigW, bigH);
    printf("  busy            %zu frames, mean error %.2f, worst %d\n", busyReport.frames, busyReport.meanError, busyReport.worstError);
    CHECK(busyReport.ok && busyReport.frames == 3 && busyReport.meanError < 12, @"busy: %zu frames, mean %.2f", busyReport.frames, busyReport.meanError);
    free(big);
    free(small);
    free(buffer);
}

#pragma mark - Video to GIF

static BOOL WriteTestVideo(NSURL *url, int width, int height, int frames, int fps) {
    [NSFileManager.defaultManager removeItemAtURL:url error:NULL];
    NSError *error = nil;
    AVAssetWriter *writer = [AVAssetWriter assetWriterWithURL:url fileType:AVFileTypeMPEG4 error:&error];
    if (!writer) { printf("  no writer: %s\n", error.description.UTF8String); return NO; }
    AVAssetWriterInput *input = [AVAssetWriterInput assetWriterInputWithMediaType:AVMediaTypeVideo outputSettings:@{
        AVVideoCodecKey: AVVideoCodecTypeH264, AVVideoWidthKey: @(width), AVVideoHeightKey: @(height),
    }];
    input.expectsMediaDataInRealTime = NO;
    AVAssetWriterInputPixelBufferAdaptor *adaptor = [AVAssetWriterInputPixelBufferAdaptor
        assetWriterInputPixelBufferAdaptorWithAssetWriterInput:input sourcePixelBufferAttributes:@{
            (__bridge id)kCVPixelBufferPixelFormatTypeKey: @(kCVPixelFormatType_32BGRA),
            (__bridge id)kCVPixelBufferWidthKey: @(width), (__bridge id)kCVPixelBufferHeightKey: @(height),
        }];
    [writer addInput:input];
    if (![writer startWriting]) { printf("  cannot start: %s\n", writer.error.description.UTF8String); return NO; }
    [writer startSessionAtSourceTime:kCMTimeZero];
    uint8_t *scratch = malloc((size_t)width * height * 4);
    for (int i = 0; i < frames; i++) {
        int waited = 0;
        while (!input.readyForMoreMediaData && waited++ < 5000) usleep(1000);
        CVPixelBufferRef buffer = NULL;
        CVPixelBufferCreate(NULL, (size_t)width, (size_t)height, kCVPixelFormatType_32BGRA,
                            (__bridge CFDictionaryRef)@{(__bridge id)kCVPixelBufferIOSurfacePropertiesKey: @{}}, &buffer);
        if (!buffer) { free(scratch); return NO; }
        DrawFrame(scratch, width, height, i / 4, 0);
        CVPixelBufferLockBaseAddress(buffer, 0);
        uint8_t *base = CVPixelBufferGetBaseAddress(buffer);
        const size_t stride = CVPixelBufferGetBytesPerRow(buffer);
        for (int y = 0; y < height; y++) memcpy(base + y * stride, scratch + (size_t)y * width * 4, (size_t)width * 4);
        CVPixelBufferUnlockBaseAddress(buffer, 0);
        const BOOL added = [adaptor appendPixelBuffer:buffer withPresentationTime:CMTimeMake(i, fps)];
        CVPixelBufferRelease(buffer);
        if (!added) { printf("  frame %d not taken: %s\n", i, writer.error.description.UTF8String); free(scratch); return NO; }
    }
    free(scratch);
    [input markAsFinished];
    [writer endSessionAtSourceTime:CMTimeMake(frames, fps)];
    dispatch_semaphore_t done = dispatch_semaphore_create(0);
    [writer finishWritingWithCompletionHandler:^{ dispatch_semaphore_signal(done); }];
    dispatch_semaphore_wait(done, DISPATCH_TIME_FOREVER);
    return writer.status == AVAssetWriterStatusCompleted;
}

static void TestMaker(NSURL *folder) {
    printf("== video to GIF\n");
    NSURL *video = [folder URLByAppendingPathComponent:@"test.mp4"];
    const int width = 800, height = 600, frames = 90, fps = 30;      // 3 seconds
    const BOOL made = WriteTestVideo(video, width, height, frames, fps);
    CHECK(made, @"test video");
    if (!made) return;
    struct { GSGifPreset preset; int width, height, minFrames, maxFrames; } expect[] = {
        { GSGifPresetSmall, 320, 240, 28, 32 },         // every 0.08 s wanted, frames come every 0.033 s: each third one
        { GSGifPresetBalanced, 480, 360, 43, 47 },      // each second one
        { GSGifPresetHigh, 640, 480, 88, 92 },             // every frame
    };
    for (int i = 0; i < 3; i++) {
        NSString *name = GSGifPresetName(expect[i].preset);
        NSURL *gif = [folder URLByAppendingPathComponent:[NSString stringWithFormat:@"maker-%@.gif", name.lowercaseString]];
        NSURL *poster = [folder URLByAppendingPathComponent:[NSString stringWithFormat:@"maker-%@.jpg", name.lowercaseString]];
        NSError *error = nil;
        __block double lastProgress = -1;
        __block BOOL progressOrdered = YES;
        const CFAbsoluteTime started = CFAbsoluteTimeGetCurrent();
        GSGifResult *result = [GSGifMaker makeGIFAtURL:gif fromVideo:video preset:expect[i].preset posterURL:poster
                                              progress:^(double fraction) {
            if (fraction < lastProgress) progressOrdered = NO;
            lastProgress = fraction;
        } error:&error];
        CHECK(result != nil, @"%@: %@", name, error);
        if (!result) continue;
        printf("  %-9s %ld x %ld, %ld frames, %.2f s, %lld bytes, made in %.2f s\n", name.UTF8String, (long)result.width,
               (long)result.height, (long)result.frames, result.duration, result.bytes, CFAbsoluteTimeGetCurrent() - started);
        CHECK(result.width == expect[i].width && result.height == expect[i].height, @"%@ size %ld x %ld", name, (long)result.width, (long)result.height);
        CHECK(result.frames >= expect[i].minFrames && result.frames <= expect[i].maxFrames, @"%@ frames %ld", name, (long)result.frames);
        CHECK(fabs(result.duration - 3.0) < 0.12, @"%@ duration %.3f", name, result.duration);
        CHECK(!result.trimmed, @"%@ not trimmed", name);
        CHECK(progressOrdered && lastProgress == 1.0, @"%@ progress ends at %.2f", name, lastProgress);
        NSNumber *size = nil;
        [gif getResourceValue:&size forKey:NSURLFileSizeKey error:NULL];
        CHECK(size.longLongValue == result.bytes, @"%@ bytes %@ on disk, %lld reported", name, size, result.bytes);
        CHECK([NSFileManager.defaultManager fileExistsAtPath:poster.path], @"%@ poster", name);

        // The square is where the video had it: frame n of the GIF shows the video at about n times the interval.
        const double step = result.duration / result.frames;
        const int outW = (int)result.width, outH = (int)result.height;
        GifReport report = ReadGIF(gif, ^(int index, uint8_t *bgra, int w, int h) {
            uint8_t *full = malloc((size_t)width * height * 4);
            const int videoFrame = (int)lround(index * step * fps);
            DrawFrame(full, width, height, MIN(videoFrame, frames - 1) / 4, 0);
            for (int y = 0; y < h; y++) {
                for (int x = 0; x < w; x++) {
                    memcpy(bgra + ((size_t)y * w + x) * 4, full + ((size_t)(y * height / h) * width + (x * width / w)) * 4, 4);
                }
            }
            free(full);
        }, outW, outH);
        printf("            read back: %zu frames, %.2f s, mean error %.2f\n", report.frames, report.seconds, report.meanError);
        CHECK(report.ok && report.frames == (size_t)result.frames, @"%@ reads back %zu frames", name, report.frames);
        CHECK(fabs(report.seconds - result.duration) < 0.011, @"%@ reads back %.3f s", name, report.seconds);
        CHECK(report.meanError < 14, @"%@ mean error %.2f", name, report.meanError);
    }

    NSError *error = nil;
    NSURL *notVideo = [folder URLByAppendingPathComponent:@"not-a-video.mp4"];
    [[@"hello" dataUsingEncoding:NSUTF8StringEncoding] writeToURL:notVideo atomically:YES];
    GSGifResult *nothing = [GSGifMaker makeGIFAtURL:[folder URLByAppendingPathComponent:@"nothing.gif"] fromVideo:notVideo
                                             preset:GSGifPresetBalanced posterURL:nil progress:nil error:&error];
    CHECK(nothing == nil && error != nil, @"a file that is not a video is refused");
}

#pragma mark - The library

static void TestStore(NSURL *folder) {
    printf("== library\n");
    NSURL *root = [folder URLByAppendingPathComponent:@"stash-test" isDirectory:YES];
    [NSFileManager.defaultManager removeItemAtURL:root error:NULL];
    [GSStore useRoot:root];
    GSStore *store = GSStore.shared;
    CHECK(store.allItems.count == 0, @"empty at first");
    for (int i = 0; i < 3; i++) {
        GSItem *item = [GSItem new];
        item.itemID = [NSString stringWithFormat:@"100%d-1", i];
        item.kind = i == 1 ? @"video" : @"gif";
        item.author = @"CatPoster";
        item.text = i == 2 ? @"Monday mood" : nil;
        item.width = 480; item.height = 270;
        item.gifBytes = 1000 * (i + 1);
        item.savedAt = [NSDate dateWithTimeIntervalSince1970:1000000 + i * 10];
        [[@"GIF89a" dataUsingEncoding:NSUTF8StringEncoding] writeToURL:[store gifURLForID:item.itemID] atomically:YES];
        CHECK([store saveItem:item], @"save %d", i);
    }
    NSArray<GSItem *> *items = store.allItems;
    CHECK(items.count == 3 && [items.firstObject.itemID isEqualToString:@"1002-1"], @"newest first: %@", items.firstObject.itemID);
    CHECK([items.firstObject.searchText containsString:@"monday"] && [items.firstObject.searchText containsString:@"catposter"], @"search text");
    CHECK(fabs(items.firstObject.aspect - 0.5625) < 0.0001, @"aspect");
    GSItem *middle = [store itemWithID:@"1001-1"];
    middle.favorite = YES;
    middle.label = @"facepalm";
    [store saveItem:middle];
    GSItem *again = [store itemWithID:@"1001-1"];
    CHECK(again.favorite && [again.label isEqualToString:@"facepalm"] && [again.kind isEqualToString:@"video"], @"round trip");
    [store deleteItem:again];
    CHECK(store.allItems.count == 2 && ![NSFileManager.defaultManager fileExistsAtPath:[store gifURLForID:@"1001-1"].path], @"delete");
    store.preset = 2;
    CHECK(store.preset == 2, @"preset");
    store.preset = 1;
    CHECK([GSByteString(1400000) isEqualToString:@"1.4 MB"] && [GSByteString(820000) isEqualToString:@"820 KB"], @"byte strings");
}

#pragma mark - A real post

static int RunLive(NSURL *folder, NSString *link) {
    printf("== live: %s\n", link.UTF8String);
    NSURL *root = [folder URLByAppendingPathComponent:@"stash-live" isDirectory:YES];
    [NSFileManager.defaultManager removeItemAtURL:root error:NULL];
    [GSStore useRoot:root];
    GSImporter *importer = [GSImporter new];
    __block int result = 1;
    __block NSString *lastStage = nil;
    const CFAbsoluteTime started = CFAbsoluteTimeGetCurrent();
    [importer importText:link progress:^(NSString *stage, double fraction) {
        if (![stage isEqualToString:lastStage]) printf("  %s\n", stage.UTF8String);
        lastStage = stage;
    } completion:^(NSArray<GSItem *> *items, NSError *error) {
        if (error) printf("  FAILED: %s\n", error.localizedDescription.UTF8String);
        for (GSItem *item in items) {
            printf("  saved %s: %s by @%s, GIF %ld x %ld, %ld frames, %.2f s, %lld bytes (video %lld bytes, %.2f s)%s\n",
                   item.itemID.UTF8String, item.kind.UTF8String, item.author.UTF8String ?: "?", (long)item.width, (long)item.height,
                   (long)item.frames, item.gifDuration, item.gifBytes, item.videoBytes, item.videoDuration, item.trimmed ? " trimmed" : "");
            GifReport report = ReadGIF([GSStore.shared gifURLForID:item.itemID], nil, (int)item.width, (int)item.height);
            printf("        reads back: %zu frames, %.2f s, ok=%d\n", report.frames, report.seconds, report.ok);
            if (report.ok && report.frames == (size_t)item.frames) result = 0;
        }
        printf("  took %.1f s\n", CFAbsoluteTimeGetCurrent() - started);
        CFRunLoopStop(CFRunLoopGetMain());
    }];
    CFRunLoopRun();
    return result;
}

int main(int argc, const char *argv[]) {
    @autoreleasepool {
        BOOL live = NO;
        NSString *out = @"build-tests/out";
        NSString *link = @"https://x.com/oshtru/status/1577855540407197696";
        for (int i = 1; i < argc; i++) {
            NSString *argument = @(argv[i]);
            if ([argument isEqualToString:@"--live"]) live = YES;
            else if ([argument hasPrefix:@"http"]) link = argument;
            else out = argument;
        }
        NSURL *folder = [NSURL fileURLWithPath:out isDirectory:YES];
        [NSFileManager.defaultManager createDirectoryAtURL:folder withIntermediateDirectories:YES attributes:nil error:NULL];
        if (live) return RunLive(folder, link);

        TestLinks();
        TestFeed();
        TestWriter(folder);
        TestMaker(folder);
        TestStore(folder);
        printf("%d checks, %d failed\n", gChecks, gFailures);
        return gFailures ? 1 : 0;
    }
}
