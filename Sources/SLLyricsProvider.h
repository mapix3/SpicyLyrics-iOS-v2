#import <Foundation/Foundation.h>
#import "SLLyrics.h"

NS_ASSUME_NONNULL_BEGIN

typedef void (^SLLyricsCompletion)(SLLyrics *_Nullable lyrics, NSString *_Nullable error);

extern NSNotificationName const SLLyricsDidLoadNotification;
extern NSNotificationName const SLSpotifyLyricsDidLoadNotification;

@interface SLLyricsProvider : NSObject
+ (instancetype)shared;

- (void)observeRequest:(NSURLRequest *)request;
- (BOOL)hasSpotifyToken;
- (void)clearCache;

- (nullable SLLyrics *)cachedLyricsForKey:(NSString *)key;

- (void)lyricsForTitle:(NSString *)title
                artist:(NSString *)artist
                 album:(nullable NSString *)album
              duration:(double)duration
              trackURI:(nullable NSString *)uri
              trackKey:(NSString *)key
            completion:(SLLyricsCompletion)completion;

- (void)spicyLyricsForTrackId:(nullable NSString *)trackId completion:(SLLyricsCompletion)completion;

- (void)storeSpotifyResponse:(NSData *)data trackId:(NSString *)trackId;
@end

NS_ASSUME_NONNULL_END
