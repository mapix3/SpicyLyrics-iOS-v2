#import "SLLyricsProvider.h"
#import "SLLocalization.h"
#import "SLSettings.h"
#import "SLSecrets.h"
#import "SLSpotifyLyrics.h"

NSNotificationName const SLLyricsDidLoadNotification = @"SLLyricsDidLoadNotification";
NSNotificationName const SLSpotifyLyricsDidLoadNotification = @"SLSpotifyLyricsDidLoadNotification";

static NSString *const SLOwnHeader = @"X-SpicyLyricsiOS";
static NSString *const SLUserAgent = @"SpicyLyricsiOS/2.0 (https://github.com/mapix3/SpicyLyrics-iOS-v2)";
static NSString *const SLSpicyAPI = @"https://api.spicylyrics.org/v1/lyrics/";

@interface SLLyricsProvider ()
@property (nonatomic, strong) NSURLSession *session;
@property (nonatomic, strong) NSCache<NSString *, SLLyrics *> *cache;
@property (nonatomic, strong) NSMutableDictionary<NSString *, NSString *> *idForKey;
@property (nonatomic, strong) NSMutableArray<NSString *> *sniffedIds;
@property (nonatomic, strong) NSMutableDictionary<NSString *, NSMutableArray<SLLyricsCompletion> *> *pending;
@property (nonatomic, strong) NSCache<NSString *, id> *spicyById;
@property (nonatomic, strong) NSCache<NSString *, id> *spotifyById;
@property (nonatomic, strong) NSMutableDictionary<NSString *, NSMutableArray<SLLyricsCompletion> *> *spicyPending;
@property (atomic, copy) NSString *spotifyToken;
@property (atomic, copy) NSString *clientToken;
@property (atomic, copy) NSString *spotifyUserAgent;
@property (atomic) NSTimeInterval tokenStamp;
@end

static NSString *SLEnc(NSString *s) {
    NSMutableCharacterSet *allowed = [[NSCharacterSet URLQueryAllowedCharacterSet] mutableCopy];
    [allowed removeCharactersInString:@"&+=?/:"];
    return [s ?: @"" stringByAddingPercentEncodingWithAllowedCharacters:allowed] ?: @"";
}

static NSString *SLNorm(NSString *s) {
    NSString *t = [[s ?: @"" lowercaseString] stringByFoldingWithOptions:NSDiacriticInsensitiveSearch locale:nil];
    NSRange dash = [t rangeOfString:@" - "];
    if (dash.location != NSNotFound) t = [t substringToIndex:dash.location];
    NSRange par = [t rangeOfString:@" ("];
    if (par.location != NSNotFound) t = [t substringToIndex:par.location];
    NSCharacterSet *keep = [NSCharacterSet alphanumericCharacterSet];
    NSMutableString *o = [NSMutableString string];
    for (NSUInteger i = 0; i < t.length; i++) {
        unichar c = [t characterAtIndex:i];
        if ([keep characterIsMember:c]) [o appendFormat:@"%C", c];
    }
    return o;
}

static NSString *SLCleanTitle(NSString *t) {
    NSString *s = t ?: @"";
    NSRange dash = [s rangeOfString:@" - "];
    if (dash.location != NSNotFound) s = [s substringToIndex:dash.location];
    NSRegularExpression *re = [NSRegularExpression regularExpressionWithPattern:@"\\s*[\\(\\[](feat\\.?|ft\\.?|with|prod\\.?)[^\\)\\]]*[\\)\\]]" options:NSRegularExpressionCaseInsensitive error:nil];
    s = [re stringByReplacingMatchesInString:s options:0 range:NSMakeRange(0, s.length) withTemplate:@""];
    return [s stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
}

static NSString *SLFirstArtist(NSString *a) {
    NSString *s = a ?: @"";
    for (NSString *sep in @[@", ", @" & ", @" feat. ", @" x "]) {
        NSRange r = [s rangeOfString:sep];
        if (r.location != NSNotFound) s = [s substringToIndex:r.location];
    }
    return s;
}

@implementation SLLyricsProvider

+ (instancetype)shared {
    static SLLyricsProvider *s;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ s = [SLLyricsProvider new]; });
    return s;
}

