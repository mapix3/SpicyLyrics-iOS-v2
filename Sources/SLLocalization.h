#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// Язык интерфейса твика = язык интерфейса Spotify (локализация его бандла,
/// учитывает и язык приложения в настройках iOS). Нет перевода строки — английский.
FOUNDATION_EXPORT NSString *SLLanguage(void);

/// Строка интерфейса по ключу.
FOUNDATION_EXPORT NSString *SLLoc(NSString *key);

/// Строка-формат по ключу + аргументы.
FOUNDATION_EXPORT NSString *SLLocFormat(NSString *key, ...);

NS_ASSUME_NONNULL_END
