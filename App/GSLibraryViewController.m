#import "GSLibraryViewController.h"
#import "GSActions.h"
#import "GSAppDelegate.h"
#import "GSCommon.h"
#import "GSDetailViewController.h"
#import "GSGifCell.h"
#import "GSGifMaker.h"
#import "GSImporter.h"
#import "GSWaterfallLayout.h"

static NSString *const kCell = @"clip";
static NSString *const kHowTo =
    @"In X, hold a GIF or video, choose “Share via…” and pick GIF Stash. The clip is saved without leaving X.\n\n"
    @"If GIF Stash is not in the row of apps, scroll that row to the end, tap More and switch it on.\n\n"
    @"Or copy a post's link and tap + here.";

@interface GSLibraryViewController () <UICollectionViewDataSource, UICollectionViewDelegate, UICollectionViewDragDelegate,
                                       UISearchResultsUpdating, GSWaterfallSource>
@end

@implementation GSLibraryViewController {
    UICollectionView *_collection;
    GSWaterfallLayout *_layout;
    UISearchController *_search;
    UIView *_empty;
    UILabel *_emptyTitle;
    UILabel *_emptyText;
    UIButton *_emptyButton;

    UIVisualEffectView *_banner;
    UILabel *_bannerLabel;
    UIProgressView *_bannerProgress;
    UIButton *_bannerAction;
    UIButton *_bannerClose;
    BOOL _bannerOffersClipboard;

    NSArray<GSItem *> *_allItems;
    NSArray<GSItem *> *_shownItems;
    BOOL _favoritesOnly;
    GSImporter *_importer;
    BOOL _importing;
    NSInteger _clipboardSeen;
}

- (NSArray<GSItem *> *)shownItems { return _shownItems ?: @[]; }
- (BOOL)isImporting { return _importing; }

#pragma mark - Building

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"GIF Stash";
    self.view.backgroundColor = UIColor.blackColor;
    self.navigationItem.largeTitleDisplayMode = UINavigationItemLargeTitleDisplayModeAlways;
    _importer = [GSImporter new];
    _allItems = @[];
    _shownItems = @[];
    _clipboardSeen = [NSUserDefaults.standardUserDefaults integerForKey:@"clipboardSeen"];

    _layout = [GSWaterfallLayout new];
    _layout.source = self;
    _collection = [[UICollectionView alloc] initWithFrame:self.view.bounds collectionViewLayout:_layout];
    _collection.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    _collection.backgroundColor = UIColor.blackColor;
    _collection.alwaysBounceVertical = YES;
    _collection.keyboardDismissMode = UIScrollViewKeyboardDismissModeOnDrag;
    _collection.dataSource = self;
    _collection.delegate = self;
    _collection.dragDelegate = self;
    _collection.dragInteractionEnabled = YES;
    _collection.contentInset = UIEdgeInsetsMake(0, 0, 76, 0);
    [_collection registerClass:GSGifCell.class forCellWithReuseIdentifier:kCell];
    [self.view addSubview:_collection];

    _search = [[UISearchController alloc] initWithSearchResultsController:nil];
    _search.obscuresBackgroundDuringPresentation = NO;
    _search.searchResultsUpdater = self;
    _search.searchBar.placeholder = @"Name, account or words of the post";
    self.navigationItem.searchController = _search;
    self.navigationItem.hidesSearchBarWhenScrolling = YES;
    self.definesPresentationContext = YES;

    [self buildEmptyView];
    [self buildBanner];
    [self updateBarButtons];

    NSNotificationCenter *center = NSNotificationCenter.defaultCenter;
    [center addObserver:self selector:@selector(storeChanged) name:GSStoreChangedNotification object:nil];
    [center addObserver:self selector:@selector(becameActive) name:UIApplicationDidBecomeActiveNotification object:nil];
    [center addObserver:self selector:@selector(wentToBackground) name:UIApplicationDidEnterBackgroundNotification object:nil];
    [self reload];
}

