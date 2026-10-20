#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

/// Диагностика: лог и дампы в Documents/SpicyLyricsiOS-debug внутри контейнера Spotify.
FOUNDATION_EXPORT void SLLog(NSString *format, ...) NS_FORMAT_FUNCTION(1, 2);

/// Сохранить тело ответа (не больше нескольких файлов на префикс).
FOUNDATION_EXPORT void SLDebugSaveBody(NSString *prefix, NSData *data);

/// Дамп иерархии вьюх (классы, фреймы) в файл.
FOUNDATION_EXPORT void SLDebugDumpViews(NSString *name, UIView *root);

/// Поделиться всеми файлами диагностики (шторка «Поделиться»).
FOUNDATION_EXPORT void SLDebugShare(UIViewController *from, UIView *_Nullable sourceView);

NS_ASSUME_NONNULL_END
