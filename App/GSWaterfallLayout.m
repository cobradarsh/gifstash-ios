#import "GSWaterfallLayout.h"

@implementation GSWaterfallLayout {
    NSMutableArray<UICollectionViewLayoutAttributes *> *_attributes;
    CGFloat _height;
    CGFloat _preparedWidth;
}

- (instancetype)init {
    if ((self = [super init])) {
        _columns = 2;
        _spacing = 10;
        _insets = UIEdgeInsetsMake(8, 12, 12, 12);
        _attributes = [NSMutableArray new];
    }
    return self;
}

- (void)prepareLayout {
    [super prepareLayout];
    [_attributes removeAllObjects];
    UICollectionView *view = self.collectionView;
    const CGFloat width = view.bounds.size.width;
    _preparedWidth = width;
    const NSInteger columns = MAX(1, self.columns);
    const CGFloat tile = floor((width - self.insets.left - self.insets.right - self.spacing * (columns - 1)) / columns);
    CGFloat bottoms[8];
    const NSInteger used = MIN(columns, 8);
    for (NSInteger i = 0; i < used; i++) bottoms[i] = self.insets.top;

    const NSInteger count = view.numberOfSections > 0 ? [view numberOfItemsInSection:0] : 0;
    for (NSInteger index = 0; index < count; index++) {
        NSInteger column = 0;
        for (NSInteger i = 1; i < used; i++) {
            if (bottoms[i] < bottoms[column] - 0.5) column = i;
        }
        CGFloat aspect = [self.source waterfallAspectAtIndex:index];
        if (!(aspect > 0)) aspect = 1;
        aspect = MAX(0.5, MIN(1.9, aspect));
        const CGFloat height = round(tile * aspect);
        UICollectionViewLayoutAttributes *attributes =
            [UICollectionViewLayoutAttributes layoutAttributesForCellWithIndexPath:[NSIndexPath indexPathForItem:index inSection:0]];
        attributes.frame = CGRectMake(self.insets.left + column * (tile + self.spacing), bottoms[column], tile, height);
        [_attributes addObject:attributes];
        bottoms[column] += height + self.spacing;
    }
    CGFloat tallest = self.insets.top;
    for (NSInteger i = 0; i < used; i++) tallest = MAX(tallest, bottoms[i]);
    _height = tallest - (count > 0 ? self.spacing : 0) + self.insets.bottom;
}

- (CGSize)collectionViewContentSize {
    return CGSizeMake(_preparedWidth, _height);
}

- (NSArray<UICollectionViewLayoutAttributes *> *)layoutAttributesForElementsInRect:(CGRect)rect {
    NSMutableArray *found = [NSMutableArray new];
    for (UICollectionViewLayoutAttributes *attributes in _attributes) {
        if (CGRectIntersectsRect(attributes.frame, rect)) [found addObject:attributes];
    }
    return found;
}

- (UICollectionViewLayoutAttributes *)layoutAttributesForItemAtIndexPath:(NSIndexPath *)indexPath {
    return indexPath.item < (NSInteger)_attributes.count ? _attributes[indexPath.item] : nil;
}

- (BOOL)shouldInvalidateLayoutForBoundsChange:(CGRect)newBounds {
    return fabs(newBounds.size.width - _preparedWidth) > 0.5;
}

@end
