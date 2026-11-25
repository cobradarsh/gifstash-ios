#import <UIKit/UIKit.h>
#import "GSStore.h"

NS_ASSUME_NONNULL_BEGIN

/// The still picture of a clip, decoded off the main thread and kept for the next time.
void GSLoadPoster(GSItem *item, void (^done)(UIImage *_Nullable image));

@interface GSGifCell : UICollectionViewCell
@property (nonatomic, strong, readonly, nullable) GSItem *item;
- (void)showItem:(GSItem *)item;
- (void)startPlaying;
- (void)stopPlaying;
@end

NS_ASSUME_NONNULL_END
