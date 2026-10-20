#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// Подменяет текст Spotify на экране плеера нашим:
/// строчку текста на самом плеере (lyrics preview) и карточку «Текст» ниже.
/// Тап по любой из них открывает полноэкранный Spicy Lyrics.
/// Можно вызывать повторно — уже установленные хуки не дублируются.
FOUNDATION_EXPORT void SLInstallPlayerHooks(void);

/// Включает в конфиге Spotify запрос текста для всех треков. Ставится как можно раньше.
FOUNDATION_EXPORT void SLInstallLyricsConfigHook(void);

/// Диагностика: дампы экрана плеера.
FOUNDATION_EXPORT void SLInstallDebugHooks(void);

/// has_lyrics = true для музыкальных треков — иначе Spotify не показывает карточку/строчку текста
/// для треков, у которых нет его собственного текста.
FOUNDATION_EXPORT void SLInstallHasLyricsHooks(void);

NS_ASSUME_NONNULL_END
