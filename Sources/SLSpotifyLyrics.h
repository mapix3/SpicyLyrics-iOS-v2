#import <Foundation/Foundation.h>
#import "SLLyrics.h"

NS_ASSUME_NONNULL_BEGIN

/// Ответ Spotify color-lyrics (protobuf или JSON) → наш формат. nil — текста нет.
FOUNDATION_EXPORT SLLyrics *_Nullable SLLyricsFromSpotifyResponse(NSData *data);

/// Наш текст → protobuf в формате color-lyrics, чтобы Spotify показал карточку и строчку текста.
/// lyrics == nil — заглушка (Spotify всё равно покажет карточку, а мы напишем «текст не найден»).
FOUNDATION_EXPORT NSData *SLSpotifyResponseFromLyrics(SLLyrics *_Nullable lyrics);

NS_ASSUME_NONNULL_END
