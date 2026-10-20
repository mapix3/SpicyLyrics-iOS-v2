#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// Перехват запросов текста самого Spotify (color-lyrics/v2): ответ 200 запоминается
/// как запасной текст, если у Spicy Lyrics его нет.
FOUNDATION_EXPORT void SLInstallLyricsNetworkHooks(void);

NS_ASSUME_NONNULL_END
