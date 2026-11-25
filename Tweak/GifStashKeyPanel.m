// The picker: laid over the keyboard, the saved clips three across and playing. Tapping one puts its GIF on the
// clipboard and pastes it into the text being edited, exactly as if "Paste" had been tapped in the message box.
#import "GifStashKey.h"
#import <AVFoundation/AVFoundation.h>
#import <ImageIO/ImageIO.h>

static NSString *const kTile = @"clip";
static const CGFloat kBar = 46;
static __weak GifStashKeyPanel *gPanel;

#pragma mark - Clips

@implementation GifStashKeyClip

- (NSString *)pathWithExtension:(NSString *)extension {
    return [GifStashKeyMirror() stringByAppendingPathComponent:[NSString stringWithFormat:@"%@.%@", self.clipID, extension]];
}

- (NSString *)gifPath { return [self pathWithExtension:@"gif"]; }
- (NSString *)videoPath { return [self pathWithExtension:@"mp4"]; }
- (NSString *)posterPath { return [self pathWithExtension:@"jpg"]; }

+ (NSArray<GifStashKeyClip *> *)allClips {
    NSFileManager *files = NSFileManager.defaultManager;
    NSString *mirror = GifStashKeyMirror();
    NSMutableArray<GifStashKeyClip *> *clips = [NSMutableArray new];
    for (NSString *name in [files contentsOfDirectoryAtPath:mirror error:NULL] ?: @[]) {
        if (![name.pathExtension isEqualToString:@"json"]) continue;
        NSData *data = [NSData dataWithContentsOfFile:[mirror stringByAppendingPathComponent:name]];
        NSDictionary *note = data ? [NSJSONSerialization JSONObjectWithData:data options:0 error:NULL] : nil;
        if (![note isKindOfClass:NSDictionary.class] || ![note[@"id"] isKindOfClass:NSString.class]) continue;
        GifStashKeyClip *clip = [GifStashKeyClip new];
        clip.clipID = note[@"id"];
        clip.favorite = [note[@"favorite"] boolValue];
        clip.savedAt = [note[@"savedAt"] doubleValue];
        id label = note[@"label"], text = note[@"text"];
        clip.title = [label isKindOfClass:NSString.class] ? label : ([text isKindOfClass:NSString.class] ? text : nil);
        if ([files fileExistsAtPath:clip.gifPath]) [clips addObject:clip];
    }
    [clips sortUsingComparator:^NSComparisonResult(GifStashKeyClip *a, GifStashKeyClip *b) {
        if (a.savedAt != b.savedAt) return a.savedAt > b.savedAt ? NSOrderedAscending : NSOrderedDescending;
        return [b.clipID compare:a.clipID];
    }];
    return clips;
}

@end

#pragma mark - A tile

@interface GifStashKeyPlayerView : UIView
@end

@implementation GifStashKeyPlayerView
+ (Class)layerClass { return AVPlayerLayer.class; }
@end

@interface GifStashKeyTile : UICollectionViewCell
@property (nonatomic, strong) GifStashKeyClip *clip;
- (void)showClip:(GifStashKeyClip *)clip;
- (void)play:(BOOL)play;
@end

@implementation GifStashKeyTile {
    UIImageView *_poster;
    GifStashKeyPlayerView *_video;
    UIImageView *_star;
    AVQueuePlayer *_player;
    AVPlayerLooper *_looper;
    NSString *_playing;
}

