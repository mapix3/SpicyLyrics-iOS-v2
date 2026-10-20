#import "SLSpotifyLyrics.h"

// Схема color-lyrics/v2 (только нужные поля):
//   Lyrics      { 1: LyricsData data; 2: LyricsColors colors }
//   LyricsData  { 1: bool timeSynchronized; 2: repeated LyricsLine lines; 5: string providedBy }
//   LyricsLine  { 1: int32 offsetMs; 2: string content }
//   LyricsColors{ 1: uint32 background; 2: uint32 line; 3: uint32 activeLine }

#pragma mark - Protobuf reader

typedef struct {
    const uint8_t *p, *end;
} SLPB;

static BOOL SLReadVarint(SLPB *r, uint64_t *out) {
    uint64_t v = 0;
    for (int shift = 0; shift < 64 && r->p < r->end; shift += 7) {
        uint8_t b = *r->p++;
        v |= (uint64_t)(b & 0x7F) << shift;
        if (!(b & 0x80)) { *out = v; return YES; }
    }
    return NO;
}

/// Следующее поле. Для LEN — *sub указывает на содержимое.
static BOOL SLNextField(SLPB *r, uint32_t *field, uint32_t *wire, uint64_t *value, SLPB *sub) {
    if (r->p >= r->end) return NO;
    uint64_t key;
    if (!SLReadVarint(r, &key)) return NO;
    *field = (uint32_t)(key >> 3);
    *wire = (uint32_t)(key & 7);
    switch (*wire) {
        case 0: return SLReadVarint(r, value);
        case 1: if (r->end - r->p < 8) return NO; r->p += 8; return YES;
        case 5: if (r->end - r->p < 4) return NO; r->p += 4; return YES;
        case 2: {
            uint64_t len;
            if (!SLReadVarint(r, &len) || len > (uint64_t)(r->end - r->p)) return NO;
            sub->p = r->p;
            sub->end = r->p + len;
            r->p += len;
            return YES;
        }
        default: return NO;
    }
}

static NSString *SLPBString(SLPB s) {
    return [[NSString alloc] initWithBytes:s.p length:(NSUInteger)(s.end - s.p) encoding:NSUTF8StringEncoding] ?: @"";
}

#pragma mark - Protobuf writer

static void SLPutVarint(NSMutableData *d, uint64_t v) {
    uint8_t buf[10];
    int n = 0;
    do {
        uint8_t b = v & 0x7F;
        v >>= 7;
        if (v) b |= 0x80;
        buf[n++] = b;
    } while (v);
    [d appendBytes:buf length:n];
}

static void SLPutVarintField(NSMutableData *d, uint32_t field, uint64_t v) {
    SLPutVarint(d, (field << 3) | 0);
    SLPutVarint(d, v);
}

static void SLPutBytesField(NSMutableData *d, uint32_t field, NSData *bytes) {
    SLPutVarint(d, (field << 3) | 2);
    SLPutVarint(d, bytes.length);
    [d appendData:bytes];
}

static void SLPutStringField(NSMutableData *d, uint32_t field, NSString *s) {
    SLPutBytesField(d, field, [s ?: @"" dataUsingEncoding:NSUTF8StringEncoding]);
}

#pragma mark - Spotify → SLLyrics

