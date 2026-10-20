#import <Foundation/Foundation.h>

/// 120 Гц на ProMotion: без CADisableMinimumFrameDurationOnPhone в Info.plist система режет приложению
/// анимации до 60 к/с. У Spotify ключа нет — добавляем его в Info.plist главного бандла при запуске.
FOUNDATION_EXPORT void SLEnableProMotion(void);