- (instancetype)initWithFrame:(CGRect)frame {
    if ((self = [super initWithFrame:frame])) {
        self.contentView.layer.cornerRadius = 10;
        self.contentView.layer.cornerCurve = kCACornerCurveContinuous;
        self.contentView.clipsToBounds = YES;
        self.contentView.backgroundColor = [UIColor colorWithWhite:0.10 alpha:1];
        _poster = [[UIImageView alloc] initWithFrame:self.contentView.bounds];
        _poster.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
        _poster.contentMode = UIViewContentModeScaleAspectFill;
        _poster.clipsToBounds = YES;
        [self.contentView addSubview:_poster];
        _video = [[GifStashKeyPlayerView alloc] initWithFrame:self.contentView.bounds];
        _video.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
        _video.userInteractionEnabled = NO;
        ((AVPlayerLayer *)_video.layer).videoGravity = AVLayerVideoGravityResizeAspectFill;
        [self.contentView addSubview:_video];
        _star = [[UIImageView alloc] initWithImage:[UIImage systemImageNamed:@"star.fill"]];
        _star.tintColor = [UIColor colorWithRed:1.0 green:0.80 blue:0.20 alpha:1.0];
        _star.contentMode = UIViewContentModeScaleAspectFit;
        _star.layer.shadowColor = UIColor.blackColor.CGColor;
        _star.layer.shadowOpacity = 0.6;
        _star.layer.shadowRadius = 2;
        _star.layer.shadowOffset = CGSizeZero;
        [self.contentView addSubview:_star];
    }
    return self;
}

- (void)layoutSubviews {
    [super layoutSubviews];
    _star.frame = CGRectMake(self.contentView.bounds.size.width - 5 - 14, 5, 14, 14);
}

- (void)showClip:(GifStashKeyClip *)clip {
    const BOOL same = [_clip.clipID isEqualToString:clip.clipID] && _clip.savedAt == clip.savedAt;
    _clip = clip;
    _star.hidden = !clip.favorite;
    self.isAccessibilityElement = YES;
    self.accessibilityLabel = clip.title ?: @"GIF";
    self.accessibilityTraits = UIAccessibilityTraitButton;
    if (same) return;
    [self play:NO];
    _poster.image = nil;
    NSString *wanted = clip.clipID, *path = clip.posterPath;
    __weak typeof(self) weakSelf = self;
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        UIImage *image = nil;
        CGImageSourceRef source = CGImageSourceCreateWithURL((__bridge CFURLRef)[NSURL fileURLWithPath:path], NULL);
        if (source) {
            NSDictionary *options = @{(__bridge id)kCGImageSourceCreateThumbnailFromImageAlways: @YES,
                                      (__bridge id)kCGImageSourceThumbnailMaxPixelSize: @360,
                                      (__bridge id)kCGImageSourceShouldCacheImmediately: @YES};
            CGImageRef small = CGImageSourceCreateThumbnailAtIndex(source, 0, (__bridge CFDictionaryRef)options);
            if (small) {
                image = [UIImage imageWithCGImage:small];
                CGImageRelease(small);
            }
            CFRelease(source);
        }
        dispatch_async(dispatch_get_main_queue(), ^{
            typeof(self) strongSelf = weakSelf;
            if (strongSelf && [strongSelf->_clip.clipID isEqualToString:wanted]) strongSelf->_poster.image = image;
        });
    });
}

- (void)play:(BOOL)play {
    NSString *wanted = (play && _clip) ? _clip.clipID : nil;
    if ((wanted == _playing) || [wanted isEqualToString:_playing]) return;
    _playing = wanted;
    [_player pause];
    [_looper disableLooping];
    _looper = nil;
    _player = nil;
    ((AVPlayerLayer *)_video.layer).player = nil;
    if (!wanted) return;

    NSURL *url = [NSURL fileURLWithPath:_clip.videoPath];
    __weak typeof(self) weakSelf = self;
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        // Picture only: a player that has a sound track, even muted, takes over the host app's audio (and stops
        // music playing elsewhere). This runs inside someone else's app, so it must not.
        AVURLAsset *asset = [AVURLAsset URLAssetWithURL:url options:nil];
        AVAssetTrack *track = [asset tracksWithMediaType:AVMediaTypeVideo].firstObject;
        AVMutableComposition *silent = [AVMutableComposition composition];
        AVMutableCompositionTrack *picture = [silent addMutableTrackWithMediaType:AVMediaTypeVideo
                                                                  preferredTrackID:kCMPersistentTrackID_Invalid];
        BOOL ok = track != nil && [picture insertTimeRange:track.timeRange ofTrack:track atTime:kCMTimeZero error:NULL];
        if (ok) picture.preferredTransform = track.preferredTransform;
        dispatch_async(dispatch_get_main_queue(), ^{
            typeof(self) strongSelf = weakSelf;
            if (!ok || !strongSelf || ![strongSelf->_playing isEqualToString:wanted]) return;
            AVPlayerItem *item = [AVPlayerItem playerItemWithAsset:silent];
            AVQueuePlayer *player = [AVQueuePlayer new];
            player.muted = YES;
            player.allowsExternalPlayback = NO;
            player.preventsDisplaySleepDuringVideoPlayback = NO;
            player.automaticallyWaitsToMinimizeStalling = NO;
            strongSelf->_player = player;
            strongSelf->_looper = [AVPlayerLooper playerLooperWithPlayer:player templateItem:item];
            ((AVPlayerLayer *)strongSelf->_video.layer).player = player;
            [player play];
        });
    });
}

