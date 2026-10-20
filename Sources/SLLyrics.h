#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSInteger, SLLyricsType) {
    SLLyricsTypeSyllable = 0,   // тайминг по слогам (Spicy Lyrics / Apple TTML)
    SLLyricsTypeLine = 1,       // тайминг по строкам
    SLLyricsTypeStatic = 2,     // без таймингов
};

@interface SLWord : NSObject
@property (nonatomic, copy) NSString *text;
@property (nonatomic) double start;          // секунды
@property (nonatomic) double end;
@property (nonatomic) BOOL partOfWord;       // YES = без пробела после (слог продолжает слово)
@end

@interface SLLine : NSObject
@property (nonatomic, copy) NSString *text;
@property (nonatomic) double start;
@property (nonatomic) double end;
@property (nonatomic, strong) NSArray<SLWord *> *words;        // основной вокал (пусто для Line/Static)
@property (nonatomic, strong) NSArray<SLWord *> *background;   // бэк-вокал
@property (nonatomic) BOOL oppositeAligned;                    // дуэт — справа
@property (nonatomic) BOOL isInterlude;
@end

@interface SLLyrics : NSObject
@property (nonatomic) SLLyricsType type;
@property (nonatomic, strong) NSArray<SLLine *> *lines;
@property (nonatomic, copy) NSString *source;
@property (nonatomic, strong, nullable) NSArray<NSString *> *songwriters;
// Атрибуция (обязательна по условиям Spicy Lyrics Developer API)
@property (nonatomic, copy, nullable) NSString *uploaderName;
@property (nonatomic, copy, nullable) NSString *uploaderURL;
@property (nonatomic, copy, nullable) NSString *makerName;
@property (nonatomic, copy, nullable) NSString *makerURL;
/// Текст взят у самого Spotify (у Spicy Lyrics его нет)
@property (nonatomic) BOOL fromSpotify;

/// Body ответа Spicy Lyrics Developer API: {Type: Syllable|Line|Static, source, UploadAttribution, ...}
+ (nullable instancetype)lyricsFromSpicyJSON:(NSDictionary *)json duration:(double)duration;
@end

NS_ASSUME_NONNULL_END
