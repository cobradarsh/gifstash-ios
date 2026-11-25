#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

/// Plays a short MP4 silently in a loop (hardware decoded, so a screen full of them stays cheap), over a still
/// picture that shows until the first frame is ready.
@interface GSLoopView : UIView
@property (nonatomic, strong, nullable) UIImage *poster;
@property (nonatomic, strong, nullable) NSURL *videoURL;       // setting it starts playback; nil stops and frees it
@property (nonatomic) BOOL fills;                               // YES: crop to fill (tiles). NO: show all of it.
- (void)pause;
- (void)resume;
/// Other apps' music keeps playing while clips loop.
+ (void)useQuietAudio;
@end

NS_ASSUME_NONNULL_END
