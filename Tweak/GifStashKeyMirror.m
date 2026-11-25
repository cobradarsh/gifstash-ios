// SpringBoard's part. A chat app is sandboxed and cannot look into GIF Stash's container, but it can read the
// jailbreak's own folders. So SpringBoard, which may read both, keeps a copy of the library there. The copy is
// made of hard links: the same files under a second name, taking no extra space.
#import "GifStashKey.h"
#include <sys/stat.h>
#include <unistd.h>

static NSString *const kApp = @"com.cobradarsh.gifstash";
static NSString *const kGroup = @"group.com.cobradarsh.gifstash";

static dispatch_queue_t MirrorQueue(void) {
    static dispatch_queue_t queue;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ queue = dispatch_queue_create("com.adarsh.gifstashkey.mirror", DISPATCH_QUEUE_SERIAL); });
    return queue;
}

static void MirrorLog(NSString *line) {
    NSString *path = @"/var/mobile/Library/Logs/GifStashKey.log";
    NSFileManager *files = NSFileManager.defaultManager;
    NSDictionary *attributes = [files attributesOfItemAtPath:path error:NULL];
    if (!attributes || [attributes fileSize] > 64 * 1024) [NSData.data writeToFile:path atomically:NO];
    NSFileHandle *handle = [NSFileHandle fileHandleForWritingAtPath:path];
    [handle seekToEndOfFile];
    NSDateFormatter *format = [NSDateFormatter new];
    format.dateFormat = @"yyyy-MM-dd HH:mm:ss";
    [handle writeData:[[NSString stringWithFormat:@"%@ %@\n", [format stringFromDate:NSDate.date], line] dataUsingEncoding:NSUTF8StringEncoding]];
    [handle closeFile];
}

/// GIF Stash's "Stash" folder, or nil while the app is not installed.
static NSString *LibraryFolder(void) {
    NSFileManager *files = NSFileManager.defaultManager;
    Class proxyClass = NSClassFromString(@"LSApplicationProxy");
    if ([proxyClass respondsToSelector:@selector(applicationProxyForIdentifier:)]) {
        LSApplicationProxy *proxy = [proxyClass applicationProxyForIdentifier:kApp];
        NSDictionary *groups = [proxy respondsToSelector:@selector(groupContainerURLs)] ? proxy.groupContainerURLs : nil;
        NSURL *url = [groups isKindOfClass:NSDictionary.class] ? groups[kGroup] : nil;
        if ([url isKindOfClass:NSURL.class]) {
            NSString *folder = [url.path stringByAppendingPathComponent:@"Stash"];
            if ([files fileExistsAtPath:folder]) return folder;
        }
    }
    // The long way: look through the shared containers for the one that carries the group's name.
    NSString *base = @"/var/mobile/Containers/Shared/AppGroup";
    for (NSString *name in [files contentsOfDirectoryAtPath:base error:NULL] ?: @[]) {
        NSString *container = [base stringByAppendingPathComponent:name];
        NSDictionary *metadata = [NSDictionary dictionaryWithContentsOfFile:
                                  [container stringByAppendingPathComponent:@".com.apple.mobile_container_manager.metadata.plist"]];
        if ([metadata[@"MCMMetadataIdentifier"] isEqual:kGroup]) {
            NSString *folder = [container stringByAppendingPathComponent:@"Stash"];
            if ([files fileExistsAtPath:folder]) return folder;
        }
    }
    return nil;
}

/// The picture the home screen shows for GIF Stash: the active SnowBoard theme's, else the app's own.
static NSString *IconSource(void) {
    NSFileManager *files = NSFileManager.defaultManager;
    NSString *root = GifStashKeyRoot();
    NSDictionary *prefs = [NSDictionary dictionaryWithContentsOfFile:
                           [root stringByAppendingPathComponent:@"var/mobile/Library/Preferences/com.spark.snowboardprefs.plist"]];
    NSMutableArray<NSString *> *candidates = [NSMutableArray new];
    id override = [prefs[@"IconOverrides"] isKindOfClass:NSDictionary.class] ? prefs[@"IconOverrides"][kApp] : nil;
    if ([override isKindOfClass:NSString.class]) [candidates addObject:override];
    for (id theme in [prefs[@"ActiveMenuItems"] isKindOfClass:NSArray.class] ? prefs[@"ActiveMenuItems"] : @[]) {
        if (![theme isKindOfClass:NSString.class]) continue;
        for (NSString *ending in @[@"-large.png", @"@3x.png", @"@2x.png", @".png"]) {
            [candidates addObject:[NSString stringWithFormat:@"%@/IconBundles/%@%@", theme, kApp, ending]];
        }
    }
    for (NSString *candidate in candidates) {
        // SnowBoard stores paths as the jailbreak sees them; some versions store the full path.
        for (NSString *path in @[[root stringByAppendingPathComponent:candidate], candidate]) {
            BOOL folder = NO;
            if ([files fileExistsAtPath:path isDirectory:&folder] && !folder) return path;
        }
    }
    Class proxyClass = NSClassFromString(@"LSApplicationProxy");
    if ([proxyClass respondsToSelector:@selector(applicationProxyForIdentifier:)]) {
        LSApplicationProxy *proxy = [proxyClass applicationProxyForIdentifier:kApp];
        NSString *bundle = [proxy respondsToSelector:@selector(bundleURL)] ? proxy.bundleURL.path : nil;
        for (NSString *name in @[@"AppIcon60x60@3x.png", @"AppIcon60x60@2x.png"]) {
            NSString *path = [bundle stringByAppendingPathComponent:name];
            if (path && [files fileExistsAtPath:path]) return path;
        }
    }
    return nil;
}

