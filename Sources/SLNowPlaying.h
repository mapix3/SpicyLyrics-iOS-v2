#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

extern NSNotificationName const SLTrackDidChangeNotification;
extern NSNotificationName const SLPlaybackDidChangeNotification;
extern NSNotificationName const SLArtworkDidChangeNotification;

@interface SLNowPlaying : NSObject
+ (instancetype)shared;

@property (nonatomic, copy, readonly, nullable) NSString *title;
@property (nonatomic, copy, readonly, nullable) NSString *artist;
@property (nonatomic, copy, readonly, nullable) NSString *album;
@property (nonatomic, copy, readonly, nullable) NSString *trackURI;
@property (nonatomic, readonly) double duration;
@property (nonatomic, strong, readonly, nullable) UIImage *artwork;
@property (nonatomic, readonly) BOOL isPlaying;
@property (nonatomic, copy, readonly, nullable) NSString *trackKey;

- (double)currentTime;

- (void)updateWithInfo:(nullable NSDictionary *)info stamp:(CFTimeInterval)stamp;
- (void)updatePlaybackState:(NSInteger)state stamp:(CFTimeInterval)stamp;
- (void)setElapsedLocally:(double)elapsed;
- (void)refreshFromCenter;
@end

NS_ASSUME_NONNULL_END
