#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// Подменяет текст Spotify на экране плеера нашим:
/// строчку текста на самом плеере (lyrics preview) и карточку «Текст» ниже.
/// Тап по любой из них открывает полноэкранный Spicy Lyrics.
/// Можно вызывать повторно — уже установленные хуки не дублируются.
FOUNDATION_EXPORT void SLInstallPlayerHooks(void);

NS_ASSUME_NONNULL_END
