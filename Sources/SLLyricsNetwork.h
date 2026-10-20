#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// Перехват запросов текста самого Spotify (color-lyrics/v2):
/// — 404 (у Spotify текста нет) подменяется на 200 с нашим текстом, чтобы Spotify показал
///   строчку и карточку текста на плеере (их мы и перекрываем своими);
/// — 200 запоминается как запасной текст, если у Spicy Lyrics его нет.
FOUNDATION_EXPORT void SLInstallLyricsNetworkHooks(void);

NS_ASSUME_NONNULL_END
