#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

FOUNDATION_EXPORT void SLLog(NSString *format, ...) NS_FORMAT_FUNCTION(1, 2);

FOUNDATION_EXPORT void SLDebugSaveBody(NSString *prefix, NSData *data);

FOUNDATION_EXPORT void SLDebugDumpViews(NSString *name, UIView *root);

FOUNDATION_EXPORT void SLDebugShare(UIViewController *from, UIView *_Nullable sourceView);

NS_ASSUME_NONNULL_END
