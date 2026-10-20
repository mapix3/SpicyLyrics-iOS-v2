#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

/// Динамический фон в стиле Spicy Lyrics: сильно размытая обложка в нескольких вращающихся слоях.
@interface SLBackgroundView : UIView
@property (nonatomic) BOOL animated;
- (void)setArtwork:(nullable UIImage *)image;
@end

NS_ASSUME_NONNULL_END