- (void)updateBarButtons {
    UIBarButtonItem *add = [[UIBarButtonItem alloc] initWithImage:[UIImage systemImageNamed:@"plus"] style:UIBarButtonItemStylePlain
                                                           target:self action:@selector(pasteTapped)];
    add.accessibilityLabel = @"Save from copied link";
    __weak typeof(self) weakSelf = self;
    UIDeferredMenuElement *live = [UIDeferredMenuElement elementWithUncachedProvider:^(void (^completion)(NSArray<UIMenuElement *> *)) {
        completion([weakSelf menuElements] ?: @[]);
    }];
    UIBarButtonItem *more = [[UIBarButtonItem alloc] initWithImage:[UIImage systemImageNamed:@"ellipsis.circle"]
                                                              menu:[UIMenu menuWithTitle:@"" children:@[live]]];
    more.accessibilityLabel = @"Options";
    self.navigationItem.rightBarButtonItems = @[add, more];

    UIBarButtonItem *star = [[UIBarButtonItem alloc] initWithImage:[UIImage systemImageNamed:_favoritesOnly ? @"star.fill" : @"star"]
                                                             style:UIBarButtonItemStylePlain target:self action:@selector(toggleFavorites)];
    star.accessibilityLabel = _favoritesOnly ? @"Show all clips" : @"Show favourites only";
    star.tintColor = _favoritesOnly ? [UIColor colorWithRed:1.0 green:0.80 blue:0.20 alpha:1.0] : nil;
    self.navigationItem.leftBarButtonItem = star;
}

- (NSArray<UIMenuElement *> *)menuElements {
    GSStore *store = GSStore.shared;
    NSMutableArray<UIMenuElement *> *quality = [NSMutableArray new];
    NSArray<NSString *> *notes = @[@"320 px, smallest files", @"480 px, good for chats", @"640 px, smoothest, largest"];
    for (NSInteger preset = 0; preset <= 2; preset++) {
        UIAction *action = [UIAction actionWithTitle:GSGifPresetName((GSGifPreset)preset) image:nil identifier:nil
                                             handler:^(UIAction *chosen) { GSStore.shared.preset = preset; }];
        action.subtitle = notes[preset];
        action.state = store.preset == preset ? UIMenuElementStateOn : UIMenuElementStateOff;
        [quality addObject:action];
    }
    UIMenu *qualityMenu = [UIMenu menuWithTitle:@"GIF quality for new clips" image:nil identifier:nil
                                        options:UIMenuOptionsDisplayInline children:quality];
    __weak typeof(self) weakSelf = self;
    UIAction *keyboard = [UIAction actionWithTitle:@"Set up the GIF keyboard" image:[UIImage systemImageNamed:@"keyboard"]
                                        identifier:nil handler:^(UIAction *action) { [weakSelf showKeyboardSetup]; }];
    UIAction *plays = [UIAction actionWithTitle:@"Keyboard plays clips" image:nil identifier:nil handler:^(UIAction *action) {
        GSStore.shared.keyboardAnimates = !GSStore.shared.keyboardAnimates;
    }];
    plays.state = store.keyboardAnimates ? UIMenuElementStateOn : UIMenuElementStateOff;
    UIMenu *keyboardMenu = [UIMenu menuWithTitle:@"" image:nil identifier:nil options:UIMenuOptionsDisplayInline children:@[keyboard, plays]];
    UIAction *how = [UIAction actionWithTitle:@"How to save a GIF" image:[UIImage systemImageNamed:@"questionmark.circle"]
                                   identifier:nil handler:^(UIAction *action) { [weakSelf showHowTo]; }];
    NSString *size = [NSString stringWithFormat:@"%lu clips  ·  %@", (unsigned long)_allItems.count, GSByteString(store.totalBytes)];
    UIAction *storage = [UIAction actionWithTitle:size image:[UIImage systemImageNamed:@"internaldrive"] identifier:nil
                                          handler:^(UIAction *action) {}];
    storage.attributes = UIMenuElementAttributesDisabled;
    return @[qualityMenu, keyboardMenu, how, storage];
}

