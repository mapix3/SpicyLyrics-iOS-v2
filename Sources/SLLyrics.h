#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSInteger, SLLyricsType) {
    SLLyricsTypeSyllable = 0,
    SLLyricsTypeLine = 1,
    SLLyricsTypeStatic = 2,
};

@interface SLWord : NSObject
@property (nonatomic, copy) NSString *text;
@property (nonatomic) double start;
@property (nonatomic) double end;
@property (nonatomic) BOOL partOfWord;
@end

@interface SLLine : NSObject
@property (nonatomic, copy) NSString *text;
@property (nonatomic) double start;
@property (nonatomic) double end;
@property (nonatomic, strong) NSArray<SLWord *> *words;
@property (nonatomic, strong) NSArray<SLWord *> *background;
@property (nonatomic) BOOL oppositeAligned;
@property (nonatomic) BOOL isInterlude;
@end

@interface SLLyrics : NSObject
@property (nonatomic) SLLyricsType type;
@property (nonatomic, strong) NSArray<SLLine *> *lines;
@property (nonatomic, copy) NSString *source;
@property (nonatomic, strong, nullable) NSArray<NSString *> *songwriters;
@property (nonatomic, copy, nullable) NSString *uploaderName;
@property (nonatomic, copy, nullable) NSString *uploaderURL;
@property (nonatomic, copy, nullable) NSString *makerName;
@property (nonatomic, copy, nullable) NSString *makerURL;
@property (nonatomic) BOOL fromSpotify;

+ (nullable instancetype)lyricsFromSpicyJSON:(NSDictionary *)json duration:(double)duration;
@end

NS_ASSUME_NONNULL_END
