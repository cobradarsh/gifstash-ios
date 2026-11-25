// "GIF Stash" in the share sheet: saves the GIF or video of the shared post without leaving the app it came from.
#import <UIKit/UIKit.h>
#import "GSCommon.h"
#import "GSImporter.h"
#import "GSLoopView.h"
#import "GSStore.h"

@interface ShareViewController : UIViewController
@end

@implementation ShareViewController {
    UIVisualEffectView *_card;
    GSLoopView *_loop;
    UILabel *_title;
    UILabel *_status;
    UIProgressView *_progress;
    UIButton *_copy;
    UIButton *_done;
    GSImporter *_importer;
    NSArray<GSItem *> *_saved;
    BOOL _started;
    BOOL _finished;
    BOOL _touched;
    BOOL _closed;
}

static UIColor *GSShareTint(void) {
    return [UIColor colorWithRed:1.00 green:0.33 blue:0.55 alpha:1.0];
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.overrideUserInterfaceStyle = UIUserInterfaceStyleDark;
    self.view.backgroundColor = [UIColor colorWithWhite:0 alpha:0.55];
    self.view.tintColor = GSShareTint();
    [GSLoopView useQuietAudio];
    _importer = [GSImporter new];

    _card = [[UIVisualEffectView alloc] initWithEffect:[UIBlurEffect effectWithStyle:UIBlurEffectStyleSystemThickMaterialDark]];
    _card.layer.cornerRadius = 30;
    _card.layer.cornerCurve = kCACornerCurveContinuous;
    _card.layer.borderColor = [UIColor colorWithWhite:1 alpha:0.10].CGColor;
    _card.layer.borderWidth = 1.0 / UIScreen.mainScreen.scale;
    _card.clipsToBounds = YES;
    [self.view addSubview:_card];

    _loop = [GSLoopView new];
    _loop.fills = NO;
    _loop.backgroundColor = UIColor.blackColor;
    _loop.layer.cornerRadius = 18;
    _loop.layer.cornerCurve = kCACornerCurveContinuous;
    _loop.hidden = YES;
    [_card.contentView addSubview:_loop];

    _title = [UILabel new];
    _title.text = @"GIF Stash";
    _title.font = [UIFont systemFontOfSize:20 weight:UIFontWeightBold];
    _title.textColor = UIColor.whiteColor;
    _title.textAlignment = NSTextAlignmentCenter;
    [_card.contentView addSubview:_title];

    _status = [UILabel new];
    _status.text = @"Reading the post…";
    _status.font = [UIFont systemFontOfSize:15 weight:UIFontWeightMedium];
    _status.textColor = [UIColor colorWithWhite:1 alpha:0.72];
    _status.textAlignment = NSTextAlignmentCenter;
    _status.numberOfLines = 4;
    [_card.contentView addSubview:_status];

    _progress = [[UIProgressView alloc] initWithProgressViewStyle:UIProgressViewStyleDefault];
    _progress.progressTintColor = GSShareTint();
    _progress.trackTintColor = [UIColor colorWithWhite:1 alpha:0.14];
    _progress.progress = 0.03f;
    [_card.contentView addSubview:_progress];

    UIButtonConfiguration *copy = UIButtonConfiguration.tintedButtonConfiguration;
    copy.title = @"Copy GIF";
    copy.image = [UIImage systemImageNamed:@"doc.on.doc"];
    copy.imagePadding = 6;
    copy.cornerStyle = UIButtonConfigurationCornerStyleLarge;
    _copy = [UIButton buttonWithConfiguration:copy primaryAction:nil];
    [_copy addTarget:self action:@selector(tappedCopy) forControlEvents:UIControlEventTouchUpInside];
    _copy.hidden = YES;
    [_card.contentView addSubview:_copy];

    UIButtonConfiguration *done = UIButtonConfiguration.filledButtonConfiguration;
    done.title = @"Cancel";
    done.cornerStyle = UIButtonConfigurationCornerStyleLarge;
    done.baseBackgroundColor = [UIColor colorWithWhite:1 alpha:0.16];
    done.baseForegroundColor = UIColor.whiteColor;
    _done = [UIButton buttonWithConfiguration:done primaryAction:nil];
    [_done addTarget:self action:@selector(tappedDone) forControlEvents:UIControlEventTouchUpInside];
    [_card.contentView addSubview:_done];

    [_card addGestureRecognizer:[[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(touchedCard)]];
}

- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    const CGRect bounds = self.view.bounds;
    const CGFloat width = MIN(bounds.size.width - 32, 380), inner = width - 40;
    CGFloat y = 22;
    if (!_loop.hidden) {
        const double aspect = _saved.firstObject ? _saved.firstObject.aspect : 1.0;
        CGFloat clipH = MIN(inner * aspect, MIN(300, bounds.size.height * 0.36));
        CGFloat clipW = MIN(inner, clipH / MAX(0.01, aspect));
        _loop.frame = CGRectMake(round((width - clipW) / 2), y, round(clipW), round(clipH));
        y += clipH + 16;
    }
    _title.frame = CGRectMake(20, y, inner, 26);
    y += 26 + 6;
    const CGSize statusSize = [_status sizeThatFits:CGSizeMake(inner, 120)];
    _status.frame = CGRectMake(20, y, inner, statusSize.height);
    y += statusSize.height + 14;
    if (!_progress.hidden) {
        _progress.frame = CGRectMake(20, y, inner, 4);
        y += 4 + 18;
    }
    if (_copy.hidden) {
        _done.frame = CGRectMake(20, y, inner, 48);
    } else {
        const CGFloat half = floor((inner - 10) / 2);
        _copy.frame = CGRectMake(20, y, half, 48);
        _done.frame = CGRectMake(20 + half + 10, y, inner - half - 10, 48);
    }
    y += 48 + 20;
    _card.frame = CGRectMake(round((bounds.size.width - width) / 2), round(MAX(40, (bounds.size.height - y) * 0.42)), width, y);
}