- (instancetype)init {
    if ((self = [super init])) {
        NSURLSessionConfiguration *cfg = [NSURLSessionConfiguration ephemeralSessionConfiguration];
        cfg.timeoutIntervalForRequest = 15;
        cfg.HTTPAdditionalHeaders = @{ SLOwnHeader: @"1" };
        _session = [NSURLSession sessionWithConfiguration:cfg];
        _cache = [NSCache new];
        _cache.countLimit = 80;
        _idForKey = [NSMutableDictionary dictionary];
        _sniffedIds = [NSMutableArray array];
        _pending = [NSMutableDictionary dictionary];
        _spicyById = [NSCache new];
        _spicyById.countLimit = 200;
        _spotifyById = [NSCache new];
        _spotifyById.countLimit = 200;
        _spicyPending = [NSMutableDictionary dictionary];
    }
    return self;
}

- (void)clearCache {
    [self.cache removeAllObjects];
    [self.spicyById removeAllObjects];
    [self.spotifyById removeAllObjects];
}

- (SLLyrics *)cachedLyricsForKey:(NSString *)key {
    return key ? [self.cache objectForKey:key] : nil;
}

- (void)observeRequest:(NSURLRequest *)request {
    NSDictionary *h = request.allHTTPHeaderFields;
    if (h[SLOwnHeader]) return;
    NSURL *url = request.URL;
    if (![url.host hasSuffix:@"spotify.com"] && ![url.host hasSuffix:@"spotify.net"]) return;

    NSString *auth = h[@"Authorization"] ?: h[@"authorization"];
    if ([auth hasPrefix:@"Bearer "] && auth.length > 47) {
        self.spotifyToken = [auth substringFromIndex:7];
        self.tokenStamp = [NSDate date].timeIntervalSince1970;
    }
    NSString *ct = h[@"client-token"] ?: h[@"Client-Token"];
    if (ct.length) self.clientToken = ct;
    NSString *ua = h[@"User-Agent"] ?: h[@"user-agent"];
    if ([url.host hasPrefix:@"spclient"] && ua.length) self.spotifyUserAgent = ua;

    static NSRegularExpression *re;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        re = [NSRegularExpression regularExpressionWithPattern:@"/(?:color-)?lyrics/v\\d+/track/([A-Za-z0-9]{22})" options:0 error:nil];
    });
    NSString *path = url.path ?: @"";
    NSTextCheckingResult *m = [re firstMatchInString:path options:0 range:NSMakeRange(0, path.length)];
    if (m) {
        NSString *tid = [path substringWithRange:[m rangeAtIndex:1]];
        @synchronized (self) {
            [self.sniffedIds removeObject:tid];
            [self.sniffedIds insertObject:tid atIndex:0];
            while (self.sniffedIds.count > 6) [self.sniffedIds removeLastObject];
        }
    }
}

- (BOOL)hasSpotifyToken {
    return self.spotifyToken.length && ([NSDate date].timeIntervalSince1970 - self.tokenStamp) < 55 * 60;
}

- (NSDictionary *)spotifyAuth {
    return @{ @"Authorization": [@"Bearer " stringByAppendingString:self.spotifyToken ?: @""], @"App-Platform": @"iOS" };
}

