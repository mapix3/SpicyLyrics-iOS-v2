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
@property (nonatomic, copy, readonly, nullable) NSString *trackURI;   // spotify:track:..., если удалось найти
@property (nonatomic, readonly) double duration;
@property (nonatomic, strong, readonly, nullable) UIImage *artwork;
@property (nonatomic, readonly) BOOL isPlaying;
@property (nonatomic, copy, readonly, nullable) NSString *trackKey;   // title|artist|duration

/// Текущая позиция с учётом времени с последнего обновления и сдвига из настроек.
- (double)currentTime;

/// Вызывается из хука MPNowPlayingInfoCenter.
/// stamp — CACurrentMediaTime() в момент, когда Spotify сообщил позицию (до перехода в главный поток).
- (void)updateWithInfo:(nullable NSDictionary *)info stamp:(CFTimeInterval)stamp;
- (void)updatePlaybackState:(NSInteger)state stamp:(CFTimeInterval)stamp; // MPNowPlayingPlaybackState
/// Оптимистично выставить позицию после перемотки.
- (void)setElapsedLocally:(double)elapsed;
/// Подтянуть данные напрямую из MPNowPlayingInfoCenter (если хук пропустил).
- (void)refreshFromCenter;
@end

NS_ASSUME_NONNULL_END
