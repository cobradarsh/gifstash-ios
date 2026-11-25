#import "GSDiag.h"
#import <ImageIO/ImageIO.h>
#import <UIKit/UIKit.h>
#import "GSActions.h"
#import "GSAppDelegate.h"
#import "GSCommon.h"
#import "GSLibraryViewController.h"
#import "GSStore.h"

static BOOL gEnabled;

static NSString *GSDiagPath(NSString *name) {
    return [[NSHomeDirectory() stringByAppendingPathComponent:@"Library/Caches"] stringByAppendingPathComponent:name];
}

BOOL GSDiagEnabled(void) { return gEnabled; }

void GSDiagLog(NSString *event, NSDictionary *info) {
    if (!gEnabled) return;
    NSMutableDictionary *entry = [NSMutableDictionary dictionaryWithDictionary:info ?: @{}];
    entry[@"t"] = @(NSDate.date.timeIntervalSince1970);
    entry[@"event"] = event;
    NSData *json = [NSJSONSerialization dataWithJSONObject:entry options:0 error:NULL];
    if (!json) return;
    NSString *path = GSDiagPath(@"gs-diag.log");
    if (![NSFileManager.defaultManager fileExistsAtPath:path]) [NSData.data writeToFile:path atomically:NO];
    NSFileHandle *handle = [NSFileHandle fileHandleForWritingAtPath:path];
    [handle seekToEndOfFile];
    [handle writeData:json];
    [handle writeData:[@"\n" dataUsingEncoding:NSUTF8StringEncoding]];
    [handle closeFile];
}

static NSDictionary *GSDiagItem(GSItem *item) {
    return @{@"id": item.itemID, @"kind": item.kind, @"author": item.author ?: @"", @"width": @(item.width), @"height": @(item.height),
             @"frames": @(item.frames), @"gifSeconds": @(item.gifDuration), @"videoSeconds": @(item.videoDuration),
             @"gifBytes": @(item.gifBytes), @"videoBytes": @(item.videoBytes), @"preset": @(item.preset),
             @"trimmed": @(item.trimmed), @"favorite": @(item.favorite)};
}

static UIViewController *GSDiagTop(void) {
    UIViewController *controller = GSAppDelegate.shared.window.rootViewController;
    while (controller.presentedViewController && !controller.presentedViewController.isBeingDismissed) {
        controller = controller.presentedViewController;
    }
    if ([controller isKindOfClass:UINavigationController.class]) {
        controller = ((UINavigationController *)controller).topViewController ?: controller;
    }
    return controller;
}

/// Opens the GIF the way any other app would, and says what is in it.
static NSDictionary *GSDiagReadGIF(NSURL *url) {
    CGImageSourceRef source = CGImageSourceCreateWithURL((__bridge CFURLRef)url, NULL);
    if (!source) return @{@"readable": @NO};
    const size_t count = CGImageSourceGetCount(source);
    double seconds = 0;
    size_t width = 0, height = 0, decoded = 0;
    for (size_t i = 0; i < count; i++) {
        NSDictionary *properties = CFBridgingRelease(CGImageSourceCopyPropertiesAtIndex(source, i, NULL));
        NSDictionary *gif = properties[(__bridge id)kCGImagePropertyGIFDictionary];
        NSNumber *delay = gif[(__bridge id)kCGImagePropertyGIFUnclampedDelayTime] ?: gif[(__bridge id)kCGImagePropertyGIFDelayTime];
        seconds += delay.doubleValue;
        if (i == 0 || i == count - 1 || i == count / 2) {
            CGImageRef image = CGImageSourceCreateImageAtIndex(source, i, NULL);
            if (image) {
                decoded++;
                width = CGImageGetWidth(image);
                height = CGImageGetHeight(image);
                CGImageRelease(image);
            }
        }
    }
    NSString *type = (__bridge NSString *)CGImageSourceGetType(source);
    CFRelease(source);
    return @{@"readable": @YES, @"type": type ?: @"", @"frames": @(count), @"seconds": @(seconds), @"width": @(width),
             @"height": @(height), @"sampledFramesDecoded": @(decoded)};
}

