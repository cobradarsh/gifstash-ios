#import <UIKit/UIKit.h>
#import "GSStore.h"

NS_ASSUME_NONNULL_BEGIN

/// One clip, large, with the things to do with it.
@interface GSDetailViewController : UIViewController
- (instancetype)initWithItem:(GSItem *)item;
@property (nonatomic, strong, readonly) GSItem *item;
@end

NS_ASSUME_NONNULL_END