- (void)request:(NSString *)url method:(NSString *)method body:(NSData *)body headers:(NSDictionary *)headers
     completion:(void (^)(id json, NSInteger status))completion {
    NSURL *u = [NSURL URLWithString:url];
    if (!u) { completion(nil, -1); return; }
    NSMutableURLRequest *req = [NSMutableURLRequest requestWithURL:u];
    req.HTTPMethod = method;
    req.HTTPBody = body;
    [req setValue:SLUserAgent forHTTPHeaderField:@"User-Agent"];
    [req setValue:@"application/json" forHTTPHeaderField:@"Accept"];
    [req setValue:@"1" forHTTPHeaderField:SLOwnHeader];
    if (body) [req setValue:@"application/json" forHTTPHeaderField:@"Content-Type"];
    [headers enumerateKeysAndObjectsUsingBlock:^(NSString *k, NSString *v, BOOL *stop) { [req setValue:v forHTTPHeaderField:k]; }];
    [[self.session dataTaskWithRequest:req completionHandler:^(NSData *data, NSURLResponse *resp, NSError *err) {
        NSInteger status = [(NSHTTPURLResponse *)resp statusCode];
        id json = data.length ? [NSJSONSerialization JSONObjectWithData:data options:0 error:nil] : nil;
        completion(err ? nil : json, err ? -1 : status);
    }] resume];
}

- (void)getJSON:(NSString *)url headers:(NSDictionary *)headers completion:(void (^)(id json, NSInteger status))completion {
    [self request:url method:@"GET" body:nil headers:headers completion:completion];
}

static BOOL SLTrackMatches(NSDictionary *t, NSString *title, NSString *artist, double duration) {
    if (![t isKindOfClass:[NSDictionary class]]) return NO;
    double d = [t[@"duration_ms"] doubleValue] / 1000.0;
    if (duration > 0 && fabs(d - duration) > 3.0) return NO;
    NSString *a = SLNorm(title), *b = SLNorm(t[@"name"]);
    if (a.length && b.length && ![a hasPrefix:b] && ![b hasPrefix:a]) return NO;
    NSString *want = SLNorm(SLFirstArtist(artist));
    if (!want.length) return YES;
    for (NSDictionary *ar in t[@"artists"]) {
        NSString *n = SLNorm(ar[@"name"]);
        if ([n isEqualToString:want] || [n hasPrefix:want] || [want hasPrefix:n]) return YES;
    }
    return NO;
}

- (void)resolveTrackIdForTitle:(NSString *)title artist:(NSString *)artist duration:(double)duration
                           uri:(NSString *)uri key:(NSString *)key completion:(void (^)(NSString *trackId))completion {
    if ([uri hasPrefix:@"spotify:track:"] && uri.length >= 36) { completion([uri substringFromIndex:14]); return; }
    NSString *known;
    @synchronized (self) { known = self.idForKey[key]; }
    if (known) { completion(known); return; }
    if (![self hasSpotifyToken]) { completion(nil); return; }

    void (^remember)(NSString *) = ^(NSString *tid) {
        if (tid) { @synchronized (self) { self.idForKey[key] = tid; } }
        completion(tid);
    };

    NSArray *candidates;
    @synchronized (self) { candidates = [self.sniffedIds copy]; }
    void (^search)(void) = ^{
        NSString *q = [NSString stringWithFormat:@"track:%@ artist:%@", SLCleanTitle(title), SLFirstArtist(artist)];
        NSString *url = [NSString stringWithFormat:@"https://api.spotify.com/v1/search?type=track&limit=10&q=%@", SLEnc(q)];
        [self getJSON:url headers:[self spotifyAuth] completion:^(NSDictionary *json, NSInteger status) {
            NSArray *items = [json isKindOfClass:[NSDictionary class]] ? json[@"tracks"][@"items"] : nil;
            NSString *best = nil; double bestDiff = 1e9;
            for (NSDictionary *it in items) {
                if (!SLTrackMatches(it, title, artist, duration)) continue;
                double d = fabs([it[@"duration_ms"] doubleValue] / 1000.0 - duration);
                if (d < bestDiff) { bestDiff = d; best = it[@"id"]; }
            }
            remember(best);
        }];
    };
    if (!candidates.count) { search(); return; }

    NSString *ids = [candidates componentsJoinedByString:@","];
    [self getJSON:[@"https://api.spotify.com/v1/tracks?ids=" stringByAppendingString:ids] headers:[self spotifyAuth]
       completion:^(NSDictionary *json, NSInteger status) {
        NSArray *tracks = [json isKindOfClass:[NSDictionary class]] ? json[@"tracks"] : nil;
        for (NSDictionary *t in tracks) {
            if (SLTrackMatches(t, title, artist, duration)) { remember(t[@"id"]); return; }
        }
        search();
    }];
}

