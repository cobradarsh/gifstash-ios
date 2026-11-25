// The GIF Stash keyboard: the saved clips, inside any chat. Tapping one puts its GIF on the clipboard, ready to paste
// into the message box (a keyboard cannot insert a picture itself; every GIF keyboard on iOS works this way).
#import <ImageIO/ImageIO.h>
#import <UIKit/UIKit.h>
#import "GSCommon.h"
#import "GSLoopView.h"
#import "GSStore.h"

static NSString *const kTile = @"tile";
static const CGFloat kBarHeight = 44;
static const CGFloat kKeyboardHeight = 312;

static UIColor *GSKeyTint(void) {
    return [UIColor colorWithRed:1.00 green:0.33 blue:0.55 alpha:1.0];
}

/// A small copy of a clip's still picture: the keyboard has far less memory to work with than the app.
static UIImage *GSSmallPoster(NSURL *url, CGFloat pixels) {
    CGImageSourceRef source = CGImageSourceCreateWithURL((__bridge CFURLRef)url, NULL);
    if (!source) return nil;
    NSDictionary *options = @{
        (__bridge id)kCGImageSourceCreateThumbnailFromImageAlways: @YES,
        (__bridge id)kCGImageSourceCreateThumbnailWithTransform: @YES,
        (__bridge id)kCGImageSourceThumbnailMaxPixelSize: @(pixels),
        (__bridge id)kCGImageSourceShouldCacheImmediately: @YES,
    };
    CGImageRef image = CGImageSourceCreateThumbnailAtIndex(source, 0, (__bridge CFDictionaryRef)options);
    CFRelease(source);
    if (!image) return nil;
    UIImage *result = [UIImage imageWithCGImage:image];
    CGImageRelease(image);
    return result;
}

/// With the file `kb-diag` in the shared container, the keyboard notes what it has and how much memory it uses.
static void GSKeyLog(NSString *event, NSDictionary *info) {
    NSURL *folder = GSStore.shared.rootURL.URLByDeletingLastPathComponent;
    if (!GSStore.shared.usesGroup || ![NSFileManager.defaultManager fileExistsAtPath:[folder URLByAppendingPathComponent:@"kb-diag"].path]) return;
    NSMutableDictionary *entry = [NSMutableDictionary dictionaryWithDictionary:info ?: @{}];
    entry[@"t"] = @(NSDate.date.timeIntervalSince1970);
    entry[@"event"] = event;
    entry[@"footprintMB"] = @(round(GSFootprintMB() * 10) / 10);
    entry[@"availableMB"] = @(round(GSAvailableMB() * 10) / 10);
    NSData *json = [NSJSONSerialization dataWithJSONObject:entry options:0 error:NULL];
    if (!json) return;
    NSString *path = [folder URLByAppendingPathComponent:@"kb-diag.log"].path;
    if (![NSFileManager.defaultManager fileExistsAtPath:path]) [NSData.data writeToFile:path atomically:NO];
    NSFileHandle *handle = [NSFileHandle fileHandleForWritingAtPath:path];
    [handle seekToEndOfFile];
    [handle writeData:json];
    [handle writeData:[@"\n" dataUsingEncoding:NSUTF8StringEncoding]];
    [handle closeFile];
}

#pragma mark - A tile

@interface GSKeyTile : UICollectionViewCell
@property (nonatomic, strong) GSItem *item;
- (void)showItem:(GSItem *)item;
- (void)play:(BOOL)play;
@end

@implementation GSKeyTile {
    GSLoopView *_loop;
    UIImageView *_star;
}

