#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@protocol SLBackground <NSObject>
@property (nonatomic) BOOL animated;
- (void)setArtwork:(nullable UIImage *)image;
@end

FOUNDATION_EXPORT NSArray<UIColor *> *_Nullable SLArtworkPalette(UIImage *image);

@interface SLCardBackgroundView : UIView <SLBackground>
@property (nonatomic) BOOL animated;
- (void)setArtwork:(nullable UIImage *)image;
@end

NS_ASSUME_NONNULL_END