- (void)lyricsForTitle:(NSString *)title artist:(NSString *)artist album:(NSString *)album duration:(double)duration
              trackURI:(NSString *)uri trackKey:(NSString *)key completion:(SLLyricsCompletion)completion {
    SLLyrics *cached = [self.cache objectForKey:key];
    if (cached) { completion(cached, nil); return; }

    @synchronized (self) {
        NSMutableArray *waiting = self.pending[key];
        if (waiting) { [waiting addObject:[completion copy]]; return; }
        self.pending[key] = [NSMutableArray arrayWithObject:[completion copy]];
    }

    void (^finish)(SLLyrics *, NSString *) = ^(SLLyrics *ly, NSString *err) {
        if (ly) [self.cache setObject:ly forKey:key];
        NSArray *cbs;
        @synchronized (self) { cbs = self.pending[key]; [self.pending removeObjectForKey:key]; }
        dispatch_async(dispatch_get_main_queue(), ^{
            for (SLLyricsCompletion cb in cbs) cb(ly, err);
            if (ly) [[NSNotificationCenter defaultCenter] postNotificationName:SLLyricsDidLoadNotification object:key];
        });
    };

    [self resolveTrackIdForTitle:title artist:artist duration:duration uri:uri key:key completion:^(NSString *tid) {
        [self spicyLyricsForTrackId:tid completion:^(SLLyrics *ly, NSString *err) {
            if (ly) { finish(ly, nil); return; }
            [self spotifyLyricsForTrackId:tid completion:^(SLLyrics *sp) {
                finish(sp, sp ? nil : (err ?: SLLoc(@"err_spicy_none")));
            }];
        }];
    }];
}

- (void)spicyLyricsForTrackId:(NSString *)tid completion:(SLLyricsCompletion)completion {
    void (^done)(SLLyrics *, NSString *) = ^(SLLyrics *ly, NSString *err) {
        dispatch_async(dispatch_get_main_queue(), ^{ completion(ly, err); });
    };
    if (!tid.length) { done(nil, SLLoc(@"err_no_track")); return; }
    id hit = [self.spicyById objectForKey:tid];
    if (hit) { done(hit == [NSNull null] ? nil : hit, hit == [NSNull null] ? SLLoc(@"err_spicy_none") : nil); return; }

    @synchronized (self) {
        NSMutableArray *waiting = self.spicyPending[tid];
        if (waiting) { [waiting addObject:[completion copy]]; return; }
        self.spicyPending[tid] = [NSMutableArray arrayWithObject:[completion copy]];
    }
    [self spicyTrackId:tid duration:0 completion:^(SLLyrics *ly, NSString *err) {
        NSArray *cbs;
        @synchronized (self) { cbs = self.spicyPending[tid]; [self.spicyPending removeObjectForKey:tid]; }
        dispatch_async(dispatch_get_main_queue(), ^{
            for (SLLyricsCompletion cb in cbs) cb(ly, err);
        });
    }];
}