- (void)prepareForReuse {
    [super prepareForReuse];
    [self play:NO];
}

- (void)setHighlighted:(BOOL)highlighted {
    [super setHighlighted:highlighted];
    self.contentView.alpha = highlighted ? 0.55 : 1.0;
}

- (void)dealloc {
    [_player pause];
    [_looper disableLooping];
}

@end

#pragma mark - The panel

@interface GifStashKeyPanel () <UICollectionViewDataSource, UICollectionViewDelegateFlowLayout>
- (void)reload;
@end

@implementation GifStashKeyPanel {
    UICollectionView *_collection;
    UISegmentedControl *_filter;
    UIImageView *_icon;
    UILabel *_title;
    UIButton *_close;
    UILabel *_message;
    NSArray<GifStashKeyClip *> *_clips;
    CGFloat _bottomInset;
}

static void PanelSynced(CFNotificationCenterRef center, void *observer, CFNotificationName name, const void *object,
                        CFDictionaryRef userInfo) {
    dispatch_async(dispatch_get_main_queue(), ^{ [gPanel reload]; });
}

+ (GifStashKeyPanel *)current {
    return gPanel;
}

+ (void)close {
    GifStashKeyPanel *panel = gPanel;
    if (!panel) return;
    gPanel = nil;
    for (GifStashKeyTile *tile in panel->_collection.visibleCells) [tile play:NO];
    [UIView animateWithDuration:0.16 animations:^{ panel.alpha = 0; } completion:^(BOOL finished) { [panel removeFromSuperview]; }];
}

+ (void)toggleFromDock:(UIView *)dock {
    if (gPanel) {
        [self close];
        return;
    }
    // The view that holds the whole keyboard, bar included.
    UIView *host = nil;
    for (UIView *view = dock.superview; view; view = view.superview) {
        if ([NSStringFromClass(view.class) containsString:@"InputSetHostView"]) { host = view; break; }
    }
    CGRect frame;
    if (host) {
        frame = host.bounds;
    } else {
        // No such view (another iOS): cover the window from the top of the keyboard down, by the bar's place in it.
        host = dock.window;
        if (!host) return;
        const CGRect bar = [host convertRect:dock.bounds fromView:dock];
        const CGFloat top = MAX(0, CGRectGetMaxY(bar) - 336);
        frame = CGRectMake(0, top, host.bounds.size.width, host.bounds.size.height - top);
    }
    GifStashKeyPanel *panel = [[GifStashKeyPanel alloc] initWithFrame:frame];
    panel.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    panel->_bottomInset = MAX(host.safeAreaInsets.bottom, dock.window.safeAreaInsets.bottom);
    [host addSubview:panel];
    gPanel = panel;
    panel.alpha = 0;
    [UIView animateWithDuration:0.16 animations:^{ panel.alpha = 1; }];
    [panel reload];
    // SpringBoard brings its copy of the library up to date and says when it has.
    CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(), (__bridge CFStringRef)GifStashKeySyncRequest,
                                         NULL, NULL, YES);
}

