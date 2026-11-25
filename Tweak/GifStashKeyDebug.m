// Test hooks, for checking the tweak on the phone without anyone tapping. Off unless the file "diag" exists in the
// copy of the library (GifStashKeyMirror()) when an app starts.
//
// Commands are lines "<number> <command> [argument]" in the file "cmd.txt" next to it; the app in front runs each
// number once and writes what it found to gifstashkey.log in its own tmp folder:
//   state         what the app can read, where the keyboard bar and the button are
//   field         put a text box on screen and bring the keyboard up in it
//   fieldstate    what the text box holds (a pasted GIF shows as an attachment)
//   endfield      take the text box away
//   open | close  the picker
//   pick <n>      choose clip number n in the picker
//   shot <name>   a picture of every window, keyboard included, as gifstashkey-<name>.png in tmp
#import "GifStashKey.h"
#include <unistd.h>

static BOOL gOn;
static NSInteger gLastCommand = -1;
static BOOL gSawOldCommands;
static UITextView *gField;

BOOL GifStashKeyDebugOn(void) { return gOn; }

static NSString *LogPath(void) {
    return [NSTemporaryDirectory() stringByAppendingPathComponent:@"gifstashkey.log"];
}

void GifStashKeyLog(NSString *format, ...) {
    if (!gOn) return;
    va_list arguments;
    va_start(arguments, format);
    NSString *line = [[NSString alloc] initWithFormat:format arguments:arguments];
    va_end(arguments);
    NSString *path = LogPath();
    if (![NSFileManager.defaultManager fileExistsAtPath:path]) [NSData.data writeToFile:path atomically:NO];
    NSFileHandle *handle = [NSFileHandle fileHandleForWritingAtPath:path];
    [handle seekToEndOfFile];
    [handle writeData:[[NSString stringWithFormat:@"%.2f %@\n", CFAbsoluteTimeGetCurrent(), line] dataUsingEncoding:NSUTF8StringEncoding]];
    [handle closeFile];
}

static NSArray<UIWindow *> *AllWindows(void) {
    if (![UIWindow respondsToSelector:@selector(allWindowsIncludingInternalWindows:onlyVisibleWindows:)]) return @[];
    NSArray<UIWindow *> *windows = [UIWindow allWindowsIncludingInternalWindows:YES onlyVisibleWindows:YES];
    return [windows sortedArrayUsingComparator:^NSComparisonResult(UIWindow *a, UIWindow *b) {
        return a.windowLevel < b.windowLevel ? NSOrderedAscending : (a.windowLevel > b.windowLevel ? NSOrderedDescending : NSOrderedSame);
    }];
}

static UIWindow *AppWindow(void) {
    for (UIWindow *window in AllWindows()) {
        if (window.isKeyWindow) return window;
    }
    return AllWindows().firstObject;
}