static BOOL SameFile(NSString *a, NSString *b) {
    struct stat first, second;
    if (stat(a.fileSystemRepresentation, &first) != 0 || stat(b.fileSystemRepresentation, &second) != 0) return NO;
    return first.st_ino == second.st_ino && first.st_dev == second.st_dev;
}

static void Sync(NSString *reason) {
    NSFileManager *files = NSFileManager.defaultManager;
    NSString *mirror = GifStashKeyMirror();
    [files createDirectoryAtPath:mirror withIntermediateDirectories:YES attributes:@{NSFilePosixPermissions: @0755} error:NULL];
    NSString *library = LibraryFolder();
    NSMutableSet<NSString *> *wanted = [NSMutableSet new];
    NSInteger linked = 0, failed = 0, removed = 0;

    for (NSString *name in library ? ([files contentsOfDirectoryAtPath:library error:NULL] ?: @[]) : @[]) {
        NSString *extension = name.pathExtension;
        if (![@[@"json", @"gif", @"mp4", @"jpg"] containsObject:extension]) continue;
        if ([name containsString:@".part."] || [name hasPrefix:@"."]) continue;
        [wanted addObject:name];
        NSString *from = [library stringByAppendingPathComponent:name];
        NSString *to = [mirror stringByAppendingPathComponent:name];
        if (SameFile(from, to)) continue;
        [files removeItemAtPath:to error:NULL];
        if (link(from.fileSystemRepresentation, to.fileSystemRepresentation) == 0 || [files copyItemAtPath:from toPath:to error:NULL]) {
            linked++;
        } else {
            failed++;
        }
    }
    for (NSString *name in [files contentsOfDirectoryAtPath:mirror error:NULL] ?: @[]) {
        if (![@[@"json", @"gif", @"mp4", @"jpg"] containsObject:name.pathExtension]) continue;
        if ([wanted containsObject:name]) continue;
        if ([files removeItemAtPath:[mirror stringByAppendingPathComponent:name] error:NULL]) removed++;
    }

    NSString *iconSource = IconSource();
    NSString *iconCopy = [mirror stringByAppendingPathComponent:@"icon.png"];
    NSData *icon = iconSource ? [NSData dataWithContentsOfFile:iconSource] : nil;
    if (icon.length) {
        if (![icon isEqualToData:[NSData dataWithContentsOfFile:iconCopy] ?: NSData.data]) [icon writeToFile:iconCopy atomically:YES];
    } else {
        [files removeItemAtPath:iconCopy error:NULL];
    }
    // Says where the icon came from, and lets an app tell "nothing saved yet" from "no copy made yet".
    NSDictionary *note = @{@"library": library ?: @"", @"icon": iconSource ?: @"", @"files": @(wanted.count),
                           @"time": @(NSDate.date.timeIntervalSince1970)};
    [[NSJSONSerialization dataWithJSONObject:note options:0 error:NULL] writeToFile:[mirror stringByAppendingPathComponent:@"mirror.info"]
                                                                        atomically:YES];
    if (linked || removed || failed || [reason isEqualToString:@"start"]) {
        MirrorLog([NSString stringWithFormat:@"%@: %lu files, %ld linked, %ld removed, %ld failed; library %@; icon %@",
                   reason, (unsigned long)wanted.count, (long)linked, (long)removed, (long)failed, library ?: @"(GIF Stash not found)",
                   iconSource ?: @"(none)"]);
    }
    CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(), (__bridge CFStringRef)GifStashKeySynced,
                                         NULL, NULL, YES);
}

static void Requested(CFNotificationCenterRef center, void *observer, CFNotificationName name, const void *object,
                      CFDictionaryRef userInfo) {
    NSString *reason = [(__bridge NSString *)name isEqualToString:GifStashKeySyncRequest] ? @"asked" : @"library changed";
    dispatch_async(MirrorQueue(), ^{ Sync(reason); });
}

void GifStashKeyStartMirror(void) {
    CFNotificationCenterRef center = CFNotificationCenterGetDarwinNotifyCenter();
    for (NSString *name in @[GifStashKeyLibraryChanged, GifStashKeySyncRequest]) {
        CFNotificationCenterAddObserver(center, NULL, Requested, (__bridge CFStringRef)name, NULL,
                                        CFNotificationSuspensionBehaviorDeliverImmediately);
    }
    // SpringBoard is still starting when this loads: wait before the first pass (it only touches files).
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(6 * NSEC_PER_SEC)), MirrorQueue(), ^{ Sync(@"start"); });
}
