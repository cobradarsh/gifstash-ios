#import "GSAppDelegate.h"
#import "GSCommon.h"
#import "GSDiag.h"
#import "GSLibraryViewController.h"
#import "GSLoopView.h"
#import "GSStore.h"

UIColor *GSTint(void) {
    return [UIColor colorWithRed:1.00 green:0.33 blue:0.55 alpha:1.0];
}

static void GSLibraryChangedElsewhere(CFNotificationCenterRef center, void *observer, CFNotificationName name,
                                      const void *object, CFDictionaryRef userInfo) {
    // The share extension saved something while the app was open behind it.
    dispatch_async(dispatch_get_main_queue(), ^{
        [NSNotificationCenter.defaultCenter postNotificationName:GSStoreChangedNotification object:nil];
    });
}

@implementation GSAppDelegate

+ (GSAppDelegate *)shared {
    return (GSAppDelegate *)UIApplication.sharedApplication.delegate;
}

- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)launchOptions {
    [GSLoopView useQuietAudio];

    _library = [GSLibraryViewController new];
    UINavigationController *navigation = [[UINavigationController alloc] initWithRootViewController:_library];
    navigation.navigationBar.prefersLargeTitles = YES;
    UINavigationBarAppearance *bar = [UINavigationBarAppearance new];
    [bar configureWithOpaqueBackground];
    bar.backgroundColor = UIColor.blackColor;
    bar.shadowColor = UIColor.clearColor;
    navigation.navigationBar.standardAppearance = bar;
    navigation.navigationBar.scrollEdgeAppearance = bar;
    navigation.navigationBar.compactAppearance = bar;

    self.window = [[UIWindow alloc] initWithFrame:UIScreen.mainScreen.bounds];
    self.window.overrideUserInterfaceStyle = UIUserInterfaceStyleDark;     // true black suits the OLED screen
    self.window.backgroundColor = UIColor.blackColor;
    self.window.tintColor = GSTint();
    self.window.rootViewController = navigation;
    [self.window makeKeyAndVisible];

    CFNotificationCenterAddObserver(CFNotificationCenterGetDarwinNotifyCenter(), (__bridge const void *)self,
                                    GSLibraryChangedElsewhere, (__bridge CFStringRef)GSChangedDarwinName, NULL,
                                    CFNotificationSuspensionBehaviorDeliverImmediately);
    GSDiagStart();
    return YES;
}

- (BOOL)application:(UIApplication *)app openURL:(NSURL *)url options:(NSDictionary<UIApplicationOpenURLOptionsKey, id> *)options {
    if (![url.scheme.lowercaseString isEqualToString:@"gifstash"]) return NO;
    if ([url.host isEqualToString:@"_diag"]) {
        GSDiagHandle(url);
        return YES;
    }
    if ([url.host isEqualToString:@"add"]) {
        // gifstash://add?url=<link>, for Shortcuts and the like.
        NSURLComponents *parts = [NSURLComponents componentsWithURL:url resolvingAgainstBaseURL:NO];
        for (NSURLQueryItem *item in parts.queryItems) {
            if ([item.name isEqualToString:@"url"] && item.value.length) {
                [self.library importText:item.value];
                break;
            }
        }
    }
    return YES;
}

@end