- (void)spicyTrackId:(NSString *)tid duration:(double)duration completion:(void (^)(SLLyrics *, NSString *))completion {
    NSString *proxy = SL_SPICY_PROXY;
    BOOL viaProxy = proxy.length > 0;
    if (!viaProxy && ![SL_SPICY_API_KEY length]) { completion(nil, SLLoc(@"err_no_key")); return; }
    if (!tid.length) { completion(nil, SLLoc(@"err_no_track")); return; }

    NSString *base = viaProxy ? [[proxy stringByTrimmingCharactersInSet:[NSCharacterSet characterSetWithCharactersInString:@"/"]]
                                 stringByAppendingString:@"/v1/lyrics/"] : SLSpicyAPI;
    NSDictionary *headers = viaProxy ? @{} : @{ @"Authorization": [@"Bearer " stringByAppendingString:SL_SPICY_API_KEY] };
    [self request:[base stringByAppendingString:tid] method:@"GET" body:nil headers:headers
       completion:^(NSDictionary *json, NSInteger status) {
        NSDictionary *body = [json isKindOfClass:[NSDictionary class]] ? json[@"Body"] : nil;
        if (status == 200 && [body isKindOfClass:[NSDictionary class]]) {
            SLLyrics *ly = [SLLyrics lyricsFromSpicyJSON:body duration:duration];
            if (ly) [self.spicyById setObject:ly forKey:tid];
            completion(ly, ly ? nil : SLLoc(@"err_format"));
            return;
        }
        if (status == 404) { [self.spicyById setObject:[NSNull null] forKey:tid]; completion(nil, SLLoc(@"err_spicy_none")); return; }
        NSString *msg = [body isKindOfClass:[NSDictionary class]] && [body[@"message"] isKindOfClass:[NSString class]] ? body[@"message"] : nil;
        NSString *code = [body isKindOfClass:[NSDictionary class]] && [body[@"error"] isKindOfClass:[NSString class]] ? body[@"error"] : nil;
        if (status <= 0) { completion(nil, SLLoc(@"err_spicy_down")); return; }
        completion(nil, [NSString stringWithFormat:@"Spicy Lyrics: %ld %@%@", (long)status, code ?: @"", msg ? [@" — " stringByAppendingString:msg] : @""]);
    }];
}

- (void)storeSpotifyResponse:(NSData *)data trackId:(NSString *)tid {
    if (!tid.length) return;
    SLLyrics *ly = SLLyricsFromSpotifyResponse(data);
    if (!ly) return;
    BOOL isNew = ![[self.spotifyById objectForKey:tid] isKindOfClass:[SLLyrics class]];
    [self.spotifyById setObject:ly forKey:tid];
    if (isNew) dispatch_async(dispatch_get_main_queue(), ^{
        [[NSNotificationCenter defaultCenter] postNotificationName:SLSpotifyLyricsDidLoadNotification object:tid];
    });
}

- (void)spotifyLyricsForTrackId:(NSString *)tid completion:(void (^)(SLLyrics *))completion {
    void (^done)(SLLyrics *) = ^(SLLyrics *ly) { dispatch_async(dispatch_get_main_queue(), ^{ completion(ly); }); };
    if (!tid.length) { done(nil); return; }
    id hit = [self.spotifyById objectForKey:tid];
    if (hit) { done(hit == [NSNull null] ? nil : hit); return; }
    if (![self hasSpotifyToken]) { done(nil); return; }

    NSString *url = [NSString stringWithFormat:@"https://spclient.wg.spotify.com/color-lyrics/v2/track/%@?format=json&vocalRemoval=false&market=from_token", tid];
    NSMutableURLRequest *req = [NSMutableURLRequest requestWithURL:[NSURL URLWithString:url]];
    [[self spotifyAuth] enumerateKeysAndObjectsUsingBlock:^(NSString *k, NSString *v, BOOL *stop) { [req setValue:v forHTTPHeaderField:k]; }];
    [req setValue:@"application/json" forHTTPHeaderField:@"Accept"];
    [req setValue:@"1" forHTTPHeaderField:SLOwnHeader];
    if (self.clientToken.length) [req setValue:self.clientToken forHTTPHeaderField:@"client-token"];
    if (self.spotifyUserAgent.length) [req setValue:self.spotifyUserAgent forHTTPHeaderField:@"User-Agent"];
    [[self.session dataTaskWithRequest:req completionHandler:^(NSData *data, NSURLResponse *resp, NSError *err) {
        NSInteger status = [(NSHTTPURLResponse *)resp statusCode];
        SLLyrics *ly = status == 200 ? SLLyricsFromSpotifyResponse(data) : nil;
        if (ly) [self.spotifyById setObject:ly forKey:tid];
        else if (status == 404) [self.spotifyById setObject:[NSNull null] forKey:tid];
        id late = [self.spotifyById objectForKey:tid];
        done(ly ?: ([late isKindOfClass:[SLLyrics class]] ? late : nil));
    }] resume];
}

@end