- (instancetype)initWithFrame:(CGRect)frame {
    if ((self = [super initWithFrame:frame])) {
        self.overrideUserInterfaceStyle = UIUserInterfaceStyleDark;
        self.backgroundColor = UIColor.blackColor;
        UIColor *accent = GifStashKeyAccent();
        self.tintColor = accent;
        _clips = @[];

        _icon = [[UIImageView alloc] initWithImage:GifStashKeyIcon()];
        _icon.contentMode = UIViewContentModeScaleAspectFit;
        _icon.layer.cornerRadius = 6;
        _icon.layer.cornerCurve = kCACornerCurveContinuous;
        _icon.clipsToBounds = YES;
        [self addSubview:_icon];

        _title = [UILabel new];
        _title.text = @"GIF Stash";
        _title.font = [UIFont systemFontOfSize:15 weight:UIFontWeightSemibold];
        _title.textColor = accent;
        [self addSubview:_title];

        _filter = [[UISegmentedControl alloc] initWithItems:@[@"All", @"★"]];
        _filter.selectedSegmentIndex = [NSUserDefaults.standardUserDefaults boolForKey:@"GifStashKeyFavorites"] ? 1 : 0;
        _filter.selectedSegmentTintColor = [accent colorWithAlphaComponent:0.30];
        [_filter setTitleTextAttributes:@{NSForegroundColorAttributeName: UIColor.whiteColor} forState:UIControlStateNormal];
        [_filter setTitleTextAttributes:@{NSForegroundColorAttributeName: accent} forState:UIControlStateSelected];
        [_filter addTarget:self action:@selector(filterChanged) forControlEvents:UIControlEventValueChanged];
        [self addSubview:_filter];

        _close = [UIButton buttonWithType:UIButtonTypeSystem];
        [_close setImage:[UIImage systemImageNamed:@"keyboard.chevron.compact.down"
                                 withConfiguration:[UIImageSymbolConfiguration configurationWithPointSize:19 weight:UIImageSymbolWeightMedium]]
                forState:UIControlStateNormal];
        _close.tintColor = accent;
        _close.accessibilityLabel = @"Back to the keyboard";
        [_close addTarget:self action:@selector(closeTapped) forControlEvents:UIControlEventTouchUpInside];
        [self addSubview:_close];

        UICollectionViewFlowLayout *layout = [UICollectionViewFlowLayout new];
        layout.minimumInteritemSpacing = 6;
        layout.minimumLineSpacing = 6;
        _collection = [[UICollectionView alloc] initWithFrame:CGRectZero collectionViewLayout:layout];
        _collection.backgroundColor = UIColor.clearColor;
        _collection.alwaysBounceVertical = YES;
        _collection.dataSource = self;
        _collection.delegate = self;
        _collection.indicatorStyle = UIScrollViewIndicatorStyleWhite;
        [_collection registerClass:GifStashKeyTile.class forCellWithReuseIdentifier:kTile];
        [self addSubview:_collection];

        _message = [UILabel new];
        _message.font = [UIFont systemFontOfSize:15];
        _message.textColor = [UIColor colorWithWhite:1 alpha:0.6];
        _message.textAlignment = NSTextAlignmentCenter;
        _message.numberOfLines = 0;
        _message.hidden = YES;
        [self addSubview:_message];

        CFNotificationCenterAddObserver(CFNotificationCenterGetDarwinNotifyCenter(), (__bridge const void *)self, PanelSynced,
                                        (__bridge CFStringRef)GifStashKeySynced, NULL, CFNotificationSuspensionBehaviorDeliverImmediately);
        // When the keyboard goes away, so does the picker: the next keyboard starts as a keyboard.
        [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(keyboardWentAway)
                                                   name:UIKeyboardDidHideNotification object:nil];
    }
    return self;
}

- (void)keyboardWentAway {
    if (gPanel == self) [GifStashKeyPanel close];
}

- (void)dealloc {
    [NSNotificationCenter.defaultCenter removeObserver:self];
    CFNotificationCenterRemoveEveryObserver(CFNotificationCenterGetDarwinNotifyCenter(), (__bridge const void *)self);
}

