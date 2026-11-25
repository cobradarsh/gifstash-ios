#import <UIKit/UIKit.h>
#import "GSStore.h"

NS_ASSUME_NONNULL_BEGIN

/// What can be done with a saved clip, shared by the tile menu and the detail sheet.
@interface GSActions : NSObject
+ (void)shareGIF:(GSItem *)item from:(UIViewController *)controller view:(UIView *)view;
+ (void)shareVideo:(GSItem *)item from:(UIViewController *)controller view:(UIView *)view;
/// Puts the GIF on the clipboard, ready to paste into a chat.
+ (BOOL)copyGIF:(GSItem *)item;
+ (void)openPost:(GSItem *)item;
+ (void)toggleFavorite:(GSItem *)item;
+ (void)confirmDelete:(GSItem *)item from:(UIViewController *)controller done:(void (^)(void))done;
+ (void)rename:(GSItem *)item from:(UIViewController *)controller done:(void (^)(void))done;
/// A copy of the clip's file under a readable name, for handing to other apps.
+ (nullable NSURL *)exportedFileFor:(GSItem *)item video:(BOOL)video;
+ (UIMenu *)menuForItem:(GSItem *)item from:(UIViewController *)controller view:(UIView *)view changed:(void (^)(void))changed;
+ (void)toast:(NSString *)text;
+ (NSString *)summaryOf:(GSItem *)item;
@end

NS_ASSUME_NONNULL_END