- (void)viewDidAppear:(BOOL)animated {
    [super viewDidAppear:animated];
    if (_started) return;
    _started = YES;
    [self collectText:^(NSString *text) { [self beginWith:text]; }];
}

/// Everything textual the sharing app handed over: the link, and any words around it.
- (void)collectText:(void (^)(NSString *text))done {
    NSMutableArray<NSString *> *pieces = [NSMutableArray new];
    dispatch_group_t group = dispatch_group_create();
    for (NSExtensionItem *item in self.extensionContext.inputItems) {
        if (item.attributedContentText.string.length) [pieces addObject:item.attributedContentText.string];
        for (NSItemProvider *provider in item.attachments) {
            for (NSString *type in @[@"public.url", @"public.plain-text"]) {
                if (![provider hasItemConformingToTypeIdentifier:type]) continue;
                dispatch_group_enter(group);
                [provider loadItemForTypeIdentifier:type options:nil completionHandler:^(id<NSSecureCoding> value, NSError *error) {
                    NSString *text = nil;
                    if ([(id)value isKindOfClass:NSURL.class]) text = [(NSURL *)value absoluteString];
                    else if ([(id)value isKindOfClass:NSString.class]) text = (NSString *)value;
                    else if ([(id)value isKindOfClass:NSData.class]) text = [[NSString alloc] initWithData:(NSData *)value encoding:NSUTF8StringEncoding];
                    dispatch_async(dispatch_get_main_queue(), ^{
                        if (text.length) [pieces addObject:text];
                        dispatch_group_leave(group);
                    });
                }];
            }
        }
    }
    dispatch_group_notify(group, dispatch_get_main_queue(), ^{
        done([pieces componentsJoinedByString:@"\n"]);
    });
}

