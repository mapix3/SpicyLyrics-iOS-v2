#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@interface SLLyricsViewController : UIViewController
+ (void)presentFromTopController;
+ (BOOL)isPresented;
+ (void)installOrientationSupport;
@end

NS_ASSUME_NONNULL_END