- (void)showHowTo {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Saving a GIF" message:kHowTo preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
    [self presentViewController:alert animated:YES completion:nil];
}

- (void)showKeyboardSetup {
    NSString *steps = @"1. Tap Open Settings, then Keyboards.\n2. Switch on GIF Stash, then Allow Full Access.\n"
                      @"3. In any chat, hold the globe key and choose GIF Stash.\n4. Tap a GIF, tap the message box, tap Paste.\n\n"
                      @"Full Access is what lets the keyboard read your library and put a GIF on the clipboard. "
                      @"It has no letter keys and does not use the network.";
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"GIF keyboard" message:steps preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"Not now" style:UIAlertActionStyleCancel handler:nil]];
    [alert addAction:[UIAlertAction actionWithTitle:@"Open Settings" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
        [UIApplication.sharedApplication openURL:[NSURL URLWithString:UIApplicationOpenSettingsURLString] options:@{} completionHandler:nil];
    }]];
    [self presentViewController:alert animated:YES completion:nil];
}

- (void)buildEmptyView {
    _empty = [[UIView alloc] initWithFrame:self.view.bounds];
    _empty.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;

    UIImageView *symbol = [[UIImageView alloc] initWithImage:
        [UIImage systemImageNamed:@"square.stack.3d.up.fill"
                withConfiguration:[UIImageSymbolConfiguration configurationWithPointSize:56 weight:UIImageSymbolWeightSemibold]]];
    symbol.tintColor = GSTint();
    symbol.contentMode = UIViewContentModeCenter;

    _emptyTitle = [UILabel new];
    _emptyTitle.font = [UIFont systemFontOfSize:24 weight:UIFontWeightBold];
    _emptyTitle.textColor = UIColor.labelColor;
    _emptyTitle.textAlignment = NSTextAlignmentCenter;

    _emptyText = [UILabel new];
    _emptyText.font = [UIFont systemFontOfSize:16];
    _emptyText.textColor = UIColor.secondaryLabelColor;
    _emptyText.textAlignment = NSTextAlignmentCenter;
    _emptyText.numberOfLines = 0;

    UIButtonConfiguration *configuration = UIButtonConfiguration.filledButtonConfiguration;
    configuration.title = @"Save from copied link";
    configuration.image = [UIImage systemImageNamed:@"link"];
    configuration.imagePadding = 8;
    configuration.cornerStyle = UIButtonConfigurationCornerStyleCapsule;
    configuration.buttonSize = UIButtonConfigurationSizeLarge;
    _emptyButton = [UIButton buttonWithConfiguration:configuration primaryAction:nil];
    [_emptyButton addTarget:self action:@selector(pasteTapped) forControlEvents:UIControlEventTouchUpInside];

    UIStackView *stack = [[UIStackView alloc] initWithArrangedSubviews:@[symbol, _emptyTitle, _emptyText, _emptyButton]];
    stack.axis = UILayoutConstraintAxisVertical;
    stack.alignment = UIStackViewAlignmentCenter;
    stack.spacing = 14;
    [stack setCustomSpacing:22 afterView:_emptyText];
    stack.translatesAutoresizingMaskIntoConstraints = NO;
    [_empty addSubview:stack];
    [NSLayoutConstraint activateConstraints:@[
        [stack.centerXAnchor constraintEqualToAnchor:_empty.centerXAnchor],
        [stack.centerYAnchor constraintEqualToAnchor:_empty.centerYAnchor constant:10],
        [stack.widthAnchor constraintLessThanOrEqualToAnchor:_empty.widthAnchor constant:-56],
    ]];
}

