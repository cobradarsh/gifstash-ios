#import "GSDetailViewController.h"
#import "GSActions.h"
#import "GSAppDelegate.h"
#import "GSCommon.h"
#import "GSGifCell.h"
#import "GSGifMaker.h"
#import "GSLoopView.h"

@implementation GSDetailViewController {
    GSLoopView *_loop;
    UILabel *_caption;
    UILabel *_facts;
    UIButton *_share;
    UIButton *_copy;
    UIButton *_favorite;
    UIButton *_video;
    UIButton *_more;
    UIActivityIndicatorView *_spinner;
    BOOL _remaking;
}

- (instancetype)initWithItem:(GSItem *)item {
    if ((self = [super initWithNibName:nil bundle:nil])) {
        _item = item;
        self.modalPresentationStyle = UIModalPresentationPageSheet;
        UISheetPresentationController *sheet = self.sheetPresentationController;
        sheet.detents = @[UISheetPresentationControllerDetent.largeDetent];
        sheet.prefersGrabberVisible = YES;
        sheet.preferredCornerRadius = 30;
    }
    return self;
}

static UIButton *GSBigButton(NSString *title, NSString *symbol, BOOL filled) {
    UIButtonConfiguration *configuration = filled ? UIButtonConfiguration.filledButtonConfiguration
                                                  : UIButtonConfiguration.tintedButtonConfiguration;
    configuration.title = title;
    configuration.image = [UIImage systemImageNamed:symbol];
    configuration.imagePadding = 8;
    configuration.cornerStyle = UIButtonConfigurationCornerStyleLarge;
    configuration.buttonSize = UIButtonConfigurationSizeLarge;
    configuration.titleTextAttributesTransformer = ^NSDictionary<NSAttributedStringKey, id> *(NSDictionary<NSAttributedStringKey, id> *incoming) {
        NSMutableDictionary *out = [incoming mutableCopy];
        out[NSFontAttributeName] = [UIFont systemFontOfSize:17 weight:UIFontWeightSemibold];
        return out;
    };
    return [UIButton buttonWithConfiguration:configuration primaryAction:nil];
}

static UIButton *GSSmallButton(NSString *title, NSString *symbol) {
    UIButtonConfiguration *configuration = UIButtonConfiguration.grayButtonConfiguration;
    configuration.title = title;
    configuration.image = [UIImage systemImageNamed:symbol];
    configuration.imagePlacement = NSDirectionalRectEdgeTop;
    configuration.imagePadding = 6;
    configuration.cornerStyle = UIButtonConfigurationCornerStyleLarge;
    configuration.baseForegroundColor = UIColor.labelColor;
    configuration.contentInsets = NSDirectionalEdgeInsetsMake(12, 4, 10, 4);
    configuration.titleTextAttributesTransformer = ^NSDictionary<NSAttributedStringKey, id> *(NSDictionary<NSAttributedStringKey, id> *incoming) {
        NSMutableDictionary *out = [incoming mutableCopy];
        out[NSFontAttributeName] = [UIFont systemFontOfSize:12 weight:UIFontWeightMedium];
        return out;
    };
    return [UIButton buttonWithConfiguration:configuration primaryAction:nil];
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = [UIColor colorWithWhite:0.06 alpha:1.0];
    self.view.tintColor = GSTint();

    _loop = [GSLoopView new];
    _loop.fills = NO;
    _loop.backgroundColor = UIColor.blackColor;
    _loop.layer.cornerRadius = 20;
    _loop.layer.cornerCurve = kCACornerCurveContinuous;
    [self.view addSubview:_loop];

    _spinner = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleLarge];
    _spinner.hidesWhenStopped = YES;
    _spinner.color = UIColor.whiteColor;
    [self.view addSubview:_spinner];

    _caption = [UILabel new];
    _caption.font = [UIFont systemFontOfSize:15 weight:UIFontWeightRegular];
    _caption.textColor = UIColor.labelColor;
    _caption.numberOfLines = 3;
    [self.view addSubview:_caption];

    _facts = [UILabel new];
    _facts.font = [UIFont monospacedDigitSystemFontOfSize:12.5 weight:UIFontWeightRegular];
    _facts.textColor = UIColor.secondaryLabelColor;
    _facts.numberOfLines = 2;
    [self.view addSubview:_facts];

    _share = GSBigButton(@"Share GIF", @"square.and.arrow.up", YES);
    [_share addTarget:self action:@selector(tappedShare) forControlEvents:UIControlEventTouchUpInside];
    _copy = GSBigButton(@"Copy GIF", @"doc.on.doc", NO);
    [_copy addTarget:self action:@selector(tappedCopy) forControlEvents:UIControlEventTouchUpInside];
    _favorite = GSSmallButton(@"Favourite", @"star");
    [_favorite addTarget:self action:@selector(tappedFavorite) forControlEvents:UIControlEventTouchUpInside];
    _video = GSSmallButton(@"As Video", @"film");
    [_video addTarget:self action:@selector(tappedVideo) forControlEvents:UIControlEventTouchUpInside];
    _more = GSSmallButton(@"More", @"ellipsis");
    _more.showsMenuAsPrimaryAction = YES;
    for (UIButton *button in @[_share, _copy, _favorite, _video, _more]) [self.view addSubview:button];

    [self refresh];
    GSItem *item = self.item;
    __weak typeof(self) weakSelf = self;
    GSLoadPoster(item, ^(UIImage *image) {
        typeof(self) strongSelf = weakSelf;
        if (strongSelf) strongSelf->_loop.poster = image;
    });
    _loop.videoURL = [GSStore.shared videoURLForID:item.itemID];
}

