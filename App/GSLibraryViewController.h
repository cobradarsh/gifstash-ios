#import <UIKit/UIKit.h>
#import "GSStore.h"

NS_ASSUME_NONNULL_BEGIN

/// The home screen: every saved clip, playing.
@interface GSLibraryViewController : UIViewController
@property (nonatomic, copy, readonly) NSArray<GSItem *> *shownItems;
@property (nonatomic, readonly) BOOL isImporting;
/// Saves the clip(s) of the post that `text` links to.
- (void)importText:(NSString *)text;
/// The same, telling the caller how it went (used by the test hooks).
- (void)importText:(NSString *)text quietly:(BOOL)quietly
        completion:(nullable void (^)(NSArray<GSItem *> *items, NSError *_Nullable error))completion;
- (void)reload;
- (BOOL)openItemWithID:(NSString *)itemID;
@end

NS_ASSUME_NONNULL_END
