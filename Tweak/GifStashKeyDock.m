// The button in the bar under the keyboard (UIKeyboardDockView: the strip with the globe key on iPhones without
// a Home button). It goes to the left of whatever sits on the right of that bar: the dictation key, or the button
// another tweak has put there.
#import "GifStashKey.h"
#import <objc/runtime.h>

static const CGFloat kSide = 30;            // points; the size other tweaks' tiles in this bar have
static const CGFloat kStep = 58;            // centre to centre, from the item on the right
static char kButtonKey;
static IMP gOriginalLayout;
static NSHashTable<UIView *> *gDocks;      // every keyboard bar seen and still alive
static UIImage *gIcon;
static UIColor *gAccent;
static NSDate *gIconDate;

#pragma mark - The icon

static UIImage *DrawnIcon(void) {
    // Only when no picture of the app could be found: a dark tile that says GIF.
    UIGraphicsImageRenderer *renderer = [[UIGraphicsImageRenderer alloc] initWithSize:CGSizeMake(60, 60)];
    return [renderer imageWithActions:^(UIGraphicsImageRendererContext *context) {
        [[UIColor colorWithWhite:0.10 alpha:1] setFill];
        [[UIBezierPath bezierPathWithRoundedRect:CGRectMake(0, 0, 60, 60) cornerRadius:14] fill];
        NSDictionary *attributes = @{NSFontAttributeName: [UIFont systemFontOfSize:22 weight:UIFontWeightHeavy],
                                     NSForegroundColorAttributeName: [UIColor colorWithRed:1.0 green:0.80 blue:0.42 alpha:1]};
        CGSize size = [@"GIF" sizeWithAttributes:attributes];
        [@"GIF" drawAtPoint:CGPointMake((60 - size.width) / 2, (60 - size.height) / 2) withAttributes:attributes];
    }];
}

/// The average of the picture's bright pixels: gold for a gold icon, pink for the app's own.
static UIColor *AccentOf(UIImage *image) {
    const size_t side = 24;
    uint8_t pixels[24 * 24 * 4];
    memset(pixels, 0, sizeof(pixels));
    CGColorSpaceRef space = CGColorSpaceCreateDeviceRGB();
    CGContextRef context = CGBitmapContextCreate(pixels, side, side, 8, side * 4, space, kCGImageAlphaPremultipliedLast | kCGBitmapByteOrder32Big);
    CGColorSpaceRelease(space);
    if (!context || !image.CGImage) {
        if (context) CGContextRelease(context);
        return [UIColor colorWithRed:1.0 green:0.80 blue:0.42 alpha:1];
    }
    CGContextDrawImage(context, CGRectMake(0, 0, side, side), image.CGImage);
    CGContextRelease(context);
    double r = 0, g = 0, b = 0, weight = 0;
    for (size_t i = 0; i < side * side; i++) {
        const double red = pixels[i * 4] / 255.0, green = pixels[i * 4 + 1] / 255.0, blue = pixels[i * 4 + 2] / 255.0;
        const double high = MAX(red, MAX(green, blue)), low = MIN(red, MIN(green, blue));
        if (pixels[i * 4 + 3] < 128 || high < 0.45) continue;
        const double w = 0.2 + (high - low);        // colourful pixels count for more than white ones
        r += red * w; g += green * w; b += blue * w; weight += w;
    }
    if (weight <= 0) return [UIColor colorWithRed:1.0 green:0.80 blue:0.42 alpha:1];
    r /= weight; g /= weight; b /= weight;
    const double high = MAX(r, MAX(g, b));
    if (high > 0 && high < 0.9) { const double lift = 0.9 / high; r *= lift; g *= lift; b *= lift; }
    return [UIColor colorWithRed:MIN(1, r) green:MIN(1, g) blue:MIN(1, b) alpha:1];
}

static void LoadIcon(void) {
    NSString *path = [GifStashKeyMirror() stringByAppendingPathComponent:@"icon.png"];
    NSDate *date = [NSFileManager.defaultManager attributesOfItemAtPath:path error:NULL].fileModificationDate;
    if (gIcon && ((!date && !gIconDate) || [date isEqualToDate:gIconDate])) return;
    UIImage *image = date ? [UIImage imageWithContentsOfFile:path] : nil;
    gIconDate = image ? date : nil;
    gIcon = image ?: DrawnIcon();
    gAccent = AccentOf(gIcon);
}

UIImage *GifStashKeyIcon(void) {
    LoadIcon();
    return gIcon;
}

UIColor *GifStashKeyAccent(void) {
    LoadIcon();
    return gAccent;
}

#pragma mark - The button

@interface GifStashKeyTarget : NSObject
+ (instancetype)shared;
- (void)tapped:(UIButton *)button;
@end

@implementation GifStashKeyTarget
+ (instancetype)shared {
    static GifStashKeyTarget *target;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ target = [GifStashKeyTarget new]; });
    return target;
}

- (void)tapped:(UIButton *)button {
    UIView *dock = button.superview;
    if (!dock) return;
    [[UIImpactFeedbackGenerator new] impactOccurred];
    [GifStashKeyPanel toggleFromDock:dock];
}
@end

NSArray<UIView *> *GifStashKeyDocks(void) {
    return gDocks.allObjects ?: @[];
}

UIView *GifStashKeyCurrentDock(void) {
    // iOS keeps more than one keyboard bar (a stand-in in the text effects window, the real one in the keyboard's
    // own window above it): the one in front is the one on screen.
    UIView *front = nil;
    for (UIView *dock in GifStashKeyDocks()) {
        UIWindow *window = dock.window;
        if (!window || window.hidden || dock.hidden) continue;
        if (!front || window.windowLevel > front.window.windowLevel) front = dock;
    }
    return front;
}

