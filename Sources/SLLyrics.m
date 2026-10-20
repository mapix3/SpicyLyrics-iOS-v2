#import "SLLyrics.h"
#import "SLLocalization.h"

@implementation SLWord
@end

@implementation SLLine
@end

static const double SLInterludeMinGap = 3.0;   // как getLyricsBetweenShow() в Spicy Lyrics

static NSString *SLTrim(NSString *s) {
    return [s ?: @"" stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
}

static BOOL SLIsInstrumentalText(NSString *t) {
    NSString *s = SLTrim(t);
    if (s.length == 0) return YES;
    NSCharacterSet *notes = [NSCharacterSet characterSetWithCharactersInString:@"♪♫♬♩🎵🎶 .…-–—*•"];
    return [[s stringByTrimmingCharactersInSet:notes] length] == 0;
}

static double SLNum(id v, double def) {
    return [v respondsToSelector:@selector(doubleValue)] ? [v doubleValue] : def;
}

static NSString *SLStr(id v) {
    return [v isKindOfClass:[NSString class]] ? v : @"";
}

static SLLine *SLInterlude(double start, double end, BOOL opposite) {
    SLLine *l = [SLLine new];
    l.isInterlude = YES;
    l.text = @"";
    l.words = @[];
    l.background = @[];
    l.start = start;
    l.end = end;
    l.oppositeAligned = opposite;
    return l;
}

/// Добавляет интерлюдии во вступление и в паузы >= 3 с.
static NSArray<SLLine *> *SLWithInterludes(NSArray<SLLine *> *lines) {
    NSMutableArray *out = [NSMutableArray array];
    for (NSUInteger i = 0; i < lines.count; i++) {
        SLLine *l = lines[i];
        if (i == 0 && l.start >= SLInterludeMinGap) [out addObject:SLInterlude(0, l.start, l.oppositeAligned)];
        [out addObject:l];
        if (i + 1 < lines.count) {
            SLLine *n = lines[i + 1];
            if (n.start - l.end >= SLInterludeMinGap) [out addObject:SLInterlude(l.end, n.start, n.oppositeAligned)];
        }
    }
    return out;
}

static NSArray<SLWord *> *SLParseSyllables(id arr) {
    if (![arr isKindOfClass:[NSArray class]]) return @[];
    NSMutableArray *out = [NSMutableArray array];
    for (NSDictionary *s in arr) {
        if (![s isKindOfClass:[NSDictionary class]]) continue;
        NSString *text = SLStr(s[@"Text"]);
        if (text.length == 0) continue;
        SLWord *w = [SLWord new];
        w.text = text;
        w.start = SLNum(s[@"StartTime"], 0);
        w.end = MAX(SLNum(s[@"EndTime"], w.start), w.start + 0.01);
        w.partOfWord = [s[@"IsPartOfWord"] boolValue];
        [out addObject:w];
    }
    return out;
}

static NSString *SLJoinWords(NSArray<SLWord *> *words) {
    NSMutableString *s = [NSMutableString string];
    for (NSUInteger i = 0; i < words.count; i++) {
        [s appendString:words[i].text];
        if (!words[i].partOfWord && i + 1 < words.count) [s appendString:@" "];
    }
    return s;
}

@implementation SLLyrics

#pragma mark - Spicy Lyrics API

+ (instancetype)lyricsFromSpicyJSON:(NSDictionary *)json duration:(double)duration {
    if (![json isKindOfClass:[NSDictionary class]]) return nil;
    NSString *type = SLStr(json[@"Type"]);
    SLLyrics *ly = [SLLyrics new];
    // провайдер берём из каждого ответа — у одного трека он может меняться
    NSString *provider = SLStr(json[@"source"]);
    if ([provider isEqualToString:@"spicy_lyrics"]) ly.source = @"Spicy Lyrics";
    else if ([provider isEqualToString:@"apple_music"]) ly.source = SLLocFormat(@"via_spicy", @"Apple Music");
    else if ([provider isEqualToString:@"spotify"]) ly.source = SLLocFormat(@"via_spicy", @"Spotify");
    else ly.source = provider.length ? SLLocFormat(@"via_spicy", provider) : @"Spicy Lyrics";
    if ([json[@"SongWriters"] isKindOfClass:[NSArray class]]) ly.songwriters = json[@"SongWriters"];
    NSDictionary *attr = json[@"UploadAttribution"];
    if ([attr isKindOfClass:[NSDictionary class]]) {
        NSDictionary *up = attr[@"Uploader"], *mk = attr[@"Maker"];
        if ([up isKindOfClass:[NSDictionary class]]) { ly.uploaderName = SLStr(up[@"username"]); ly.uploaderURL = SLStr(up[@"url"]); }
        if ([mk isKindOfClass:[NSDictionary class]]) { ly.makerName = SLStr(mk[@"username"]); ly.makerURL = SLStr(mk[@"url"]); }
    }

    if ([type isEqualToString:@"Syllable"]) {
        NSMutableArray *lines = [NSMutableArray array];
        for (NSDictionary *c in json[@"Content"]) {
            if (![c isKindOfClass:[NSDictionary class]]) continue;
            NSDictionary *lead = c[@"Lead"];
            if (![lead isKindOfClass:[NSDictionary class]]) continue;
            NSArray<SLWord *> *words = SLParseSyllables(lead[@"Syllables"]);
            if (!words.count) continue;
            NSMutableArray<SLWord *> *bg = [NSMutableArray array];
            if ([c[@"Background"] isKindOfClass:[NSArray class]]) {
                for (NSDictionary *b in c[@"Background"]) {
                    if ([b isKindOfClass:[NSDictionary class]]) [bg addObjectsFromArray:SLParseSyllables(b[@"Syllables"])];
                }
            }
            SLLine *l = [SLLine new];
            l.words = words;
            l.background = bg;
            l.text = SLJoinWords(words);
            l.oppositeAligned = [c[@"OppositeAligned"] boolValue];
            l.start = MIN(SLNum(lead[@"StartTime"], words.firstObject.start), words.firstObject.start);
            double end = MAX(SLNum(lead[@"EndTime"], words.lastObject.end), words.lastObject.end);
            if (bg.count) end = MAX(end, bg.lastObject.end);
            l.end = end;
            [lines addObject:l];
        }
        if (!lines.count) return nil;
        ly.type = SLLyricsTypeSyllable;
        ly.lines = SLWithInterludes(lines);
        return ly;
    }

    if ([type isEqualToString:@"Line"]) {
        NSMutableArray *lines = [NSMutableArray array];
        for (NSDictionary *c in json[@"Content"]) {
            if (![c isKindOfClass:[NSDictionary class]]) continue;
            NSString *text = SLTrim(SLStr(c[@"Text"]));
            if (SLIsInstrumentalText(text)) continue;
            SLLine *l = [SLLine new];
            l.text = text;
            l.words = @[];
            l.background = @[];
            l.start = SLNum(c[@"StartTime"], 0);
            l.end = MAX(SLNum(c[@"EndTime"], l.start), l.start + 0.1);
            l.oppositeAligned = [c[@"OppositeAligned"] boolValue];
            [lines addObject:l];
        }
        if (!lines.count) return nil;
        ly.type = SLLyricsTypeLine;
        ly.lines = SLWithInterludes(lines);
        return ly;
    }

    if ([type isEqualToString:@"Static"]) {
        NSMutableArray *lines = [NSMutableArray array];
        for (NSDictionary *c in json[@"Lines"]) {
            if (![c isKindOfClass:[NSDictionary class]]) continue;
            SLLine *l = [SLLine new];
            l.text = SLTrim(SLStr(c[@"Text"]));
            l.words = @[];
            l.background = @[];
            [lines addObject:l];
        }
        if (!lines.count) return nil;
        ly.type = SLLyricsTypeStatic;
        ly.lines = lines;
        return ly;
    }
    return nil;
}

@end