- (instancetype)initWithFrame:(CGRect)frame {
    if ((self = [super initWithFrame:frame])) {
        self.contentView.layer.cornerRadius = 10;
        self.contentView.layer.cornerCurve = kCACornerCurveContinuous;
        self.contentView.clipsToBounds = YES;
        _loop = [[GSLoopView alloc] initWithFrame:self.contentView.bounds];
        _loop.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
        _loop.userInteractionEnabled = NO;
        [self.contentView addSubview:_loop];
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

- (void)showItem:(GSItem *)item {
    const BOOL same = [_item.itemID isEqualToString:item.itemID] && [_item.savedAt isEqualToDate:item.savedAt];
    _item = item;
    _star.hidden = !item.favorite;
    self.isAccessibilityElement = YES;
    self.accessibilityLabel = item.label ?: item.text ?: @"GIF";
    self.accessibilityTraits = UIAccessibilityTraitButton;
    if (same) return;
    _loop.videoURL = nil;
    _loop.poster = nil;
    NSString *wanted = item.itemID;
    NSURL *poster = [GSStore.shared posterURLForID:item.itemID];
    const CGFloat pixels = 150 * UIScreen.mainScreen.scale * 0.75;
    __weak typeof(self) weakSelf = self;
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        UIImage *image = GSSmallPoster(poster, pixels);
        dispatch_async(dispatch_get_main_queue(), ^{
            typeof(self) strongSelf = weakSelf;
            if (strongSelf && [strongSelf->_item.itemID isEqualToString:wanted]) strongSelf->_loop.poster = image;
        });
    });
}

- (void)play:(BOOL)play {
    _loop.videoURL = (play && _item) ? [GSStore.shared videoURLForID:_item.itemID] : nil;
}

- (void)prepareForReuse {
    [super prepareForReuse];
    [self play:NO];
}

- (void)setHighlighted:(BOOL)highlighted {
    [super setHighlighted:highlighted];
    self.contentView.alpha = highlighted ? 0.6 : 1.0;
}

@end

#pragma mark - The keyboard

@interface KeyboardViewController : UIInputViewController <UICollectionViewDataSource, UICollectionViewDelegateFlowLayout>
@end

@implementation KeyboardViewController {
    UICollectionView *_collection;
    UISegmentedControl *_filter;
    UIButton *_next;
    UIButton *_erase;
    UILabel *_message;
    UILabel *_toast;
    NSArray<GSItem *> *_items;
    BOOL _animates;
    NSLayoutConstraint *_height;
}

static UIButton *GSKeyButton(NSString *symbol, NSString *label) {
    UIButton *button = [UIButton buttonWithType:UIButtonTypeSystem];
    [button setImage:[UIImage systemImageNamed:symbol
                             withConfiguration:[UIImageSymbolConfiguration configurationWithPointSize:18 weight:UIImageSymbolWeightMedium]]
            forState:UIControlStateNormal];
    button.tintColor = UIColor.labelColor;
    button.accessibilityLabel = label;
    return button;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    [GSLoopView useQuietAudio];
    _items = @[];

    _next = GSKeyButton(@"globe", @"Next keyboard");
    [_next addTarget:self action:@selector(handleInputModeListFromView:withEvent:) forControlEvents:UIControlEventAllTouchEvents];
    [self.view addSubview:_next];

    _filter = [[UISegmentedControl alloc] initWithItems:@[@"All", @"Favourites"]];
    _filter.selectedSegmentIndex = [NSUserDefaults.standardUserDefaults integerForKey:@"filter"] == 1 ? 1 : 0;
    [_filter addTarget:self action:@selector(filterChanged) forControlEvents:UIControlEventValueChanged];
    [self.view addSubview:_filter];

    _erase = GSKeyButton(@"delete.left", @"Delete");
    [_erase addTarget:self action:@selector(eraseTapped) forControlEvents:UIControlEventTouchUpInside];
    [self.view addSubview:_erase];

    UICollectionViewFlowLayout *layout = [UICollectionViewFlowLayout new];
    layout.minimumInteritemSpacing = 6;
    layout.minimumLineSpacing = 6;
    layout.sectionInset = UIEdgeInsetsMake(2, 6, 6, 6);
    _collection = [[UICollectionView alloc] initWithFrame:CGRectZero collectionViewLayout:layout];
    _collection.backgroundColor = UIColor.clearColor;
    _collection.alwaysBounceVertical = YES;
    _collection.dataSource = self;
    _collection.delegate = self;
    [_collection registerClass:GSKeyTile.class forCellWithReuseIdentifier:kTile];
    [self.view addSubview:_collection];

    _message = [UILabel new];
    _message.font = [UIFont systemFontOfSize:15];
    _message.textColor = UIColor.secondaryLabelColor;
    _message.textAlignment = NSTextAlignmentCenter;
    _message.numberOfLines = 0;
    _message.hidden = YES;
    [self.view addSubview:_message];

    _toast = [UILabel new];
    _toast.font = [UIFont systemFontOfSize:15 weight:UIFontWeightSemibold];
    _toast.textColor = UIColor.whiteColor;
    _toast.backgroundColor = [GSKeyTint() colorWithAlphaComponent:0.96];
    _toast.textAlignment = NSTextAlignmentCenter;
    _toast.numberOfLines = 2;
    _toast.layer.cornerRadius = 14;
    _toast.layer.cornerCurve = kCACornerCurveContinuous;
    _toast.clipsToBounds = YES;
    _toast.alpha = 0;
    [self.view addSubview:_toast];
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    if (!_height) {
        _height = [self.view.heightAnchor constraintEqualToConstant:kKeyboardHeight];
        _height.priority = 999;
        _height.active = YES;
    }
    [self reload];
}

