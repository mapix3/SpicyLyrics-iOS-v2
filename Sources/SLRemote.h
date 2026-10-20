#import <MediaPlayer/MediaPlayer.h>

NS_ASSUME_NONNULL_BEGIN

@interface SLRemote : NSObject
+ (void)command:(MPRemoteCommand *)cmd addedTarget:(id)target action:(SEL)action;
+ (void)command:(MPRemoteCommand *)cmd addedHandler:(id)handler token:(id)token;
+ (void)command:(MPRemoteCommand *)cmd removedTarget:(nullable id)target;

+ (BOOL)seekTo:(double)seconds;
+ (BOOL)togglePlayPause;
@end

NS_ASSUME_NONNULL_END