- (void)refresh {
    GSItem *item = self.item;
    NSMutableArray<NSString *> *lines = [NSMutableArray new];
    if (item.label.length) [lines addObject:item.label];
    if (item.author.length) [lines addObject:[@"@" stringByAppendingString:item.author]];
    if (item.text.length) [lines addObject:item.text];
    _caption.text = [lines componentsJoinedByString:@"  ·  "];
    NSString *facts = [GSActions summaryOf:item];
    if (item.trimmed) facts = [facts stringByAppendingFormat:@"\nThe GIF covers the first %.0f seconds; the video is whole.", GSGifMaxSeconds];
    _facts.text = facts;

    UIButtonConfiguration *configuration = _favorite.configuration;
    configuration.image = [UIImage systemImageNamed:item.favorite ? @"star.fill" : @"star"];
    configuration.baseForegroundColor = item.favorite ? [UIColor colorWithRed:1.0 green:0.80 blue:0.20 alpha:1.0] : UIColor.labelColor;
    _favorite.configuration = configuration;
    _more.menu = [self moreMenu];
    [self.view setNeedsLayout];
}

- (UIMenu *)moreMenu {
    __weak typeof(self) weakSelf = self;
    GSItem *item = self.item;
    NSMutableArray<UIMenuElement *> *quality = [NSMutableArray new];
    NSArray<NSString *> *notes = @[@"320 px, smallest file", @"480 px, good for chats", @"640 px, smoothest"];
    for (NSInteger preset = 0; preset <= 2; preset++) {
        UIAction *action = [UIAction actionWithTitle:GSGifPresetName((GSGifPreset)preset) image:nil identifier:nil
                                             handler:^(UIAction *chosen) { [weakSelf remakeWithPreset:preset]; }];
        action.subtitle = notes[preset];
        action.state = item.preset == preset ? UIMenuElementStateOn : UIMenuElementStateOff;
        [quality addObject:action];
    }
    UIMenu *remake = [UIMenu menuWithTitle:@"Remake GIF" image:[UIImage systemImageNamed:@"wand.and.stars"] identifier:nil
                                   options:0 children:quality];
    UIAction *name = [UIAction actionWithTitle:@"Name…" image:[UIImage systemImageNamed:@"pencil"] identifier:nil
                                       handler:^(UIAction *action) {
        typeof(self) strongSelf = weakSelf;
        if (strongSelf) [GSActions rename:item from:strongSelf done:^{ [weakSelf refresh]; }];
    }];
    NSMutableArray<UIMenuElement *> *children = [NSMutableArray arrayWithObjects:remake, name, nil];
    if (item.tweetID || item.sourceURL) {
        [children addObject:[UIAction actionWithTitle:@"Open Post" image:[UIImage systemImageNamed:@"arrow.up.right.square"]
                                           identifier:nil handler:^(UIAction *action) { [GSActions openPost:item]; }]];
    }
    UIAction *delete = [UIAction actionWithTitle:@"Delete" image:[UIImage systemImageNamed:@"trash"] identifier:nil
                                         handler:^(UIAction *action) {
        typeof(self) strongSelf = weakSelf;
        if (strongSelf) [GSActions confirmDelete:item from:strongSelf done:^{ [weakSelf dismissViewControllerAnimated:YES completion:nil]; }];
    }];
    delete.attributes = UIMenuElementAttributesDestructive;
    [children addObject:delete];
    return [UIMenu menuWithTitle:@"" children:children];
}

- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    const CGRect bounds = self.view.bounds;
    const UIEdgeInsets safe = self.view.safeAreaInsets;
    const CGFloat side = 16, width = bounds.size.width - side * 2;

    // From the bottom up: small buttons, large buttons, facts, caption; the clip takes what is left.
    CGFloat y = bounds.size.height - MAX(safe.bottom, 12) - 8;
    const CGFloat small = 64, gap = 10;
    const CGFloat third = floor((width - gap * 2) / 3);
    y -= small;
    _favorite.frame = CGRectMake(side, y, third, small);
    _video.frame = CGRectMake(side + third + gap, y, third, small);
    _more.frame = CGRectMake(side + (third + gap) * 2, y, width - (third + gap) * 2, small);
    y -= gap + 54;
    const CGFloat half = floor((width - gap) / 2);
    _share.frame = CGRectMake(side, y, half, 54);
    _copy.frame = CGRectMake(side + half + gap, y, width - half - gap, 54);

    const CGSize factsSize = [_facts sizeThatFits:CGSizeMake(width, 80)];
    y -= 14 + factsSize.height;
    _facts.frame = CGRectMake(side, y, width, factsSize.height);
    if (_caption.text.length) {
        const CGSize captionSize = [_caption sizeThatFits:CGSizeMake(width, 80)];
        y -= 6 + captionSize.height;
        _caption.frame = CGRectMake(side, y, width, captionSize.height);
    } else {
        _caption.frame = CGRectZero;
    }

    const CGFloat top = MAX(safe.top, 0) + 26;
    const CGFloat room = MAX(80, y - 16 - top);
    CGFloat clipW = width, clipH = width * self.item.aspect;
    if (clipH > room) { clipH = room; clipW = MIN(width, room / MAX(0.01, self.item.aspect)); }
    _loop.frame = CGRectMake(round((bounds.size.width - clipW) / 2), round(top + (room - clipH) / 2), round(clipW), round(clipH));
    _spinner.center = _loop.center;
}

- (void)tappedShare { [GSActions shareGIF:self.item from:self view:_share]; }
- (void)tappedVideo { [GSActions shareVideo:self.item from:self view:_video]; }
- (void)tappedCopy { [GSActions copyGIF:self.item]; }

- (void)tappedFavorite {
    [GSActions toggleFavorite:self.item];
    [self refresh];
}

- (void)remakeWithPreset:(NSInteger)preset {
    if (_remaking) return;
    _remaking = YES;
    [_spinner startAnimating];
    _share.enabled = _copy.enabled = NO;
    GSItem *item = self.item;
    GSStore *store = GSStore.shared;
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        NSURL *gif = [store gifURLForID:item.itemID];
        NSURL *part = [gif URLByAppendingPathExtension:@"part"];
        NSError *error = nil;
        GSGifResult *result = [GSGifMaker makeGIFAtURL:part fromVideo:[store videoURLForID:item.itemID] preset:(GSGifPreset)preset
                                             posterURL:nil progress:nil error:&error];
        if (result) {
            NSFileManager *files = NSFileManager.defaultManager;
            [files removeItemAtURL:gif error:NULL];
            if (![files moveItemAtURL:part toURL:gif error:&error]) result = nil;
        }
        dispatch_async(dispatch_get_main_queue(), ^{
            self->_remaking = NO;
            [self->_spinner stopAnimating];
            self->_share.enabled = self->_copy.enabled = YES;
            if (!result) {
                [GSActions toast:error.localizedDescription ?: @"The GIF could not be remade"];
                return;
            }
            item.width = result.width;
            item.height = result.height;
            item.frames = result.frames;
            item.gifDuration = result.duration;
            item.gifBytes = result.bytes;
            item.preset = preset;
            [store saveItem:item];
            [self refresh];
            [GSActions toast:[NSString stringWithFormat:@"%@ GIF, %@", GSGifPresetName((GSGifPreset)preset), GSByteString(result.bytes)]];
        });
    });
}

@end
