#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSInteger, GSGifPreset) {
    GSGifPresetSmall = 0,       // 320 px, 12 frames a second
    GSGifPresetBalanced = 1,    // 480 px, 16 frames a second
    GSGifPresetHigh = 2,        // 640 px, 20 frames a second, smoothed gradients
};

extern const double GSGifMaxSeconds;        // a GIF covers at most this much of a video

NSString *GSGifPresetName(GSGifPreset preset);

@interface GSGifResult : NSObject
@property (nonatomic) NSInteger width;
@property (nonatomic) NSInteger height;
@property (nonatomic) NSInteger frames;
@property (nonatomic) double duration;          // of the GIF
@property (nonatomic) double videoDuration;
@property (nonatomic) long long bytes;
@property (nonatomic) BOOL trimmed;
@end

/// Turns a video file into a GIF. Synchronous: call it off the main thread.
@interface GSGifMaker : NSObject
+ (nullable GSGifResult *)makeGIFAtURL:(NSURL *)gifURL
                             fromVideo:(NSURL *)videoURL
                                preset:(GSGifPreset)preset
                             posterURL:(nullable NSURL *)posterURL
                              progress:(nullable void (^)(double fraction))progress
                                 error:(NSError **)error;
@end

NS_ASSUME_NONNULL_END