UIButton *GifStashKeyButtonInDock(UIView *dock) {
    return objc_getAssociatedObject(dock, &kButtonKey);
}

/// Where the drawing of a bar item is, in the bar's coordinates: its picture if it is a button with one.
static CGRect GlyphRect(UIView *item, UIView *dock) {
    if ([item isKindOfClass:UIButton.class]) {
        UIImageView *picture = ((UIButton *)item).imageView;
        if (picture.image && picture.bounds.size.width > 1 && picture.bounds.size.height > 1) {
            return [dock convertRect:picture.bounds fromView:picture];
        }
    }
    return [dock convertRect:item.bounds fromView:item];
}

static void PlaceButton(UIView *dock) {
    const CGRect bounds = dock.bounds;
    if (bounds.size.width < 200 || bounds.size.height < 20) return;
    if (!gDocks) gDocks = [NSHashTable weakObjectsHashTable];
    [gDocks addObject:dock];

    UIButton *button = objc_getAssociatedObject(dock, &kButtonKey);
    if (!button) {
        button = [UIButton buttonWithType:UIButtonTypeCustom];
        button.adjustsImageWhenHighlighted = YES;
        button.imageView.contentMode = UIViewContentModeScaleAspectFit;
        button.imageView.layer.cornerRadius = kSide * 0.235;
        button.imageView.layer.cornerCurve = kCACornerCurveContinuous;
        button.imageView.clipsToBounds = YES;
        button.contentHorizontalAlignment = UIControlContentHorizontalAlignmentFill;
        button.contentVerticalAlignment = UIControlContentVerticalAlignmentFill;
        button.accessibilityLabel = @"GIF Stash";
        [button addTarget:GifStashKeyTarget.shared action:@selector(tapped:) forControlEvents:UIControlEventTouchUpInside];
        objc_setAssociatedObject(dock, &kButtonKey, button, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    UIImage *icon = GifStashKeyIcon();
    if ([button imageForState:UIControlStateNormal] != icon) [button setImage:icon forState:UIControlStateNormal];
    if (button.superview != dock) [dock addSubview:button];
    if (dock.subviews.lastObject != button && ![dock.subviews.lastObject isKindOfClass:GifStashKeyPanel.class]) {
        [dock bringSubviewToFront:button];
    }

    // What else is in the bar: the nearest thing on the right half, and the globe on the left.
    UIView *right = nil, *left = nil;
    CGRect rightGlyph = CGRectZero, leftGlyph = CGRectZero;
    for (UIView *item in dock.subviews) {
        if (item == button || item.hidden || item.alpha < 0.05 || ![item isKindOfClass:UIControl.class]) continue;
        if (item.bounds.size.width < 4 || item.bounds.size.height < 4) continue;
        const CGRect glyph = GlyphRect(item, dock);
        if (CGRectGetMidX(glyph) > CGRectGetMidX(bounds)) {
            if (!right || CGRectGetMidX(glyph) < CGRectGetMidX(rightGlyph)) { right = item; rightGlyph = glyph; }
        } else {
            if (!left || CGRectGetMidX(glyph) < CGRectGetMidX(leftGlyph)) { left = item; leftGlyph = glyph; }
        }
    }
    CGPoint centre;
    if (right) {
        centre = CGPointMake(CGRectGetMidX(rightGlyph) - kStep, CGRectGetMidY(rightGlyph));
    } else if (left) {
        // Nothing on the right: take the place across from the globe.
        centre = CGPointMake(bounds.size.width - CGRectGetMidX(leftGlyph), CGRectGetMidY(leftGlyph));
    } else {
        centre = CGPointMake(bounds.size.width - 46, CGRectGetMidY(bounds));
    }
    centre.x = MAX(CGRectGetMidX(bounds) + kSide, MIN(bounds.size.width - kSide / 2 - 4, centre.x));
    // A larger touch area than the picture, like the bar's own keys.
    const CGFloat reach = 7;
    const CGRect frame = CGRectMake(round(centre.x - kSide / 2 - reach), round(centre.y - kSide / 2 - reach),
                                    kSide + reach * 2, kSide + reach * 2);
    if (!CGRectEqualToRect(button.frame, frame)) button.frame = frame;
    const UIEdgeInsets insets = UIEdgeInsetsMake(reach, reach, reach, reach);
    if (!UIEdgeInsetsEqualToEdgeInsets(button.imageEdgeInsets, insets)) button.imageEdgeInsets = insets;
}

static void DockLayout(UIView *self, SEL _cmd) {
    if (gOriginalLayout) ((void (*)(id, SEL))gOriginalLayout)(self, _cmd);
    @try {
        PlaceButton(self);
    } @catch (NSException *exception) {
        GifStashKeyLog(@"layout: %@", exception);
    }
}

void GifStashKeyInstallDock(void) {
    Class dockClass = NSClassFromString(@"UIKeyboardDockView");
    if (!dockClass) return;
    SEL selector = @selector(layoutSubviews);
    Method method = class_getInstanceMethod(dockClass, selector);
    if (!method) return;
    gOriginalLayout = method_getImplementation(method);
    // If the class only inherits the method, give it its own rather than changing UIView's.
    if (!class_addMethod(dockClass, selector, (IMP)DockLayout, method_getTypeEncoding(method))) {
        method_setImplementation(method, (IMP)DockLayout);
    }
}