static void State(void) {
    NSFileManager *files = NSFileManager.defaultManager;
    NSString *mirror = GifStashKeyMirror();
    NSArray *listing = [files contentsOfDirectoryAtPath:mirror error:NULL];
    NSArray<GifStashKeyClip *> *clips = [GifStashKeyClip allClips];
    GifStashKeyClip *first = clips.firstObject;
    GifStashKeyLog(@"state: app %@, root '%@', mirror listed=%d (%lu names), clips %lu, icon file=%d, first gif readable=%d video readable=%d",
                   NSBundle.mainBundle.bundleIdentifier, GifStashKeyRoot(), listing != nil, (unsigned long)listing.count,
                   (unsigned long)clips.count, [files isReadableFileAtPath:[mirror stringByAppendingPathComponent:@"icon.png"]],
                   first ? [files isReadableFileAtPath:first.gifPath] : -1, first ? [files isReadableFileAtPath:first.videoPath] : -1);
    GifStashKeyLog(@"state: mirror.info %@", [[NSString alloc] initWithData:[NSData dataWithContentsOfFile:[mirror stringByAppendingPathComponent:@"mirror.info"]] ?: NSData.data
                                                                   encoding:NSUTF8StringEncoding]);
    UIView *dock = GifStashKeyCurrentDock();
    if (!dock) {
        GifStashKeyLog(@"state: no keyboard bar seen yet");
        return;
    }
    NSMutableArray<NSString *> *chain = [NSMutableArray new];
    for (UIView *view = dock; view; view = view.superview) {
        [chain addObject:[NSString stringWithFormat:@"%@ %@", NSStringFromClass(view.class), NSStringFromCGRect(view.frame)]];
    }
    GifStashKeyLog(@"state: bar chain: %@", [chain componentsJoinedByString:@" < "]);
    for (UIView *item in dock.subviews) {
        NSString *picture = @"";
        if ([item isKindOfClass:UIButton.class]) {
            UIImageView *imageView = ((UIButton *)item).imageView;
            picture = [NSString stringWithFormat:@" picture %@", NSStringFromCGRect([dock convertRect:imageView.bounds fromView:imageView])];
        }
        GifStashKeyLog(@"state: bar item %@ frame %@ hidden=%d alpha=%.2f%@%@", NSStringFromClass(item.class), NSStringFromCGRect(item.frame),
                       item.hidden, item.alpha, picture, item == GifStashKeyButtonInDock(dock) ? @" <- GIF Stash button" : @"");
    }
    UIButton *button = GifStashKeyButtonInDock(dock);
    UIImage *icon = [button imageForState:UIControlStateNormal];
    GifStashKeyLog(@"state: button in window=%d, on screen at %@, icon %@ px, panel open=%d (%lu clips)", button.window != nil,
                   NSStringFromCGRect([button convertRect:button.bounds toView:nil]),
                   NSStringFromCGSize(CGSizeMake(icon.size.width * icon.scale, icon.size.height * icon.scale)),
                   GifStashKeyPanel.current != nil, (unsigned long)GifStashKeyPanel.current.clipCount);
}

static void Shot(NSString *name) {
    UIWindow *base = AppWindow();
    if (!base) { GifStashKeyLog(@"shot %@: no window", name); return; }
    const CGRect bounds = base.screen.bounds;
    UIGraphicsImageRenderer *renderer = [[UIGraphicsImageRenderer alloc] initWithBounds:bounds];
    UIImage *image = [renderer imageWithActions:^(UIGraphicsImageRendererContext *context) {
        for (UIWindow *window in AllWindows()) {
            [window drawViewHierarchyInRect:window.frame afterScreenUpdates:NO];
        }
    }];
    NSString *path = [NSTemporaryDirectory() stringByAppendingPathComponent:[NSString stringWithFormat:@"gifstashkey-%@.png", name]];
    const BOOL ok = [UIImagePNGRepresentation(image) writeToFile:path atomically:YES];
    NSMutableArray<NSString *> *names = [NSMutableArray new];
    for (UIWindow *window in AllWindows()) [names addObject:NSStringFromClass(window.class)];
    GifStashKeyLog(@"shot %@: written=%d, windows %@", name, ok, [names componentsJoinedByString:@", "]);
}

