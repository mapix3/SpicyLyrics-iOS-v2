#import <Foundation/Foundation.h>
#import "SLLyrics.h"

NS_ASSUME_NONNULL_BEGIN

typedef void (^SLLyricsCompletion)(SLLyrics *_Nullable lyrics, NSString *_Nullable error);

extern NSNotificationName const SLLyricsDidLoadNotification;          // object: trackKey
extern NSNotificationName const SLSpotifyLyricsDidLoadNotification;   // object: track id

@interface SLLyricsProvider : NSObject
+ (instancetype)shared;

/// Хук сетевых запросов Spotify: забираем Bearer-токен и id треков из запросов текста.
- (void)observeRequest:(NSURLRequest *)request;
- (BOOL)hasSpotifyToken;
- (void)clearCache;

/// Уже загруженный текст (без сети).
- (nullable SLLyrics *)cachedLyricsForKey:(NSString *)key;

- (void)lyricsForTitle:(NSString *)title
                artist:(NSString *)artist
                 album:(nullable NSString *)album
              duration:(double)duration
              trackURI:(nullable NSString *)uri
              trackKey:(NSString *)key
            completion:(SLLyricsCompletion)completion;

/// Только Spicy Lyrics по id трека Spotify (с кэшем). completion — на главном потоке.
- (void)spicyLyricsForTrackId:(nullable NSString *)trackId completion:(SLLyricsCompletion)completion;

/// Ответ color-lyrics, который Spotify получил сам, — запоминаем как запасной текст.
- (void)storeSpotifyResponse:(NSData *)data trackId:(NSString *)trackId;
@end

NS_ASSUME_NONNULL_END
