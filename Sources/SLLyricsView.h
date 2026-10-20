#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSInteger, SLLyricsViewMode) {
    SLLyricsViewModeFull = 0,      // полноэкранный текст
    SLLyricsViewModeCompact = 1,   // карточка на экране плеера
};

/// Самодостаточный экран текста: сам грузит текст текущего трека, синхронизирует и скроллит.
@interface SLLyricsView : UIView
- (instancetype)initWithMode:(SLLyricsViewMode)mode;

@property (nonatomic, readonly) SLLyricsViewMode mode;
@property (nonatomic, readonly) BOOL hasLyrics;
@property (nonatomic) BOOL showsBackground;       // динамический фон из обложки
@property (nonatomic) BOOL interactive;           // скролл, тап по строке = перемотка
@property (nonatomic) UIEdgeInsets contentInsets; // отступы текста от краёв
/// Вызывается, когда текст появился/пропал (чтобы хост показал/скрыл оригинальный UI Spotify).
@property (nonatomic, copy, nullable) void (^availabilityChanged)(BOOL hasLyrics);

- (void)reload;          // перезагрузить текст (без кэша)
- (void)resync;          // вернуться к текущей строке
@end

NS_ASSUME_NONNULL_END