- (void)viewDidAppear:(BOOL)animated {
    [super viewDidAppear:animated];
    GSKeyLog(@"appear", @{@"fullAccess": @(self.hasFullAccess), @"usesGroup": @(GSStore.shared.usesGroup),
                          @"clips": @(_items.count), @"animates": @(_animates)});
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(4 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        GSKeyLog(@"settled", @{@"visible": @(self->_collection.visibleCells.count)});
    });
}

- (void)viewDidDisappear:(BOOL)animated {
    [super viewDidDisappear:animated];
    for (GSKeyTile *tile in _collection.visibleCells) [tile play:NO];
}

- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    const CGRect bounds = self.view.bounds;
    _next.frame = CGRectMake(4, 0, 48, kBarHeight);
    _erase.frame = CGRectMake(bounds.size.width - 52, 0, 48, kBarHeight);
    const CGFloat filterWidth = MIN(240, bounds.size.width - 120);
    _filter.frame = CGRectMake(round((bounds.size.width - filterWidth) / 2), 7, filterWidth, 30);
    _collection.frame = CGRectMake(0, kBarHeight, bounds.size.width, MAX(0, bounds.size.height - kBarHeight));
    _message.frame = CGRectInset(_collection.frame, 28, 8);
    const CGFloat toastWidth = MIN(bounds.size.width - 32, 360);
    _toast.frame = CGRectMake(round((bounds.size.width - toastWidth) / 2), bounds.size.height - 64, toastWidth, 52);
    [_collection.collectionViewLayout invalidateLayout];
}

- (void)reload {
    GSStore *store = GSStore.shared;
    NSString *message = nil;
    NSArray<GSItem *> *items = @[];
    if (!self.hasFullAccess || !store.usesGroup) {
        message = @"Allow Full Access to see your GIFs here.\n\nSettings › GIF Stash › Keyboards › Allow Full Access. "
                  @"The keyboard needs it to read your library and to put a GIF on the clipboard.";
    } else {
        _animates = store.keyboardAnimates;
        NSMutableArray<GSItem *> *shown = [NSMutableArray new];
        const BOOL favorites = _filter.selectedSegmentIndex == 1;
        for (GSItem *item in store.allItems) {
            if (!favorites || item.favorite) [shown addObject:item];
        }
        items = shown;
        if (shown.count == 0) {
            message = favorites ? @"No favourites yet.\nStar a clip in GIF Stash and it shows up here."
                                : @"No GIFs saved yet.\nIn X, hold a GIF, tap “Share via…” and choose GIF Stash.";
        }
    }
    _items = items;
    _message.text = message;
    _message.hidden = message == nil;
    [_collection reloadData];
}

