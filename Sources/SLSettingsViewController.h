#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@interface SLSettingsViewController : UIViewController
/// Показать шторку настроек поверх текущего экрана.
+ (void)presentFrom:(nullable UIViewController *)presenter;
/// Вызывается при нажатии «Перезагрузить текст».
@property (nonatomic, copy, nullable) void (^onReload)(void);
@end

NS_ASSUME_NONNULL_END
