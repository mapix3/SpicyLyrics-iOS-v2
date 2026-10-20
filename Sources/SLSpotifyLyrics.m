#import "SLSpotifyLyrics.h"

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
