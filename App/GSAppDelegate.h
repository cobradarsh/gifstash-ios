#import <UIKit/UIKit.h>

@class GSLibraryViewController;

@interface GSAppDelegate : UIResponder <UIApplicationDelegate>
@property (nonatomic, strong) UIWindow *window;
@property (nonatomic, strong, readonly) GSLibraryViewController *library;
+ (GSAppDelegate *)shared;
@end

/// The app's accent colour.
UIColor *GSTint(void);
