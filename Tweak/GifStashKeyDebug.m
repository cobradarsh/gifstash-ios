// Test hooks, for checking the tweak on the phone without anyone tapping. Off unless the file "diag" exists in the
// copy of the library (GifStashKeyMirror()) when an app starts.
//
// Commands are lines "<number> <command> [argument]" in the file "cmd.txt" next to it; the app in front runs each
// number once and writes what it found to gifstashkey.log in its own tmp folder:
//   state         what the app can read, where the keyboard bar and the button are
//   field         put a text box on screen and bring the keyboard up in it
//   fieldstate    what the text box holds (a pasted GIF shows as an attachment)
//   endfield      take the text box away
//   tap           press the button, as a finger would
//   hit           which view a touch on the first tile, and on the picker's empty part, would reach
//   open | close  the picker
//   pick <n>      choose clip number n in the picker
//   shot <name>   a picture of every window, keyboard included, as gifstashkey-<name>.png in tmp
#import "GifStashKey.h"
#import <objc/runtime.h>
#include <unistd.h>

static NSString *const kVersion = @"1.0.3";

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
    for (UIView *each in GifStashKeyDocks()) {
        NSMutableArray<NSString *> *chain = [NSMutableArray new];
        for (UIView *view = each; view; view = view.superview) {
            [chain addObject:[NSString stringWithFormat:@"%@ %@", NSStringFromClass(view.class), NSStringFromCGRect(view.frame)]];
        }
        UIView *content = each;
        while (content.superview && content.superview != each.window) content = content.superview;
        GifStashKeyLog(@"state: bar%@ (window level %.0f, hidden=%d, button=%d, keyboard takes touches=%d): %@", each == dock ? @" IN FRONT" : @"",
                       each.window.windowLevel, each.window.hidden, GifStashKeyButtonInDock(each) != nil, content.userInteractionEnabled,
                       [chain componentsJoinedByString:@" < "]);
    }
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
    } else if ([command isEqualToString:@"tap"]) {
        // What a finger on the button does.
        UIButton *button = GifStashKeyCurrentDock() ? GifStashKeyButtonInDock(GifStashKeyCurrentDock()) : nil;
        [button sendActionsForControlEvents:UIControlEventTouchUpInside];
        GifStashKeyLog(@"tap: button=%d, panel=%d in %@", button != nil, GifStashKeyPanel.current != nil,
                       NSStringFromClass(GifStashKeyPanel.current.window.class));
    } else if ([command isEqualToString:@"hit"]) {
        // Where a finger on the first tile, and one on the empty part of the picker, would land: the windows are
        // asked from the front one back, as the system does.
        GifStashKeyPanel *panel = GifStashKeyPanel.current;
        const CGPoint tile = [panel centreOfFirstTile];
        const CGRect area = [panel convertRect:panel.bounds toView:nil];
        NSArray<NSValue *> *points = @[[NSValue valueWithCGPoint:tile],
                                       [NSValue valueWithCGPoint:CGPointMake(CGRectGetMaxX(area) - 30, CGRectGetMaxY(area) - 60)]];
        for (NSValue *value in points) {
            const CGPoint point = value.CGPointValue;
            NSString *found = @"nothing";
            for (UIWindow *window in AllWindows().reverseObjectEnumerator) {
                UIView *view = [window hitTest:[window convertPoint:point fromWindow:nil] withEvent:nil];
                if (!view) continue;
                NSMutableArray<NSString *> *chain = [NSMutableArray new];
                for (UIView *each = view; each && chain.count < 5; each = each.superview) [chain addObject:NSStringFromClass(each.class)];
                found = [NSString stringWithFormat:@"%@ in %@, inside the picker=%d", [chain componentsJoinedByString:@" < "],
                         NSStringFromClass(window.class), panel != nil && [view isDescendantOfView:panel]];
                break;
            }
            GifStashKeyLog(@"hit %@: %@", NSStringFromCGPoint(point), found);
        }
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

#pragma mark - What a paste meets

static __weak UIResponder *gFirstResponder;
static NSString *gTextBefore;

@interface UIResponder (GifStashKeyDebug)
- (void)gifStashKeyNoteFirstResponder:(id)sender;
@end

@implementation UIResponder (GifStashKeyDebug)
- (void)gifStashKeyNoteFirstResponder:(id)sender {
    gFirstResponder = self;
}
@end

/// The class, going up from `object`'s, that has its own version of `selector`.
static NSString *Implementer(id object, SEL selector) {
    for (Class each = [object class]; each; each = class_getSuperclass(each)) {
        unsigned int count = 0;
        Method *methods = class_copyMethodList(each, &count);
        BOOL has = NO;
        for (unsigned int i = 0; i < count && !has; i++) has = method_getName(methods[i]) == selector;
        free(methods);
        if (has) return NSStringFromClass(each);
    }
    return @"nobody";
}

static NSString *TextOf(UIResponder *responder) {
    if ([responder isKindOfClass:UITextView.class]) return ((UITextView *)responder).text ?: @"";
    if ([responder isKindOfClass:UITextField.class]) return ((UITextField *)responder).text ?: @"";
    return nil;
}

void GifStashKeyDebugPaste(NSString *stage) {
    if (!gOn) return;
    gFirstResponder = nil;
    [UIApplication.sharedApplication sendAction:@selector(gifStashKeyNoteFirstResponder:) to:nil from:nil forEvent:nil];
    UIResponder *first = gFirstResponder;
    NSString *text = TextOf(first);
    if ([stage isEqualToString:@"before"]) {
        gTextBefore = text;
        NSMutableArray<NSString *> *classes = [NSMutableArray new];
        for (Class each = first.class; each && classes.count < 6; each = class_getSuperclass(each)) [classes addObject:NSStringFromClass(each)];
        NSMutableArray<NSString *> *chain = [NSMutableArray new];
        for (UIResponder *each = first.nextResponder; each && chain.count < 8; each = each.nextResponder) {
            [chain addObject:[NSString stringWithFormat:@"%@%@", NSStringFromClass(each.class),
                              [Implementer(each, @selector(paste:)) isEqualToString:@"nobody"] ? @"" : @"(has paste:)"]];
        }
        GifStashKeyLog(@"paste before: first responder %@", first ? [classes componentsJoinedByString:@" : "] : @"NONE");
        GifStashKeyLog(@"paste before: paste: comes from %@, pasteItemProviders: from %@, canPerformAction(paste)=%d, accepts %@",
                       Implementer(first, @selector(paste:)), Implementer(first, @selector(pasteItemProviders:)),
                       [first canPerformAction:@selector(paste:) withSender:nil],
                       [first respondsToSelector:@selector(pasteConfiguration)] ? first.pasteConfiguration.acceptableTypeIdentifiers : nil);
        GifStashKeyLog(@"paste before: then %@", [chain componentsJoinedByString:@" > "]);
        if ([first isKindOfClass:UITextView.class]) {
            UITextView *view = (UITextView *)first;
            GifStashKeyLog(@"paste before: text view editable=%d, attributes allowed=%d, delegate %@, %lu characters", view.editable,
                           view.allowsEditingTextAttributes, NSStringFromClass([view.delegate class]), (unsigned long)text.length);
        }
        UIPasteboard *board = UIPasteboard.generalPasteboard;
        NSMutableArray *providers = [NSMutableArray new];
        for (NSItemProvider *provider in board.itemProviders) [providers addObject:provider.registeredTypeIdentifiers];
        GifStashKeyLog(@"paste before: clipboard %ld items, types %@, images=%d strings=%d urls=%d, providers %@", (long)board.numberOfItems,
                       board.pasteboardTypes, board.hasImages, board.hasStrings, board.hasURLs, providers);
    } else {
        // Only what the paste added is written down, never what was already in the box.
        NSString *before = gTextBefore ?: @"";
        NSString *added = @"";
        if (text && text.length > before.length) {
            NSUInteger head = 0;
            while (head < before.length && [text characterAtIndex:head] == [before characterAtIndex:head]) head++;
            added = [text substringWithRange:NSMakeRange(head, MIN((NSUInteger)80, text.length - before.length))];
        }
        NSMutableArray<NSString *> *codes = [NSMutableArray new];
        for (NSUInteger i = 0; i < added.length && i < 12; i++) [codes addObject:[NSString stringWithFormat:@"%04x", [added characterAtIndex:i]]];
        UIViewController *top = nil;
        for (UIWindow *window in AllWindows()) {
            if (!window.isKeyWindow) continue;
            top = window.rootViewController;
            while (top.presentedViewController) top = top.presentedViewController;
        }
        GifStashKeyLog(@"paste after: first responder %@, text went from %lu to %lu characters, added '%@' (codes %@), front screen %@",
                       NSStringFromClass(first.class), (unsigned long)before.length, (unsigned long)text.length, added,
                       [codes componentsJoinedByString:@" "], NSStringFromClass(top.class));
        gTextBefore = nil;
    }
}

#pragma mark - Touches that reach the keys

static IMP gKeyboardTouchesBegan;

static void KeyboardTouchesBegan(UIView *self, SEL _cmd, NSSet<UITouch *> *touches, UIEvent *event) {
    UITouch *touch = touches.anyObject;
    NSMutableArray<NSString *> *chain = [NSMutableArray new];
    for (UIView *each = touch.view; each && chain.count < 4; each = each.superview) [chain addObject:NSStringFromClass(each.class)];
    GifStashKeyLog(@"touch: the KEYBOARD got a touch at %@ (picker open=%d); it was aimed at %@ in %@", NSStringFromCGPoint([touch locationInView:nil]),
                   GifStashKeyPanel.current != nil, [chain componentsJoinedByString:@" < "], NSStringFromClass(touch.window.class));
    if (gKeyboardTouchesBegan) ((void (*)(id, SEL, id, id))gKeyboardTouchesBegan)(self, _cmd, touches, event);
}

static void WatchKeyboardTouches(void) {
    Class layout = NSClassFromString(@"UIKeyboardLayout");
    SEL selector = @selector(touchesBegan:withEvent:);
    Method method = layout ? class_getInstanceMethod(layout, selector) : NULL;
    if (!method) return;
    gKeyboardTouchesBegan = method_getImplementation(method);
    if (!class_addMethod(layout, selector, (IMP)KeyboardTouchesBegan, method_getTypeEncoding(method))) {
        method_setImplementation(method, (IMP)KeyboardTouchesBegan);
    }
}

void GifStashKeyDebugStart(void) {
    NSString *mirror = GifStashKeyMirror();
    gOn = [NSFileManager.defaultManager fileExistsAtPath:[mirror stringByAppendingPathComponent:@"diag"]];
    if (!gOn) return;
    GifStashKeyLog(@"loaded into %@ (pid %d), GIF Stash Button %@", NSBundle.mainBundle.bundleIdentifier, (int)getpid(), kVersion);
    WatchKeyboardTouches();
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
