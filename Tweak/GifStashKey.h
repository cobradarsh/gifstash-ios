// GIF Stash Button: a button in the bar under the system keyboard that opens the clips saved in GIF Stash and
// pastes the chosen one into the message being written.
//
// One library, two jobs, chosen by the process it finds itself in:
//   SpringBoard   keeps a copy of the library where apps can read it (hard links: no extra space), plus the
//                 GIF Stash icon as the active SnowBoard theme draws it.
//   an app        adds the button to the keyboard bar and shows the picker.
#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

extern NSString *const GifStashKeyLibraryChanged;   // posted by the GIF Stash app and its share extension
extern NSString *const GifStashKeySyncRequest;      // an app asks SpringBoard to bring the copy up to date
extern NSString *const GifStashKeySynced;           // SpringBoard has done so

/// The jailbreak's root folder ("" on a rootful jailbreak), worked out from where this library was loaded from.
NSString *GifStashKeyRoot(void);
/// Where SpringBoard keeps the copy of the library: <root>/var/mobile/Library/GifStash.
NSString *GifStashKeyMirror(void);

void GifStashKeyStartMirror(void);
void GifStashKeyInstallDock(void);
void GifStashKeyDebugStart(void);
BOOL GifStashKeyDebugOn(void);
/// Written only while the test marker is there (an app's own tmp folder).
void GifStashKeyLog(NSString *format, ...) NS_FORMAT_FUNCTION(1, 2);

/// GIF Stash's icon as the home screen shows it, and a colour taken from it for the picker's accents.
UIImage *GifStashKeyIcon(void);
UIColor *GifStashKeyAccent(void);

/// The keyboard bar that is on screen (the frontmost of those seen), and all of them.
UIView *_Nullable GifStashKeyCurrentDock(void);
NSArray<UIView *> *GifStashKeyDocks(void);
UIButton *_Nullable GifStashKeyButtonInDock(UIView *dock);

@interface GifStashKeyClip : NSObject
@property (nonatomic, copy) NSString *clipID;
@property (nonatomic) BOOL favorite;
@property (nonatomic) double savedAt;
@property (nonatomic, copy, nullable) NSString *title;
@property (nonatomic, readonly) NSString *gifPath;
@property (nonatomic, readonly) NSString *videoPath;
@property (nonatomic, readonly) NSString *posterPath;
/// Newest first. Empty when the copy of the library cannot be read.
+ (NSArray<GifStashKeyClip *> *)allClips;
@end

@interface GifStashKeyPanel : UIView
+ (nullable GifStashKeyPanel *)current;
+ (void)toggleFromDock:(UIView *)dock;
+ (void)close;
- (NSUInteger)clipCount;
/// Where the first clip's tile is, in its window's coordinates (zero when there is none).
- (CGPoint)centreOfFirstTile;
/// Puts clip number `index` on the clipboard and pastes it into the text being edited.
- (BOOL)pickIndex:(NSUInteger)index;
@end

@interface LSApplicationProxy : NSObject
+ (nullable instancetype)applicationProxyForIdentifier:(NSString *)identifier;
@property (nonatomic, readonly, nullable) NSDictionary<NSString *, NSURL *> *groupContainerURLs;
@property (nonatomic, readonly, nullable) NSURL *bundleURL;
@end

@interface UIWindow (GifStashKeyPrivate)
+ (NSArray<UIWindow *> *)allWindowsIncludingInternalWindows:(BOOL)internal onlyVisibleWindows:(BOOL)visible;
@end

NS_ASSUME_NONNULL_END