- (void)buildBanner {
    _banner = [[UIVisualEffectView alloc] initWithEffect:[UIBlurEffect effectWithStyle:UIBlurEffectStyleSystemThickMaterialDark]];
    _banner.layer.cornerRadius = 22;
    _banner.layer.cornerCurve = kCACornerCurveContinuous;
    _banner.layer.borderColor = [UIColor colorWithWhite:1 alpha:0.10].CGColor;
    _banner.layer.borderWidth = 1.0 / UIScreen.mainScreen.scale;
    _banner.clipsToBounds = YES;
    _banner.alpha = 0;
    _banner.hidden = YES;
    [self.view addSubview:_banner];

    _bannerLabel = [UILabel new];
    _bannerLabel.font = [UIFont systemFontOfSize:15 weight:UIFontWeightSemibold];
    _bannerLabel.textColor = UIColor.whiteColor;
    _bannerLabel.adjustsFontSizeToFitWidth = YES;
    _bannerLabel.minimumScaleFactor = 0.8;
    [_banner.contentView addSubview:_bannerLabel];

    _bannerProgress = [[UIProgressView alloc] initWithProgressViewStyle:UIProgressViewStyleDefault];
    _bannerProgress.progressTintColor = GSTint();
    _bannerProgress.trackTintColor = [UIColor colorWithWhite:1 alpha:0.14];
    [_banner.contentView addSubview:_bannerProgress];

    UIButtonConfiguration *save = UIButtonConfiguration.filledButtonConfiguration;
    save.title = @"Save GIF";
    save.cornerStyle = UIButtonConfigurationCornerStyleCapsule;
    save.buttonSize = UIButtonConfigurationSizeSmall;
    _bannerAction = [UIButton buttonWithConfiguration:save primaryAction:nil];
    [_bannerAction addTarget:self action:@selector(pasteTapped) forControlEvents:UIControlEventTouchUpInside];
    [_banner.contentView addSubview:_bannerAction];

    _bannerClose = [UIButton buttonWithType:UIButtonTypeSystem];
    [_bannerClose setImage:[UIImage systemImageNamed:@"xmark"] forState:UIControlStateNormal];
    _bannerClose.tintColor = [UIColor colorWithWhite:1 alpha:0.6];
    [_bannerClose addTarget:self action:@selector(dismissOffer) forControlEvents:UIControlEventTouchUpInside];
    [_banner.contentView addSubview:_bannerClose];
}

- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    const CGRect bounds = self.view.bounds;
    const CGFloat width = bounds.size.width - 24, height = 60;
    // Set through bounds and centre, so that the slide-in transform is left alone.
    _banner.bounds = CGRectMake(0, 0, width, height);
    _banner.center = CGPointMake(bounds.size.width / 2, bounds.size.height - self.view.safeAreaInsets.bottom - 10 - height / 2);
    if (_bannerOffersClipboard) {
        _bannerClose.frame = CGRectMake(width - 44, 8, 40, 44);
        _bannerAction.frame = CGRectMake(width - 44 - 104, 13, 100, 34);
        _bannerLabel.frame = CGRectMake(18, 0, width - 44 - 104 - 26, height);
    } else {
        _bannerLabel.frame = CGRectMake(18, 9, width - 36, 24);
        _bannerProgress.frame = CGRectMake(18, 41, width - 36, 4);
    }
}

#pragma mark - The clips

- (void)storeChanged {
    // The app's own change and the notice that crosses processes can both arrive: one reload does.
    [NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(reload) object:nil];
    [self performSelector:@selector(reload) withObject:nil afterDelay:0.05];
}

- (void)reload {
    _allItems = [GSStore.shared allItems];
    [self applyFilter];
}