- (void)layoutSubviews {
    [super layoutSubviews];
    const CGRect bounds = self.bounds;
    _icon.frame = CGRectMake(12, (kBar - 24) / 2, 24, 24);
    _title.frame = CGRectMake(44, 0, 110, kBar);
    _close.frame = CGRectMake(bounds.size.width - 56, 0, 52, kBar);
    const CGFloat filterWidth = 116;
    _filter.frame = CGRectMake(round((bounds.size.width - filterWidth) / 2), (kBar - 30) / 2, filterWidth, 30);
    _collection.frame = CGRectMake(0, kBar, bounds.size.width, MAX(0, bounds.size.height - kBar));
    _collection.contentInset = UIEdgeInsetsMake(0, 0, _bottomInset, 0);
    _collection.scrollIndicatorInsets = _collection.contentInset;
    _message.frame = CGRectInset(CGRectMake(0, kBar, bounds.size.width, MAX(0, bounds.size.height - kBar - _bottomInset)), 28, 6);
}

- (void)reload {
    NSArray<GifStashKeyClip *> *all = [GifStashKeyClip allClips];
    const BOOL favorites = _filter.selectedSegmentIndex == 1;
    NSMutableArray<GifStashKeyClip *> *shown = [NSMutableArray new];
    for (GifStashKeyClip *clip in all) {
        if (!favorites || clip.favorite) [shown addObject:clip];
    }
    NSString *message = nil;
    if (shown.count == 0) {
        NSString *mirror = GifStashKeyMirror();
        if (![NSFileManager.defaultManager fileExistsAtPath:[mirror stringByAppendingPathComponent:@"mirror.info"]]) {
            message = @"GIF Stash's library is not visible here yet.\nRespring once, then try again.";
        } else if (favorites && all.count) {
            message = @"No favourites yet.\nStar a clip in GIF Stash and it shows up here.";
        } else {
            message = @"No GIFs saved yet.\nIn X, hold a GIF, tap “Share via…” and choose GIF Stash.";
        }
    }
    // Leave the tiles alone when nothing changed, so that they do not start their loops again.
    BOOL sameList = shown.count == _clips.count;
    for (NSUInteger i = 0; sameList && i < shown.count; i++) {
        sameList = [shown[i].clipID isEqualToString:_clips[i].clipID] && shown[i].savedAt == _clips[i].savedAt
                   && shown[i].favorite == _clips[i].favorite;
    }
    _clips = shown;
    _message.text = message;
    _message.hidden = message == nil;
    if (!sameList) [_collection reloadData];
    GifStashKeyLog(@"panel: %lu of %lu clips shown, frame %@ in %@", (unsigned long)shown.count, (unsigned long)all.count,
                   NSStringFromCGRect(self.frame), NSStringFromClass(self.superview.class));
}

- (NSUInteger)clipCount {
    return _clips.count;
}

- (void)filterChanged {
    [NSUserDefaults.standardUserDefaults setBool:_filter.selectedSegmentIndex == 1 forKey:@"GifStashKeyFavorites"];
    [self reload];
    [_collection setContentOffset:CGPointZero animated:NO];
}

- (void)closeTapped {
    [GifStashKeyPanel close];
}

#pragma mark Tiles

- (NSInteger)collectionView:(UICollectionView *)collectionView numberOfItemsInSection:(NSInteger)section {
    return _clips.count;
}

- (UICollectionViewCell *)collectionView:(UICollectionView *)collectionView cellForItemAtIndexPath:(NSIndexPath *)indexPath {
    GifStashKeyTile *tile = [collectionView dequeueReusableCellWithReuseIdentifier:kTile forIndexPath:indexPath];
    [tile showClip:_clips[indexPath.item]];
    return tile;
}

- (CGSize)collectionView:(UICollectionView *)collectionView layout:(UICollectionViewLayout *)layout
  sizeForItemAtIndexPath:(NSIndexPath *)indexPath {
    const CGFloat width = floor((collectionView.bounds.size.width - 6 * 4) / 3);
    return CGSizeMake(width, round(width * 0.82));
}

