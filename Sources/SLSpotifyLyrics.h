#import <Foundation/Foundation.h>
#import "SLLyrics.h"

NS_ASSUME_NONNULL_BEGIN

/// Ответ Spotify color-lyrics (protobuf или JSON) → наш формат. nil — текста нет.
FOUNDATION_EXPORT SLLyrics *_Nullable SLLyricsFromSpotifyResponse(NSData *data);

NS_ASSUME_NONNULL_END