- (void)filterChanged {
    [NSUserDefaults.standardUserDefaults setInteger:_filter.selectedSegmentIndex forKey:@"filter"];
    [self reload];
    [_collection setContentOffset:CGPointZero animated:NO];
}

- (void)eraseTapped {
    [self.textDocumentProxy deleteBackward];
    [UIDevice.currentDevice playInputClick];
}

#pragma mark - Tiles

- (NSInteger)collectionView:(UICollectionView *)collectionView numberOfItemsInSection:(NSInteger)section {
    return _items.count;
}

- (UICollectionViewCell *)collectionView:(UICollectionView *)collectionView cellForItemAtIndexPath:(NSIndexPath *)indexPath {
    GSKeyTile *tile = [collectionView dequeueReusableCellWithReuseIdentifier:kTile forIndexPath:indexPath];
    [tile showItem:_items[indexPath.item]];
    return tile;
}

- (CGSize)collectionView:(UICollectionView *)collectionView layout:(UICollectionViewLayout *)layout
  sizeForItemAtIndexPath:(NSIndexPath *)indexPath {
    // Three across; two rows and the top of a third show, so it is plain that the list scrolls.
    const CGFloat width = floor((collectionView.bounds.size.width - 6 * 4) / 3);
    return CGSizeMake(width, round(width * 0.82));
}

- (void)collectionView:(UICollectionView *)collectionView willDisplayCell:(UICollectionViewCell *)cell forItemAtIndexPath:(NSIndexPath *)indexPath {
    if (_animates) [(GSKeyTile *)cell play:YES];
}

- (void)collectionView:(UICollectionView *)collectionView didEndDisplayingCell:(UICollectionViewCell *)cell forItemAtIndexPath:(NSIndexPath *)indexPath {
    [(GSKeyTile *)cell play:NO];
}

- (void)collectionView:(UICollectionView *)collectionView didSelectItemAtIndexPath:(NSIndexPath *)indexPath {
    [collectionView deselectItemAtIndexPath:indexPath animated:NO];
    if (indexPath.item >= (NSInteger)_items.count) return;
    GSItem *item = _items[indexPath.item];
    NSURL *gif = [GSStore.shared gifURLForID:item.itemID];
    [[UIImpactFeedbackGenerator new] impactOccurred];
    [self showToast:@"Copying…" lasting:10];
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        // Mapped, so that a large GIF is not read into the keyboard's small memory allowance.
        NSData *data = [NSData dataWithContentsOfURL:gif options:NSDataReadingMappedIfSafe error:NULL];
        if (data.length) [UIPasteboard.generalPasteboard setData:data forPasteboardType:@"com.compuserve.gif"];
        const NSUInteger bytes = data.length;
        data = nil;
        dispatch_async(dispatch_get_main_queue(), ^{
            if (bytes) {
                [[UINotificationFeedbackGenerator new] notificationOccurred:UINotificationFeedbackTypeSuccess];
                [self showToast:@"Copied. Tap the message box, then Paste." lasting:3.2];
            } else {
                [self showToast:@"That GIF's file is missing." lasting:2.5];
            }
            GSKeyLog(@"copy", @{@"bytes": @(bytes), @"id": item.itemID});
        });
    });
}

- (void)showToast:(NSString *)text lasting:(NSTimeInterval)seconds {
    _toast.text = text;
    [NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(hideToast) object:nil];
    [UIView animateWithDuration:0.18 animations:^{ self->_toast.alpha = 1; }];
    [self performSelector:@selector(hideToast) withObject:nil afterDelay:seconds];
}

- (void)hideToast {
    [UIView animateWithDuration:0.3 animations:^{ self->_toast.alpha = 0; }];
}

@end