- (UIEdgeInsets)collectionView:(UICollectionView *)collectionView layout:(UICollectionViewLayout *)layout
        insetForSectionAtIndex:(NSInteger)section {
    return UIEdgeInsetsMake(2, 6, 6, 6);
}

- (void)collectionView:(UICollectionView *)collectionView willDisplayCell:(UICollectionViewCell *)cell forItemAtIndexPath:(NSIndexPath *)indexPath {
    [(GifStashKeyTile *)cell play:YES];
}

- (void)collectionView:(UICollectionView *)collectionView didEndDisplayingCell:(UICollectionViewCell *)cell forItemAtIndexPath:(NSIndexPath *)indexPath {
    [(GifStashKeyTile *)cell play:NO];
}

- (void)collectionView:(UICollectionView *)collectionView didSelectItemAtIndexPath:(NSIndexPath *)indexPath {
    [collectionView deselectItemAtIndexPath:indexPath animated:NO];
    [self pickIndex:(NSUInteger)indexPath.item];
}

#pragma mark Pasting

+ (void)toast:(NSString *)text {
    UIWindow *window = nil;
    for (UIWindow *candidate in [UIWindow respondsToSelector:@selector(allWindowsIncludingInternalWindows:onlyVisibleWindows:)]
             ? [UIWindow allWindowsIncludingInternalWindows:YES onlyVisibleWindows:YES] : @[]) {
        if (!window || candidate.windowLevel >= window.windowLevel) window = candidate;
    }
    if (!window) return;
    UILabel *label = [UILabel new];
    label.text = text;
    label.font = [UIFont systemFontOfSize:15 weight:UIFontWeightSemibold];
    label.textColor = UIColor.blackColor;
    label.backgroundColor = GifStashKeyAccent();
    label.textAlignment = NSTextAlignmentCenter;
    label.numberOfLines = 2;
    label.layer.cornerRadius = 16;
    label.layer.cornerCurve = kCACornerCurveContinuous;
    label.clipsToBounds = YES;
    label.userInteractionEnabled = NO;
    const CGFloat width = MIN(window.bounds.size.width - 40, 340);
    label.frame = CGRectMake(round((window.bounds.size.width - width) / 2), window.safeAreaInsets.top + 12, width, 52);
    label.alpha = 0;
    [window addSubview:label];
    [UIView animateWithDuration:0.2 animations:^{ label.alpha = 1; } completion:^(BOOL finished) {
        [UIView animateWithDuration:0.3 delay:2.4 options:0 animations:^{ label.alpha = 0; } completion:^(BOOL done) {
            [label removeFromSuperview];
        }];
    }];
}

- (BOOL)pickIndex:(NSUInteger)index {
    if (index >= _clips.count) return NO;
    GifStashKeyClip *clip = _clips[index];
    NSString *path = clip.gifPath;
    [[UIImpactFeedbackGenerator new] impactOccurred];
    [GifStashKeyPanel close];
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        NSData *data = [NSData dataWithContentsOfFile:path options:NSDataReadingMappedIfSafe error:NULL];
        if (data.length) [UIPasteboard.generalPasteboard setData:data forPasteboardType:@"com.compuserve.gif"];
        const NSUInteger bytes = data.length;
        // A moment for the keyboard to be back in front, then the same "paste:" the Paste button sends.
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.12 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            if (!bytes) {
                [GifStashKeyPanel toast:@"That GIF's file is missing."];
                GifStashKeyLog(@"pick %@: file missing", clip.clipID);
                return;
            }
            const BOOL pasted = [UIApplication.sharedApplication sendAction:@selector(paste:) to:nil from:nil forEvent:nil];
            if (!pasted) [GifStashKeyPanel toast:@"Copied. Hold the message box and tap Paste."];
            GifStashKeyLog(@"pick %@: %lu bytes on the clipboard, paste taken=%d", clip.clipID, (unsigned long)bytes, pasted);
        });
    });
    return YES;
}

@end
