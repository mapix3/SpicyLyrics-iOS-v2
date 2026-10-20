#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@interface SLSettingsViewController : UIViewController
+ (void)presentFrom:(nullable UIViewController *)presenter;
@property (nonatomic, copy, nullable) void (^onReload)(void);
@end

NS_ASSUME_NONNULL_END
