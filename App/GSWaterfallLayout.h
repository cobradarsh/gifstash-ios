#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@protocol GSWaterfallSource <NSObject>
/// Height over width of the tile at `index`.
- (CGFloat)waterfallAspectAtIndex:(NSInteger)index;
@end

/// Columns of tiles that keep each clip's own shape; the next tile goes into the shortest column.
@interface GSWaterfallLayout : UICollectionViewLayout
@property (nonatomic, weak, nullable) id<GSWaterfallSource> source;
@property (nonatomic) NSInteger columns;
@property (nonatomic) CGFloat spacing;
@property (nonatomic) UIEdgeInsets insets;
@end

NS_ASSUME_NONNULL_END