static BOOL SLIsFiller(NSString *t) {
    NSString *s = [t stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    NSCharacterSet *notes = [NSCharacterSet characterSetWithCharactersInString:@"♪♫♬♩🎵🎶 .…-–—*•"];
    return [[s stringByTrimmingCharactersInSet:notes] length] == 0;
}

static SLLyrics *SLBuild(NSArray<NSNumber *> *starts, NSArray<NSString *> *texts, BOOL synced, NSString *provider) {
    NSMutableArray<SLLine *> *lines = [NSMutableArray array];
    for (NSUInteger i = 0; i < texts.count; i++) {
        NSString *t = [texts[i] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
        if (synced && SLIsFiller(t)) continue;
        SLLine *l = [SLLine new];
        l.text = t;
        l.words = @[];
        l.background = @[];
        l.start = synced ? starts[i].doubleValue : 0;
        [lines addObject:l];
    }
    if (!lines.count) return nil;
    if (synced) {
        [lines sortUsingComparator:^NSComparisonResult(SLLine *a, SLLine *b) { return [@(a.start) compare:@(b.start)]; }];
        for (NSUInteger i = 0; i < lines.count; i++) {
            double next = i + 1 < lines.count ? lines[i + 1].start : lines[i].start + 5;
            lines[i].end = MAX(next, lines[i].start + 0.1);
        }
    }
    SLLyrics *ly = [SLLyrics new];
    ly.type = synced ? SLLyricsTypeLine : SLLyricsTypeStatic;
    ly.lines = lines;
    ly.source = provider.length ? provider : @"Spotify";
    ly.fromSpotify = YES;
    return ly;
}

static SLLyrics *SLFromProtobuf(NSData *data) {
    SLPB top = { data.bytes, (const uint8_t *)data.bytes + data.length };
    uint32_t f, w; uint64_t v; SLPB sub;
    while (SLNextField(&top, &f, &w, &v, &sub)) {
        if (f != 1 || w != 2) continue;
        BOOL synced = NO;
        NSString *provider = nil;
        NSMutableArray *starts = [NSMutableArray array], *texts = [NSMutableArray array];
        SLPB d = sub;
        while (SLNextField(&d, &f, &w, &v, &sub)) {
            if (f == 1 && w == 0) synced = v != 0;
            else if (f == 5 && w == 2) provider = SLPBString(sub);
            else if (f == 2 && w == 2) {
                SLPB l = sub;
                double start = 0;
                NSString *text = @"";
                SLPB s;
                while (SLNextField(&l, &f, &w, &v, &s)) {
                    if (f == 1 && w == 0) start = (double)(int32_t)v / 1000.0;
                    else if (f == 2 && w == 2) text = SLPBString(s);
                }
                [starts addObject:@(start)];
                [texts addObject:text];
            }
        }
        return SLBuild(starts, texts, synced, provider);
    }
    return nil;
}

static SLLyrics *SLFromJSON(NSData *data) {
    NSDictionary *json = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
    NSDictionary *ly = [json isKindOfClass:[NSDictionary class]] ? json[@"lyrics"] : nil;
    if (![ly isKindOfClass:[NSDictionary class]]) return nil;
    BOOL synced = ![ly[@"syncType"] isEqual:@"UNSYNCED"];
    NSString *provider = [ly[@"providerDisplayName"] isKindOfClass:[NSString class]] ? ly[@"providerDisplayName"] : nil;
    NSMutableArray *starts = [NSMutableArray array], *texts = [NSMutableArray array];
    for (NSDictionary *l in ly[@"lines"]) {
        if (![l isKindOfClass:[NSDictionary class]]) continue;
        [starts addObject:@([l[@"startTimeMs"] doubleValue] / 1000.0)];
        [texts addObject:[l[@"words"] isKindOfClass:[NSString class]] ? l[@"words"] : @""];
    }
    return SLBuild(starts, texts, synced, provider);
}

SLLyrics *SLLyricsFromSpotifyResponse(NSData *data) {
    if (!data.length) return nil;
    const uint8_t first = ((const uint8_t *)data.bytes)[0];
    @try {
        return first == '{' ? SLFromJSON(data) : SLFromProtobuf(data);
    } @catch (NSException *e) {
        return nil;
    }
}

#pragma mark - SLLyrics → Spotify

NSData *SLSpotifyResponseFromLyrics(SLLyrics *lyrics) {
    BOOL synced = lyrics && lyrics.type != SLLyricsTypeStatic;
    NSMutableData *data = [NSMutableData data];
    SLPutVarintField(data, 1, synced ? 1 : 0);
    NSUInteger count = 0;
    for (SLLine *line in lyrics.lines) {
        if (line.isInterlude || !line.text.length) continue;
        NSMutableData *l = [NSMutableData data];
        if (synced) SLPutVarintField(l, 1, (uint64_t)MAX(0, (int64_t)llround(line.start * 1000)));
        SLPutStringField(l, 2, line.text);
        SLPutBytesField(data, 2, l);
        count++;
    }
    if (!count) {
        NSMutableData *l = [NSMutableData data];
        SLPutStringField(l, 2, @"♪");
        SLPutBytesField(data, 2, l);
    }
    SLPutStringField(data, 5, @"Spicy Lyrics");

    NSMutableData *colors = [NSMutableData data];
    SLPutVarintField(colors, 1, 0xFF3A3A3Au);
    SLPutVarintField(colors, 2, 0xFF000000u);
    SLPutVarintField(colors, 3, 0xFFFFFFFFu);

    NSMutableData *out = [NSMutableData data];
    SLPutBytesField(out, 1, data);
    SLPutBytesField(out, 2, colors);
    return out;
}
