#import "GifStashKey.h"
#include <dlfcn.h>

NSString *const GifStashKeyLibraryChanged = @"com.cobradarsh.gifstash.changed";
NSString *const GifStashKeySyncRequest = @"com.adarsh.gifstashkey.sync";
NSString *const GifStashKeySynced = @"com.adarsh.gifstashkey.synced";

NSString *GifStashKeyRoot(void) {
    static NSString *root;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        root = @"";
        Dl_info info;
        memset(&info, 0, sizeof(info));
        if (dladdr((const void *)&GifStashKeyRoot, &info) && info.dli_fname) {
            NSString *path = [NSString stringWithUTF8String:info.dli_fname];
            for (NSString *marker in @[@"/usr/lib/TweakInject/", @"/Library/MobileSubstrate/DynamicLibraries/"]) {
                NSRange range = [path rangeOfString:marker];
                if (range.location != NSNotFound) {
                    root = [path substringToIndex:range.location];
                    break;
                }
            }
        }
    });
    return root;
}

NSString *GifStashKeyMirror(void) {
    return [GifStashKeyRoot() stringByAppendingPathComponent:@"var/mobile/Library/GifStash"];
}

__attribute__((constructor)) static void GifStashKeyInit(void) {
    @autoreleasepool {
        NSBundle *main = NSBundle.mainBundle;
        NSString *identifier = main.bundleIdentifier;
        if (!identifier) return;
        if ([identifier isEqualToString:@"com.apple.springboard"]) {
            GifStashKeyStartMirror();
            return;
        }
        // Apps only: not their extensions, not daemons that happen to link UIKit.
        if (![main.bundlePath.pathExtension isEqualToString:@"app"]) return;
        GifStashKeyInstallDock();
        GifStashKeyDebugStart();
    }
}