void GSDiagHandle(NSURL *url) {
    if (!gEnabled) return;
    NSString *command = [url.path stringByTrimmingCharactersInSet:[NSCharacterSet characterSetWithCharactersInString:@"/"]];
    NSMutableDictionary<NSString *, NSString *> *query = [NSMutableDictionary new];
    for (NSURLQueryItem *item in [NSURLComponents componentsWithURL:url resolvingAgainstBaseURL:NO].queryItems) {
        query[item.name] = item.value ?: @"";
    }
    GSLibraryViewController *library = GSAppDelegate.shared.library;
    GSStore *store = GSStore.shared;

    if ([command isEqualToString:@"state"]) {
        NSMutableArray *items = [NSMutableArray new];
        for (GSItem *item in store.allItems) [items addObject:GSDiagItem(item)];
        UIScreen *screen = UIScreen.mainScreen;
        GSDiagLog(@"state", @{@"root": store.rootURL.path ?: @"", @"usesGroup": @(store.usesGroup), @"count": @(items.count),
                              @"items": items, @"shown": @(library.shownItems.count), @"preset": @(store.preset),
                              @"bytes": @(store.totalBytes), @"importing": @(library.isImporting),
                              @"top": NSStringFromClass(GSDiagTop().class),
                              @"screen": NSStringFromCGRect(screen.bounds), @"scale": @(screen.scale),
                              @"maxFPS": @(screen.maximumFramesPerSecond),
                              @"footprintMB": @(GSFootprintMB()), @"availableMB": @(GSAvailableMB()),
                              @"keyboardAnimates": @(store.keyboardAnimates),
                              @"version": [NSBundle.mainBundle objectForInfoDictionaryKey:@"CFBundleShortVersionString"] ?: @""});
    } else if ([command isEqualToString:@"import"]) {
        const CFAbsoluteTime started = CFAbsoluteTimeGetCurrent();
        [library importText:query[@"url"] ?: @"" quietly:YES completion:^(NSArray<GSItem *> *items, NSError *error) {
            NSMutableArray *saved = [NSMutableArray new];
            for (GSItem *item in items) [saved addObject:GSDiagItem(item)];
            GSDiagLog(@"import", @{@"ok": @(error == nil), @"error": error.localizedDescription ?: @"", @"items": saved,
                                   @"seconds": @(CFAbsoluteTimeGetCurrent() - started)});
        }];
    } else if ([command isEqualToString:@"gifcheck"]) {
        GSItem *item = [store itemWithID:query[@"id"] ?: @""];
        NSMutableDictionary *answer = [NSMutableDictionary dictionaryWithDictionary:item ? GSDiagReadGIF([store gifURLForID:item.itemID]) : @{}];
        answer[@"found"] = @(item != nil);
        answer[@"id"] = query[@"id"] ?: @"";
        GSDiagLog(@"gifcheck", answer);
    } else if ([command isEqualToString:@"open"]) {
        GSDiagLog(@"open", @{@"ok": @([library openItemWithID:query[@"id"] ?: @""])});
    } else if ([command isEqualToString:@"dismiss"]) {
        [GSAppDelegate.shared.window.rootViewController dismissViewControllerAnimated:NO completion:^{
            GSDiagLog(@"dismiss", @{@"top": NSStringFromClass(GSDiagTop().class)});
        }];
    } else if ([command isEqualToString:@"copy"]) {
        GSItem *item = [store itemWithID:query[@"id"] ?: @""];
        const BOOL ok = item && [GSActions copyGIF:item];
        UIPasteboard *board = UIPasteboard.generalPasteboard;
        GSDiagLog(@"copy", @{@"ok": @(ok), @"types": board.pasteboardTypes ?: @[],
                             @"bytes": @([board dataForPasteboardType:@"com.compuserve.gif"].length)});
    } else if ([command isEqualToString:@"delete"]) {
        GSItem *item = [store itemWithID:query[@"id"] ?: @""];
        if (item) [store deleteItem:item];
        GSDiagLog(@"delete", @{@"found": @(item != nil), @"id": query[@"id"] ?: @""});
    } else if ([command isEqualToString:@"snapshot"]) {
        UIWindow *window = GSAppDelegate.shared.window;
        UIGraphicsImageRenderer *renderer = [[UIGraphicsImageRenderer alloc] initWithBounds:window.bounds];
        UIImage *image = [renderer imageWithActions:^(UIGraphicsImageRendererContext *context) {
            [window drawViewHierarchyInRect:window.bounds afterScreenUpdates:YES];
        }];
        NSString *name = query[@"name"].length ? query[@"name"] : @"shot";
        NSString *path = GSDiagPath([NSString stringWithFormat:@"gs-snap-%@.png", name]);
        const BOOL ok = [UIImagePNGRepresentation(image) writeToFile:path atomically:YES];
        GSDiagLog(@"snapshot", @{@"ok": @(ok), @"name": name});
    } else {
        GSDiagLog(@"unknown", @{@"command": command ?: @""});
    }
}

void GSDiagStart(void) {
    gEnabled = [NSFileManager.defaultManager fileExistsAtPath:GSDiagPath(@"gs-diag")];
    if (!gEnabled) return;
    GSDiagLog(@"launch", @{@"root": GSStore.shared.rootURL.path ?: @"", @"usesGroup": @(GSStore.shared.usesGroup)});
    // URLs can also arrive through a file (the simulator asks before opening a URL; a phone pass feeds steps this way).
    [NSTimer scheduledTimerWithTimeInterval:0.2 repeats:YES block:^(NSTimer *timer) {
        NSString *path = GSDiagPath(@"gs-diag-cmd");
        NSString *text = [NSString stringWithContentsOfFile:path encoding:NSUTF8StringEncoding error:NULL];
        if (!text) return;
        [NSFileManager.defaultManager removeItemAtPath:path error:NULL];
        for (NSString *line in [text componentsSeparatedByCharactersInSet:NSCharacterSet.newlineCharacterSet]) {
            NSString *trimmed = [line stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceCharacterSet];
            NSURL *url = trimmed.length ? [NSURL URLWithString:trimmed] : nil;
            if (url) [UIApplication.sharedApplication.delegate application:UIApplication.sharedApplication openURL:url options:@{}];
        }
    }];
}
