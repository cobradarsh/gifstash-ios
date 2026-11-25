#import "GSLoopView.h"
#import <AVFoundation/AVFoundation.h>

@interface GSPlayerLayerView : UIView
@end

@implementation GSPlayerLayerView
+ (Class)layerClass { return AVPlayerLayer.class; }
@end

@implementation GSLoopView {
    UIImageView *_posterView;
    GSPlayerLayerView *_video;
    AVQueuePlayer *_player;
    AVPlayerLooper *_looper;
}

+ (void)useQuietAudio {
    [AVAudioSession.sharedInstance setCategory:AVAudioSessionCategoryAmbient
                                   withOptions:AVAudioSessionCategoryOptionMixWithOthers error:NULL];
}

- (instancetype)initWithFrame:(CGRect)frame {
    if ((self = [super initWithFrame:frame])) {
        self.clipsToBounds = YES;
        self.backgroundColor = [UIColor colorWithWhite:0.09 alpha:1.0];
        _fills = YES;
        _posterView = [[UIImageView alloc] initWithFrame:self.bounds];
        _posterView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
        _posterView.contentMode = UIViewContentModeScaleAspectFill;
        _posterView.clipsToBounds = YES;
        [self addSubview:_posterView];
        _video = [[GSPlayerLayerView alloc] initWithFrame:self.bounds];
        _video.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
        _video.userInteractionEnabled = NO;
        ((AVPlayerLayer *)_video.layer).videoGravity = AVLayerVideoGravityResizeAspectFill;
        [self addSubview:_video];
    }
    return self;
}

- (void)setFills:(BOOL)fills {
    _fills = fills;
    _posterView.contentMode = fills ? UIViewContentModeScaleAspectFill : UIViewContentModeScaleAspectFit;
    ((AVPlayerLayer *)_video.layer).videoGravity = fills ? AVLayerVideoGravityResizeAspectFill : AVLayerVideoGravityResizeAspect;
}

- (void)setPoster:(UIImage *)poster {
    _poster = poster;
    _posterView.image = poster;
}

- (void)setVideoURL:(NSURL *)videoURL {
    if ((videoURL == _videoURL) || [videoURL isEqual:_videoURL]) return;
    _videoURL = videoURL;
    [_player pause];
    [_looper disableLooping];
    _looper = nil;
    _player = nil;
    ((AVPlayerLayer *)_video.layer).player = nil;
    if (!videoURL) return;

    AVPlayerItem *item = [AVPlayerItem playerItemWithURL:videoURL];
    _player = [AVQueuePlayer new];
    _player.muted = YES;
    _player.allowsExternalPlayback = NO;
    _player.preventsDisplaySleepDuringVideoPlayback = NO;
    _player.automaticallyWaitsToMinimizeStalling = NO;
    _looper = [AVPlayerLooper playerLooperWithPlayer:_player templateItem:item];
    ((AVPlayerLayer *)_video.layer).player = _player;
    [_player play];
}

- (void)pause { [_player pause]; }
- (void)resume { [_player play]; }

- (void)dealloc {
    [_player pause];
    [_looper disableLooping];
}

@end
