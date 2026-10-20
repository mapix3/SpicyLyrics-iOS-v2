#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@interface SLBackgroundView : UIView
@property (nonatomic) BOOL animated;
- (void)setArtwork:(nullable UIImage *)image;
@end

NS_ASSUME_NONNULL_END