- (void)applyFilter {
    NSString *query = [_search.searchBar.text.lowercaseString stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceCharacterSet];
    NSArray<NSString *> *words = query.length ? [query componentsSeparatedByCharactersInSet:NSCharacterSet.whitespaceCharacterSet] : @[];
    NSMutableArray<GSItem *> *shown = [NSMutableArray new];
    for (GSItem *item in _allItems) {
        if (_favoritesOnly && !item.favorite) continue;
        BOOL matches = YES;
        NSString *haystack = words.count ? item.searchText : nil;
        for (NSString *word in words) {
            if (word.length && ![haystack containsString:word]) { matches = NO; break; }
        }
        if (matches) [shown addObject:item];
    }
    _shownItems = shown;
    [_collection reloadData];

    const BOOL empty = shown.count == 0;
    if (empty) {
        if (_allItems.count == 0) {
            _emptyTitle.text = @"No GIFs yet";
            _emptyText.text = @"In X, hold a GIF or video, tap “Share via…” and choose GIF Stash.\nOr copy a post's link and save it here.";
            _emptyButton.hidden = NO;
        } else {
            _emptyTitle.text = _favoritesOnly && !query.length ? @"No favourites yet" : @"Nothing found";
            _emptyText.text = _favoritesOnly && !query.length ? @"Hold a clip and choose Favourite." : @"No clip matches that search.";
            _emptyButton.hidden = YES;
        }
    }
    _collection.backgroundView = empty ? _empty : nil;
}

- (void)toggleFavorites {
    _favoritesOnly = !_favoritesOnly;
    [[UISelectionFeedbackGenerator new] selectionChanged];
    [self updateBarButtons];
    [self applyFilter];
}

- (void)updateSearchResultsForSearchController:(UISearchController *)searchController {
    [self applyFilter];
}

- (CGFloat)waterfallAspectAtIndex:(NSInteger)index {
    return index < (NSInteger)_shownItems.count ? _shownItems[index].aspect : 1;
}

- (NSInteger)collectionView:(UICollectionView *)collectionView numberOfItemsInSection:(NSInteger)section {
    return _shownItems.count;
}

- (UICollectionViewCell *)collectionView:(UICollectionView *)collectionView cellForItemAtIndexPath:(NSIndexPath *)indexPath {
    GSGifCell *cell = [collectionView dequeueReusableCellWithReuseIdentifier:kCell forIndexPath:indexPath];
    [cell showItem:_shownItems[indexPath.item]];
    return cell;
}

- (void)collectionView:(UICollectionView *)collectionView willDisplayCell:(UICollectionViewCell *)cell forItemAtIndexPath:(NSIndexPath *)indexPath {
    if (UIApplication.sharedApplication.applicationState != UIApplicationStateBackground) [(GSGifCell *)cell startPlaying];
}

- (void)collectionView:(UICollectionView *)collectionView didEndDisplayingCell:(UICollectionViewCell *)cell forItemAtIndexPath:(NSIndexPath *)indexPath {
    [(GSGifCell *)cell stopPlaying];
}

- (void)collectionView:(UICollectionView *)collectionView didSelectItemAtIndexPath:(NSIndexPath *)indexPath {
    [collectionView deselectItemAtIndexPath:indexPath animated:NO];
    if (indexPath.item >= (NSInteger)_shownItems.count) return;
    [self presentViewController:[[GSDetailViewController alloc] initWithItem:_shownItems[indexPath.item]] animated:YES completion:nil];
}

- (BOOL)openItemWithID:(NSString *)itemID {
    for (GSItem *item in _allItems) {
        if ([item.itemID isEqualToString:itemID]) {
            [self presentViewController:[[GSDetailViewController alloc] initWithItem:item] animated:YES completion:nil];
            return YES;
        }
    }
    return NO;
}

- (UIContextMenuConfiguration *)collectionView:(UICollectionView *)collectionView
    contextMenuConfigurationForItemAtIndexPath:(NSIndexPath *)indexPath point:(CGPoint)point {
    if (indexPath.item >= (NSInteger)_shownItems.count) return nil;
    GSItem *item = _shownItems[indexPath.item];
    UIView *cell = [collectionView cellForItemAtIndexPath:indexPath];
    __weak typeof(self) weakSelf = self;
    return [UIContextMenuConfiguration configurationWithIdentifier:item.itemID previewProvider:nil
                                                    actionProvider:^UIMenu *(NSArray<UIMenuElement *> *suggested) {
        typeof(self) strongSelf = weakSelf;
        if (!strongSelf) return nil;
        return [GSActions menuForItem:item from:strongSelf view:cell changed:^{ [weakSelf reload]; }];
    }];
}

