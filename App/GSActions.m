#import "GSActions.h"
#import "GSAppDelegate.h"
#import "GSCommon.h"
#import "GSTweet.h"

@implementation GSActions

+ (NSURL *)exportedFileFor:(GSItem *)item video:(BOOL)video {
    GSStore *store = GSStore.shared;
    NSURL *source = video ? [store videoURLForID:item.itemID] : [store gifURLForID:item.itemID];
    NSFileManager *files = NSFileManager.defaultManager;
    if (![files fileExistsAtPath:source.path]) return nil;
    NSURL *folder = [[NSURL fileURLWithPath:NSTemporaryDirectory()] URLByAppendingPathComponent:@"Share" isDirectory:YES];
    [files removeItemAtURL:folder error:NULL];
    [files createDirectoryAtURL:folder withIntermediateDirectories:YES attributes:nil error:NULL];

    NSString *base = item.label ?: (item.author ?: @"clip");
    NSMutableString *clean = [NSMutableString new];
    for (NSUInteger i = 0; i < base.length && clean.length < 24; i++) {
        unichar c = [base characterAtIndex:i];
        if ([NSCharacterSet.alphanumericCharacterSet characterIsMember:c] || c == '-' || c == '_') [clean appendFormat:@"%C", c];
        else if (c == ' ' && clean.length) [clean appendString:@"-"];
    }
    if (clean.length == 0) [clean appendString:@"clip"];
    NSString *tail = item.itemID.length > 6 ? [item.itemID substringFromIndex:item.itemID.length - 6] : item.itemID;
    NSString *name = [NSString stringWithFormat:@"%@-%@.%@", clean, tail, video ? @"mp4" : @"gif"];
    NSURL *copy = [folder URLByAppendingPathComponent:name];
    if (![files copyItemAtURL:source toURL:copy error:NULL]) return source;
    return copy;
}

+ (void)shareFile:(NSURL *)file from:(UIViewController *)controller view:(UIView *)view {
    if (!file) {
        [self toast:@"The file is missing"];
        return;
    }
    UIActivityViewController *sheet = [[UIActivityViewController alloc] initWithActivityItems:@[file] applicationActivities:nil];
    sheet.popoverPresentationController.sourceView = view ?: controller.view;
    [controller presentViewController:sheet animated:YES completion:nil];
}

+ (void)shareGIF:(GSItem *)item from:(UIViewController *)controller view:(UIView *)view {
    [self shareFile:[self exportedFileFor:item video:NO] from:controller view:view];
}

+ (void)shareVideo:(GSItem *)item from:(UIViewController *)controller view:(UIView *)view {
    [self shareFile:[self exportedFileFor:item video:YES] from:controller view:view];
}

+ (BOOL)copyGIF:(GSItem *)item {
    NSData *data = [NSData dataWithContentsOfURL:[GSStore.shared gifURLForID:item.itemID] options:NSDataReadingMappedIfSafe error:NULL];
    if (!data.length) {
        [self toast:@"The GIF is missing"];
        return NO;
    }
    [UIPasteboard.generalPasteboard setData:data forPasteboardType:@"com.compuserve.gif"];
    [[UINotificationFeedbackGenerator new] notificationOccurred:UINotificationFeedbackTypeSuccess];
    [self toast:@"Copied. Paste it into any chat."];
    return YES;
}

+ (void)openPost:(GSItem *)item {
    NSURL *url = item.tweetID ? [GSTweet pageURLForID:item.tweetID] : (item.sourceURL ? [NSURL URLWithString:item.sourceURL] : nil);
    if (url) [UIApplication.sharedApplication openURL:url options:@{} completionHandler:nil];
}

+ (void)toggleFavorite:(GSItem *)item {
    item.favorite = !item.favorite;
    [GSStore.shared saveItem:item];
    [[UIImpactFeedbackGenerator new] impactOccurred];
}

+ (void)confirmDelete:(GSItem *)item from:(UIViewController *)controller done:(void (^)(void))done {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Delete this clip?"
                                                                   message:@"Its GIF and video are removed from this iPhone."
                                                            preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
    [alert addAction:[UIAlertAction actionWithTitle:@"Delete" style:UIAlertActionStyleDestructive handler:^(UIAlertAction *action) {
        [GSStore.shared deleteItem:item];
        if (done) done();
    }]];
    [controller presentViewController:alert animated:YES completion:nil];
}

+ (void)rename:(GSItem *)item from:(UIViewController *)controller done:(void (^)(void))done {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Name"
                                                                   message:@"A few words to find this clip by when you search."
                                                            preferredStyle:UIAlertControllerStyleAlert];
    [alert addTextFieldWithConfigurationHandler:^(UITextField *field) {
        field.text = item.label;
        field.placeholder = @"happy cat, facepalm…";
        field.autocapitalizationType = UITextAutocapitalizationTypeNone;
        field.clearButtonMode = UITextFieldViewModeWhileEditing;
    }];
    __weak UIAlertController *weakAlert = alert;
    [alert addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
    [alert addAction:[UIAlertAction actionWithTitle:@"Save" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
        NSString *text = [weakAlert.textFields.firstObject.text stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
        item.label = text.length ? text : nil;
        [GSStore.shared saveItem:item];
        if (done) done();
    }]];
    [controller presentViewController:alert animated:YES completion:nil];
}

