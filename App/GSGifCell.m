#import "GSGifCell.h"
#import "GSLoopView.h"

void GSLoadPoster(GSItem *item, void (^done)(UIImage *image)) {
    static NSCache<NSString *, UIImage *> *cache;
    static dispatch_queue_t queue;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        cache = [NSCache new];
        cache.countLimit = 300;
        queue = dispatch_queue_create("com.cobradarsh.gifstash.posters", DISPATCH_QUEUE_CONCURRENT);
    });
    NSString *key = [NSString stringWithFormat:@"%@-%.0f", item.itemID, item.savedAt.timeIntervalSince1970];
    UIImage *ready = [cache objectForKey:key];
    if (ready) { done(ready); return; }
    NSURL *url = [GSStore.shared posterURLForID:item.itemID];
    dispatch_async(queue, ^{
        UIImage *image = [UIImage imageWithContentsOfFile:url.path];
        // Decode here rather than on the main thread at first draw.
        image = [image imageByPreparingForDisplay] ?: image;
        if (image) [cache setObject:image forKey:key];
        dispatch_async(dispatch_get_main_queue(), ^{ done(image); });
    });
}

@implementation GSGifCell {
    GSLoopView *_loop;
    UILabel *_badge;
    UIImageView *_star;
}

- (instancetype)initWithFrame:(CGRect)frame {
    if ((self = [super initWithFrame:frame])) {
        self.contentView.layer.cornerRadius = 16;
        self.contentView.layer.cornerCurve = kCACornerCurveContinuous;
        self.contentView.clipsToBounds = YES;
        self.contentView.backgroundColor = [UIColor colorWithWhite:0.09 alpha:1.0];

        _loop = [[GSLoopView alloc] initWithFrame:self.contentView.bounds];
        _loop.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
        _loop.userInteractionEnabled = NO;
        [self.contentView addSubview:_loop];

        _badge = [UILabel new];
        _badge.font = [UIFont systemFontOfSize:11 weight:UIFontWeightBold];
        _badge.textColor = UIColor.whiteColor;
        _badge.textAlignment = NSTextAlignmentCenter;
        _badge.backgroundColor = [UIColor colorWithWhite:0 alpha:0.55];
        _badge.layer.cornerRadius = 7;
        _badge.layer.cornerCurve = kCACornerCurveContinuous;
        _badge.clipsToBounds = YES;
        [self.contentView addSubview:_badge];

        _star = [[UIImageView alloc] initWithImage:[UIImage systemImageNamed:@"star.fill"]];
        _star.tintColor = [UIColor colorWithRed:1.0 green:0.80 blue:0.20 alpha:1.0];
        _star.contentMode = UIViewContentModeScaleAspectFit;
        _star.layer.shadowColor = UIColor.blackColor.CGColor;
        _star.layer.shadowOpacity = 0.6;
        _star.layer.shadowRadius = 3;
        _star.layer.shadowOffset = CGSizeZero;
        [self.contentView addSubview:_star];
    }
    return self;
}

- (void)layoutSubviews {
    [super layoutSubviews];
    const CGRect bounds = self.contentView.bounds;
    [_badge sizeToFit];
    const CGFloat width = MAX(30, _badge.bounds.size.width + 12);
    _badge.frame = CGRectMake(8, bounds.size.height - 8 - 20, width, 20);
    _star.frame = CGRectMake(bounds.size.width - 8 - 18, 8, 18, 18);
}

- (void)showItem:(GSItem *)item {
    const BOOL sameClip = [_item.itemID isEqualToString:item.itemID] && [_item.savedAt isEqualToDate:item.savedAt];
    _item = item;
    if ([item.kind isEqualToString:@"gif"]) {
        _badge.text = @"GIF";
    } else {
        const NSInteger seconds = (NSInteger)llround(MAX(item.videoDuration, item.gifDuration));
        _badge.text = [NSString stringWithFormat:@"%ld:%02ld", (long)(seconds / 60), (long)(seconds % 60)];
    }
    _star.hidden = !item.favorite;
    self.accessibilityLabel = item.label ?: item.text ?: (item.author ? [@"Clip from @" stringByAppendingString:item.author] : @"Clip");
    self.isAccessibilityElement = YES;
    [self setNeedsLayout];
    if (sameClip) return;

    _loop.videoURL = nil;
    _loop.poster = nil;
    NSString *wanted = item.itemID;
    __weak typeof(self) weakSelf = self;
    GSLoadPoster(item, ^(UIImage *image) {
        typeof(self) strongSelf = weakSelf;
        if (strongSelf && [strongSelf->_item.itemID isEqualToString:wanted]) strongSelf->_loop.poster = image;
    });
}

- (void)startPlaying {
    if (_item) _loop.videoURL = [GSStore.shared videoURLForID:_item.itemID];
}

- (void)stopPlaying {
    _loop.videoURL = nil;
}

- (void)prepareForReuse {
    [super prepareForReuse];
    [self stopPlaying];
}

- (void)setHighlighted:(BOOL)highlighted {
    [super setHighlighted:highlighted];
    [UIView animateWithDuration:0.18 delay:0 options:UIViewAnimationOptionBeginFromCurrentState | UIViewAnimationOptionAllowUserInteraction
                     animations:^{
        self.contentView.transform = highlighted ? CGAffineTransformMakeScale(0.96, 0.96) : CGAffineTransformIdentity;
    } completion:nil];
}

@end