- (UITargetedPreview *)previewForMenu:(UIContextMenuConfiguration *)configuration {
    NSString *itemID = (NSString *)configuration.identifier;
    for (GSGifCell *cell in _collection.visibleCells) {
        if ([cell.item.itemID isEqualToString:itemID]) {
            UIPreviewParameters *parameters = [UIPreviewParameters new];
            parameters.backgroundColor = UIColor.clearColor;
            parameters.visiblePath = [UIBezierPath bezierPathWithRoundedRect:cell.contentView.bounds cornerRadius:16];
            return [[UITargetedPreview alloc] initWithView:cell.contentView parameters:parameters];
        }
    }
    return nil;
}

- (UITargetedPreview *)collectionView:(UICollectionView *)collectionView
    previewForHighlightingContextMenuWithConfiguration:(UIContextMenuConfiguration *)configuration {
    return [self previewForMenu:configuration];
}

- (UITargetedPreview *)collectionView:(UICollectionView *)collectionView
    previewForDismissingContextMenuWithConfiguration:(UIContextMenuConfiguration *)configuration {
    return [self previewForMenu:configuration];
}

- (NSArray<UIDragItem *> *)collectionView:(UICollectionView *)collectionView itemsForBeginningDragSession:(id<UIDragSession>)session
                              atIndexPath:(NSIndexPath *)indexPath {
    if (indexPath.item >= (NSInteger)_shownItems.count) return @[];
    NSURL *file = [GSActions exportedFileFor:_shownItems[indexPath.item] video:NO];
    NSItemProvider *provider = file ? [[NSItemProvider alloc] initWithContentsOfURL:file] : nil;
    if (!provider) return @[];
    return @[[[UIDragItem alloc] initWithItemProvider:provider]];
}

- (void)wentToBackground {
    for (GSGifCell *cell in _collection.visibleCells) [cell stopPlaying];
}

#pragma mark - Saving from a link

- (void)becameActive {
    [self reload];
    for (GSGifCell *cell in _collection.visibleCells) [cell startPlaying];
    [self lookAtClipboard];
}

/// Offers to save a link that was copied elsewhere. Only asks what kind of thing is on the clipboard, which does
/// not bring up the "allow paste" question; the link itself is read when the offer is taken up.
- (void)lookAtClipboard {
    if (_importing) return;
    UIPasteboard *board = UIPasteboard.generalPasteboard;
    const NSInteger count = board.changeCount;
    if (count == _clipboardSeen) return;
    if (!board.hasURLs && !board.hasStrings) return;
    __weak typeof(self) weakSelf = self;
    [board detectPatternsForPatterns:[NSSet setWithObject:UIPasteboardDetectionPatternProbableWebURL]
                   completionHandler:^(NSSet<UIPasteboardDetectionPattern> *found, NSError *error) {
        if (![found containsObject:UIPasteboardDetectionPatternProbableWebURL]) return;
        dispatch_async(dispatch_get_main_queue(), ^{
            typeof(self) strongSelf = weakSelf;
            if (!strongSelf || strongSelf->_importing) return;
            [strongSelf showBannerOffer:YES text:@"A link is on the clipboard" progress:-1];
        });
    }];
}

- (void)rememberClipboard {
    _clipboardSeen = UIPasteboard.generalPasteboard.changeCount;
    [NSUserDefaults.standardUserDefaults setInteger:_clipboardSeen forKey:@"clipboardSeen"];
}

- (void)dismissOffer {
    [self rememberClipboard];
    [self hideBanner];
}

- (void)pasteTapped {
    if (_importing) return;
    UIPasteboard *board = UIPasteboard.generalPasteboard;
    NSString *text = board.string ?: board.URL.absoluteString;
    [self rememberClipboard];
    if (text.length == 0) {
        [self hideBanner];
        UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"No link copied"
            message:@"Copy a post's link in X first (Share, then Copy Link), then tap + again." preferredStyle:UIAlertControllerStyleAlert];
        [alert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
        [self presentViewController:alert animated:YES completion:nil];
        return;
    }
    [self importText:text];
}

