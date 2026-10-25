#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@interface SLUpdateInfo : NSObject
@property (nonatomic, copy) NSString *version;
@property (nonatomic, copy, nullable) NSString *notes;
@property (nonatomic, copy, nullable) NSString *ipa;
@property (nonatomic, copy, nullable) NSString *url;
@end

@interface SLUpdates : NSObject
+ (NSString *)currentVersion;
+ (void)checkOnLaunch;
+ (void)check:(void (^)(SLUpdateInfo *_Nullable info, BOOL failed))completion;
+ (void)presentUpdate:(SLUpdateInfo *)info from:(nullable UIViewController *)presenter;
@end

NS_ASSUME_NONNULL_END