+ (UIMenu *)menuForItem:(GSItem *)item from:(UIViewController *)controller view:(UIView *)view changed:(void (^)(void))changed {
    __weak UIViewController *weakController = controller;
    __weak UIView *weakView = view;
    UIAction *share = [UIAction actionWithTitle:@"Share GIF" image:[UIImage systemImageNamed:@"square.and.arrow.up"] identifier:nil
                                        handler:^(UIAction *action) { [GSActions shareGIF:item from:weakController view:weakView]; }];
    UIAction *copy = [UIAction actionWithTitle:@"Copy GIF" image:[UIImage systemImageNamed:@"doc.on.doc"] identifier:nil
                                       handler:^(UIAction *action) { [GSActions copyGIF:item]; }];
    UIAction *video = [UIAction actionWithTitle:@"Share as Video" image:[UIImage systemImageNamed:@"film"] identifier:nil
                                        handler:^(UIAction *action) { [GSActions shareVideo:item from:weakController view:weakView]; }];
    UIAction *favorite = [UIAction actionWithTitle:item.favorite ? @"Remove Favourite" : @"Favourite"
                                             image:[UIImage systemImageNamed:item.favorite ? @"star.slash" : @"star"] identifier:nil
                                           handler:^(UIAction *action) { [GSActions toggleFavorite:item]; if (changed) changed(); }];
    UIAction *name = [UIAction actionWithTitle:@"Name…" image:[UIImage systemImageNamed:@"pencil"] identifier:nil
                                       handler:^(UIAction *action) { [GSActions rename:item from:weakController done:changed]; }];
    NSMutableArray<UIMenuElement *> *more = [NSMutableArray arrayWithObjects:favorite, name, nil];
    if (item.tweetID || item.sourceURL) {
        [more addObject:[UIAction actionWithTitle:@"Open Post" image:[UIImage systemImageNamed:@"arrow.up.right.square"] identifier:nil
                                          handler:^(UIAction *action) { [GSActions openPost:item]; }]];
    }
    UIAction *delete = [UIAction actionWithTitle:@"Delete" image:[UIImage systemImageNamed:@"trash"] identifier:nil
                                         handler:^(UIAction *action) { [GSActions confirmDelete:item from:weakController done:changed]; }];
    delete.attributes = UIMenuElementAttributesDestructive;
    return [UIMenu menuWithTitle:@"" children:@[
        [UIMenu menuWithTitle:@"" image:nil identifier:nil options:UIMenuOptionsDisplayInline children:@[share, copy, video]],
        [UIMenu menuWithTitle:@"" image:nil identifier:nil options:UIMenuOptionsDisplayInline children:more],
        [UIMenu menuWithTitle:@"" image:nil identifier:nil options:UIMenuOptionsDisplayInline children:@[delete]],
    ]];
}

+ (NSString *)summaryOf:(GSItem *)item {
    NSMutableArray<NSString *> *parts = [NSMutableArray new];
    [parts addObject:[NSString stringWithFormat:@"GIF %@", GSByteString(item.gifBytes)]];
    [parts addObject:[NSString stringWithFormat:@"%ld × %ld", (long)item.width, (long)item.height]];
    [parts addObject:[NSString stringWithFormat:@"%.1f s", item.gifDuration]];
    if (item.videoBytes > 0) [parts addObject:[NSString stringWithFormat:@"video %@", GSByteString(item.videoBytes)]];
    return [parts componentsJoinedByString:@"  ·  "];
}

+ (void)toast:(NSString *)text {
    UIWindow *window = GSAppDelegate.shared.window;
    if (!window) return;
    static const NSInteger kTag = 0x6753;
    [[window viewWithTag:kTag] removeFromSuperview];

    UIVisualEffectView *pill = [[UIVisualEffectView alloc] initWithEffect:[UIBlurEffect effectWithStyle:UIBlurEffectStyleSystemMaterialDark]];
    pill.tag = kTag;
    pill.layer.cornerRadius = 22;
    pill.layer.cornerCurve = kCACornerCurveContinuous;
    pill.clipsToBounds = YES;
    pill.userInteractionEnabled = NO;
    UILabel *label = [UILabel new];
    label.text = text;
    label.font = [UIFont systemFontOfSize:15 weight:UIFontWeightSemibold];
    label.textColor = UIColor.whiteColor;
    label.textAlignment = NSTextAlignmentCenter;
    label.numberOfLines = 2;
    const CGFloat maxWidth = window.bounds.size.width - 64;
    CGSize fit = [label sizeThatFits:CGSizeMake(maxWidth - 40, 100)];
    const CGFloat width = MIN(maxWidth, fit.width + 40), height = MAX(44, fit.height + 22);
    pill.frame = CGRectMake((window.bounds.size.width - width) / 2,
                            window.bounds.size.height - window.safeAreaInsets.bottom - height - 28, width, height);
    label.frame = pill.contentView.bounds;
    label.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    [pill.contentView addSubview:label];
    [window addSubview:pill];

    pill.alpha = 0;
    pill.transform = CGAffineTransformMakeTranslation(0, 12);
    [UIView animateWithDuration:0.22 animations:^{
        pill.alpha = 1;
        pill.transform = CGAffineTransformIdentity;
    } completion:^(BOOL finished) {
        [UIView animateWithDuration:0.3 delay:1.6 options:0 animations:^{ pill.alpha = 0; } completion:^(BOOL done) {
            [pill removeFromSuperview];
        }];
    }];
}

@end