- (void)beginWith:(NSString *)text {
    if (!GSStore.shared.usesGroup) {
        [self fail:@"GIF Stash cannot reach its library from here. Open the GIF Stash app once, then try again."];
        return;
    }
    __weak typeof(self) weakSelf = self;
    [_importer importText:text progress:^(NSString *stage, double fraction) {
        typeof(self) strongSelf = weakSelf;
        if (!strongSelf || strongSelf->_finished) return;
        strongSelf->_status.text = stage;
        [strongSelf->_progress setProgress:(float)MAX(0.03, MIN(1.0, fraction)) animated:fraction > 0.03];
        [strongSelf.view setNeedsLayout];
    } completion:^(NSArray<GSItem *> *items, NSError *error) {
        typeof(self) strongSelf = weakSelf;
        if (!strongSelf) return;
        if (error) [strongSelf fail:error.localizedDescription];
        else [strongSelf succeed:items];
    }];
}

- (void)setDoneTitle:(NSString *)title {
    UIButtonConfiguration *configuration = _done.configuration;
    configuration.title = title;
    _done.configuration = configuration;
}

- (void)fail:(NSString *)message {
    _finished = YES;
    _title.text = @"Not saved";
    _status.text = message;
    _progress.hidden = YES;
    [self setDoneTitle:@"Close"];
    [[UINotificationFeedbackGenerator new] notificationOccurred:UINotificationFeedbackTypeError];
    [self.view setNeedsLayout];
}

- (void)succeed:(NSArray<GSItem *> *)items {
    _finished = YES;
    _saved = items;
    GSItem *first = items.firstObject;
    long long bytes = 0;
    for (GSItem *item in items) bytes += item.gifBytes;
    _title.text = items.count > 1 ? [NSString stringWithFormat:@"Saved %lu clips", (unsigned long)items.count] : @"Saved to GIF Stash";
    _status.text = [NSString stringWithFormat:@"GIF %@  ·  %ld × %ld  ·  %.1f s", GSByteString(bytes), (long)first.width,
                    (long)first.height, first.gifDuration];
    _progress.hidden = YES;
    _copy.hidden = NO;
    [self setDoneTitle:@"Done"];
    _loop.hidden = NO;
    _loop.poster = [UIImage imageWithContentsOfFile:[GSStore.shared posterURLForID:first.itemID].path];
    _loop.videoURL = [GSStore.shared videoURLForID:first.itemID];
    [[UINotificationFeedbackGenerator new] notificationOccurred:UINotificationFeedbackTypeSuccess];
    [UIView animateWithDuration:0.3 delay:0 usingSpringWithDamping:0.86 initialSpringVelocity:0 options:0 animations:^{
        [self.view setNeedsLayout];
        [self.view layoutIfNeeded];
    } completion:nil];
    // Closes by itself unless the card was touched.
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(2.6 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        if (!self->_touched) [self close];
    });
}

- (void)touchedCard { _touched = YES; }

- (void)tappedCopy {
    _touched = YES;
    GSItem *first = _saved.firstObject;
    NSData *data = first ? [NSData dataWithContentsOfURL:[GSStore.shared gifURLForID:first.itemID]] : nil;
    if (!data.length) return;
    [UIPasteboard.generalPasteboard setData:data forPasteboardType:@"com.compuserve.gif"];
    [[UINotificationFeedbackGenerator new] notificationOccurred:UINotificationFeedbackTypeSuccess];
    _status.text = @"Copied. Paste it into any chat.";
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.9 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{ [self close]; });
}

- (void)tappedDone {
    _touched = YES;
    [self close];
}

- (void)close {
    if (_closed) return;
    _closed = YES;
    _loop.videoURL = nil;
    if (_saved.count || _finished) {
        [self.extensionContext completeRequestReturningItems:@[] completionHandler:nil];
    } else {
        [self.extensionContext cancelRequestWithError:GSMakeError(GSErrorCancelled, @"Cancelled")];
    }
}

@end