static void Run(NSString *command, NSString *argument) {
    if ([command isEqualToString:@"state"]) {
        State();
    } else if ([command isEqualToString:@"field"]) {
        UIWindow *window = AppWindow();
        [gField removeFromSuperview];
        gField = [[UITextView alloc] initWithFrame:CGRectMake(20, 120, window.bounds.size.width - 40, 220)];
        gField.backgroundColor = [UIColor colorWithWhite:0.15 alpha:1];
        gField.textColor = UIColor.whiteColor;
        gField.font = [UIFont systemFontOfSize:17];
        gField.allowsEditingTextAttributes = YES;       // so that a pasted picture is accepted, as a chat's box would
        gField.layer.cornerRadius = 12;
        [window addSubview:gField];
        const BOOL focused = [gField becomeFirstResponder];
        GifStashKeyLog(@"field: in %@, focused=%d", NSStringFromClass(window.class), focused);
    } else if ([command isEqualToString:@"fieldstate"]) {
        __block NSInteger attachments = 0;
        NSAttributedString *text = gField.attributedText;
        [text enumerateAttribute:NSAttachmentAttributeName inRange:NSMakeRange(0, text.length) options:0
                      usingBlock:^(id value, NSRange range, BOOL *stop) { if (value) attachments++; }];
        UIPasteboard *board = UIPasteboard.generalPasteboard;
        GifStashKeyLog(@"fieldstate: field=%d, %lu characters, %ld attachments, first responder=%d; clipboard types %@, gif bytes %lu",
                       gField != nil, (unsigned long)text.length, (long)attachments, gField.isFirstResponder,
                       board.pasteboardTypes, (unsigned long)[board dataForPasteboardType:@"com.compuserve.gif"].length);
    } else if ([command isEqualToString:@"endfield"]) {
        [gField resignFirstResponder];
        [gField removeFromSuperview];
        gField = nil;
        GifStashKeyLog(@"endfield");
    } else if ([command isEqualToString:@"open"]) {
        UIView *dock = GifStashKeyCurrentDock();
        if (dock && !GifStashKeyPanel.current) [GifStashKeyPanel toggleFromDock:dock];
        GifStashKeyLog(@"open: bar=%d, panel=%d", dock != nil, GifStashKeyPanel.current != nil);
    } else if ([command isEqualToString:@"close"]) {
        [GifStashKeyPanel close];
        GifStashKeyLog(@"close");
    } else if ([command isEqualToString:@"pick"]) {
        const BOOL ok = [GifStashKeyPanel.current pickIndex:(NSUInteger)MAX(0, argument.integerValue)];
        GifStashKeyLog(@"pick %@: started=%d", argument, ok);
    } else if ([command isEqualToString:@"shot"]) {
        Shot(argument.length ? argument : @"shot");
    } else {
        GifStashKeyLog(@"unknown command %@", command);
    }
}

void GifStashKeyDebugStart(void) {
    NSString *mirror = GifStashKeyMirror();
    gOn = [NSFileManager.defaultManager fileExistsAtPath:[mirror stringByAppendingPathComponent:@"diag"]];
    if (!gOn) return;
    GifStashKeyLog(@"loaded into %@ (pid %d)", NSBundle.mainBundle.bundleIdentifier, (int)getpid());
    NSString *commands = [mirror stringByAppendingPathComponent:@"cmd.txt"];
    dispatch_async(dispatch_get_main_queue(), ^{
        [NSTimer scheduledTimerWithTimeInterval:0.3 repeats:YES block:^(NSTimer *timer) {
            if (UIApplication.sharedApplication.applicationState != UIApplicationStateActive) return;
            NSString *text = [NSString stringWithContentsOfFile:commands encoding:NSUTF8StringEncoding error:NULL];
            // Commands that were already in the file when this app came to the front belong to an earlier test.
            const BOOL skipping = !gSawOldCommands;
            gSawOldCommands = YES;
            for (NSString *line in [text componentsSeparatedByCharactersInSet:NSCharacterSet.newlineCharacterSet]) {
                NSArray<NSString *> *parts = [[line stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceCharacterSet]
                                              componentsSeparatedByString:@" "];
                if (parts.count < 2) continue;
                const NSInteger number = parts[0].integerValue;
                if (number <= gLastCommand) continue;
                gLastCommand = number;
                if (skipping) continue;
                @try {
                    Run(parts[1], parts.count > 2 ? parts[2] : @"");
                } @catch (NSException *exception) {
                    GifStashKeyLog(@"command %@ threw %@", parts[1], exception);
                }
            }
        }];
    });
}
