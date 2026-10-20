#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

extern NSNotificationName const SLSettingsDidChangeNotification;

@interface SLSettings : NSObject
+ (instancetype)shared;
@property (nonatomic) NSInteger syncOffsetMs;
@property (nonatomic) CGFloat fontScale;
@property (nonatomic) BOOL dynamicBackground;
@property (nonatomic) BOOL showBubble;
@property (nonatomic) BOOL wordGlow;
@property (nonatomic) BOOL showBackgroundVocals;
@property (nonatomic) CGPoint bubbleCenter;   // {0,0} = по умолчанию
@end

NS_ASSUME_NONNULL_END
