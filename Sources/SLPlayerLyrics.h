#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// Подменяет строчку текста Spotify прямо на плеере (lyrics preview) нашей.
/// Тап по любой из них открывает полноэкранный Spicy Lyrics.
/// Можно вызывать повторно — уже установленные хуки не дублируются.
FOUNDATION_EXPORT void SLInstallPlayerHooks(void);

/// Наше окно текста первой карточкой под плеером (вместо карточки текста Spotify, для любого трека).
FOUNDATION_EXPORT void SLInstallVirtualCard(void);

/// Диагностика: дампы экрана плеера.
FOUNDATION_EXPORT void SLInstallDebugHooks(void);


NS_ASSUME_NONNULL_END