- (void)importText:(NSString *)text {
    [self importText:text quietly:NO completion:nil];
}

- (void)importText:(NSString *)text quietly:(BOOL)quietly
        completion:(void (^)(NSArray<GSItem *> *, NSError *))completion {
    if (_importing) {
        if (completion) completion(@[], GSMakeError(GSErrorCancelled, @"Another clip is still being saved."));
        else [GSActions toast:@"Still saving the last clip"];
        return;
    }
    [self loadViewIfNeeded];
    _importing = YES;
    [self showBannerOffer:NO text:@"Reading the post…" progress:-1];
    __weak typeof(self) weakSelf = self;
    [_importer importText:text progress:^(NSString *stage, double fraction) {
        [weakSelf showBannerOffer:NO text:stage progress:fraction];
    } completion:^(NSArray<GSItem *> *items, NSError *error) {
        typeof(self) strongSelf = weakSelf;
        if (!strongSelf) return;
        strongSelf->_importing = NO;
        if (error) {
            [strongSelf hideBanner];
            [[UINotificationFeedbackGenerator new] notificationOccurred:UINotificationFeedbackTypeError];
            if (!quietly) {
                UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Could not save" message:error.localizedDescription
                                                                        preferredStyle:UIAlertControllerStyleAlert];
                [alert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
                UIViewController *top = strongSelf.presentedViewController ?: strongSelf;
                [top presentViewController:alert animated:YES completion:nil];
            }
        } else {
            [[UINotificationFeedbackGenerator new] notificationOccurred:UINotificationFeedbackTypeSuccess];
            long long bytes = 0;
            for (GSItem *item in items) bytes += item.gifBytes;
            NSString *done = items.count > 1 ? [NSString stringWithFormat:@"Saved %lu clips  ·  %@", (unsigned long)items.count, GSByteString(bytes)]
                                             : [NSString stringWithFormat:@"Saved  ·  %@ GIF", GSByteString(bytes)];
            [strongSelf showBannerOffer:NO text:done progress:1];
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.6 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                if (!weakSelf.isImporting) [weakSelf hideBanner];
            });
            [strongSelf reload];
            if (strongSelf->_shownItems.count) {
                [strongSelf->_collection setContentOffset:CGPointMake(0, -strongSelf->_collection.adjustedContentInset.top) animated:YES];
            }
        }
        if (completion) completion(items, error);
    }];
}

#pragma mark - The banner

- (void)showBannerOffer:(BOOL)offer text:(NSString *)text progress:(double)fraction {
    _bannerOffersClipboard = offer;
    _bannerLabel.text = text;
    _bannerAction.hidden = !offer;
    _bannerClose.hidden = !offer;
    _bannerProgress.hidden = offer;
    if (!offer) [_bannerProgress setProgress:(float)MAX(0.03, MIN(1.0, fraction)) animated:fraction > 0.03];
    [self.view setNeedsLayout];
    if (!_banner.hidden && _banner.alpha > 0.99) return;
    _banner.hidden = NO;
    if (_banner.alpha < 0.01) _banner.transform = CGAffineTransformMakeTranslation(0, 24);
    [UIView animateWithDuration:0.28 delay:0 usingSpringWithDamping:0.85 initialSpringVelocity:0
                        options:UIViewAnimationOptionBeginFromCurrentState animations:^{
        self->_banner.alpha = 1;
        self->_banner.transform = CGAffineTransformIdentity;
    } completion:nil];
}

- (void)hideBanner {
    if (_banner.hidden) return;
    [UIView animateWithDuration:0.22 delay:0 options:UIViewAnimationOptionBeginFromCurrentState animations:^{
        self->_banner.alpha = 0;
        self->_banner.transform = CGAffineTransformMakeTranslation(0, 24);
    } completion:^(BOOL finished) {
        if (self->_banner.alpha < 0.01) self->_banner.hidden = YES;
    }];
}

@end
