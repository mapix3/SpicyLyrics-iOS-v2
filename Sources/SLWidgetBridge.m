#import "SLWidgetBridge.h"
#import <UIKit/UIKit.h>
#import <dlfcn.h>
#import "SLNowPlaying.h"
#import "SLLyricsProvider.h"
#import "SLLocalization.h"
#import "SLSettings.h"
#import "SLBackgroundView.h"
#import "SLDebug.h"

static NSString *const SLWidgetGroup = @"group.com.spotify.client.widget";
static NSString *const SLWidgetFolder = @"SpicyLyricsWidget";

typedef struct { const void *metadata; intptr_t state; } SLMetadataResponse;
typedef SLMetadataResponse (*SLMetadataAccessor)(intptr_t request) __attribute__((swiftcall));
typedef void *(*SLSharedGetter)(const void *metatype __attribute__((swift_context))) __attribute__((swiftcall));
typedef void (*SLReloadAll)(void *center __attribute__((swift_context))) __attribute__((swiftcall));

static void SLReloadWidgets(void) {
#if defined(__arm64__) || defined(__aarch64__)
    static void *center;
    static SLReloadAll reload;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        void *h = dlopen("/System/Library/Frameworks/WidgetKit.framework/WidgetKit", RTLD_LAZY);
        if (!h) return;
        SLMetadataAccessor accessor = (SLMetadataAccessor)dlsym(h, "$s9WidgetKit0A6CenterCMa");
        SLSharedGetter shared = (SLSharedGetter)dlsym(h, "$s9WidgetKit0A6CenterC6sharedACvgZ");
        reload = (SLReloadAll)dlsym(h, "$s9WidgetKit0A6CenterC18reloadAllTimelinesyyFTj");
        if (!accessor || !shared || !reload) { reload = NULL; return; }
        SLMetadataResponse meta = accessor(0);
        if (!meta.metadata) { reload = NULL; return; }
        center = shared(meta.metadata);
    });
    if (center && reload) reload(center);
#endif
}

static NSString *SLHex(UIColor *c) {
    CGFloat r = 0, g = 0, b = 0, a = 1;
    if (![c getRed:&r green:&g blue:&b alpha:&a]) return @"#333333";
    return [NSString stringWithFormat:@"#%02X%02X%02X", (int)lround(MIN(1, MAX(0, r)) * 255), (int)lround(MIN(1, MAX(0, g)) * 255), (int)lround(MIN(1, MAX(0, b)) * 255)];
}

static UIColor *SLDarken(UIColor *c) {
    CGFloat h = 0, s = 0, b = 0, a = 1;
    if (![c getHue:&h saturation:&s brightness:&b alpha:&a]) return [UIColor colorWithWhite:0.12 alpha:1];
    return [UIColor colorWithHue:h saturation:MIN(1, s * 1.1) brightness:MIN(0.26, MAX(0.16, b)) alpha:1];
}

@interface SLWidgetBridge : NSObject
@property (nonatomic, strong) NSURL *directory;
@property (nonatomic, strong) NSMutableDictionary<NSString *, NSString *> *failures;
@property (nonatomic, strong) NSMutableSet<NSString *> *requested;
@property (nonatomic, copy) NSString *artworkKey;
@property (nonatomic, copy) NSArray<NSString *> *palette;
@property (nonatomic, copy) NSString *baseColor;
@property (nonatomic, copy) NSString *lastSignature;
@property (nonatomic) BOOL scheduled;
@property (nonatomic) double lastPosition;
@property (nonatomic) CFTimeInterval lastStamp;
@property (nonatomic) BOOL lastPlaying;
@end

@implementation SLWidgetBridge

+ (NSURL *)resolveDirectory {
    NSMutableArray<NSString *> *groups = [NSMutableArray array];
    id alt = [NSBundle.mainBundle objectForInfoDictionaryKey:@"ALTAppGroups"];
    if ([alt isKindOfClass:[NSArray class]]) [groups addObjectsFromArray:alt];
    [groups addObject:SLWidgetGroup];
    NSFileManager *fm = NSFileManager.defaultManager;
    for (NSString *g in groups) {
        if (![g isKindOfClass:[NSString class]]) continue;
        NSURL *u = [fm containerURLForSecurityApplicationGroupIdentifier:g];
        if (!u) continue;
        NSURL *dir = [u URLByAppendingPathComponent:SLWidgetFolder isDirectory:YES];
        [fm createDirectoryAtURL:dir withIntermediateDirectories:YES attributes:nil error:nil];
        SLLog(@"widget: app group %@", g);
        return dir;
    }
    SLLog(@"widget: no app group container");
    return nil;
}

- (instancetype)init {
    if ((self = [super init])) {
        _directory = [SLWidgetBridge resolveDirectory];
        _failures = [NSMutableDictionary dictionary];
        _requested = [NSMutableSet set];
        NSNotificationCenter *nc = [NSNotificationCenter defaultCenter];
        for (NSString *name in @[SLTrackDidChangeNotification, SLPlaybackDidChangeNotification, SLArtworkDidChangeNotification,
                                 SLLyricsDidLoadNotification, SLSpotifyLyricsDidLoadNotification, SLSettingsDidChangeNotification,
                                 UIApplicationDidEnterBackgroundNotification]) {
            [nc addObserver:self selector:@selector(schedule) name:name object:nil];
        }
    }
    return self;
}

- (void)schedule {
    if (!self.directory || self.scheduled) return;
    self.scheduled = YES;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.35 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        self.scheduled = NO;
        [self update];
    });
}

- (NSString *)footerFor:(SLLyrics *)ly {
    if (ly.fromSpotify) {
        NSString *note = SLLoc(@"spotify_fallback");
        if (ly.source.length && ![ly.source isEqualToString:@"Spotify"]) note = [note stringByAppendingFormat:@" · %@", ly.source];
        return note;
    }
    NSMutableString *s = [SLLocFormat(@"lyrics_from", ly.source ?: @"Spicy Lyrics") mutableCopy];
    if (ly.uploaderName.length) [s appendFormat:@" · %@ %@", SLLoc(@"uploaded_by"), ly.uploaderName];
    if (ly.makerName.length) [s appendFormat:@" · %@ %@", SLLoc(@"synced_by"), ly.makerName];
    return s;
}

- (void)refreshArtwork:(SLNowPlaying *)np {
    NSString *key = np.trackKey ?: @"";
    UIImage *art = np.artwork;
    if (!art || [key isEqualToString:self.artworkKey ?: @""]) return;
    self.artworkKey = key;
    NSURL *file = [self.directory URLByAppendingPathComponent:@"artwork.jpg"];
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^{
        CGSize size = CGSizeMake(240, 240);
        UIGraphicsImageRendererFormat *fmt = [UIGraphicsImageRendererFormat defaultFormat];
        fmt.scale = 1;
        UIImage *small = [[[UIGraphicsImageRenderer alloc] initWithSize:size format:fmt] imageWithActions:^(UIGraphicsImageRendererContext *ctx) {
            [art drawInRect:CGRectMake(0, 0, size.width, size.height)];
        }];
        [UIImageJPEGRepresentation(small, 0.85) writeToURL:file atomically:YES];
        NSArray<UIColor *> *colors = SLArtworkPalette(art);
        NSMutableArray *hex = [NSMutableArray array];
        for (UIColor *c in colors) [hex addObject:SLHex(c)];
        NSString *base = colors.count ? SLHex(SLDarken(colors.firstObject)) : @"#1F1F1F";
        dispatch_async(dispatch_get_main_queue(), ^{
            if (![key isEqualToString:self.artworkKey]) return;
            self.palette = hex;
            self.baseColor = base;
            self.lastSignature = nil;
            [self schedule];
        });
    });
}

- (void)update {
    SLNowPlaying *np = [SLNowPlaying shared];
    NSMutableDictionary *state = [NSMutableDictionary dictionary];
    state[@"v"] = @1;
    state[@"titleLabel"] = SLLoc(@"lyrics");
    state[@"capturedAt"] = @([NSDate date].timeIntervalSince1970);

    NSString *key = np.trackKey;
    SLLyrics *ly = nil;
    NSString *status = @"idle";
    if (np.title.length && key) {
        [self refreshArtwork:np];
        ly = [[SLLyricsProvider shared] cachedLyricsForKey:key];
        if (ly) status = @"ok";
        else if (self.failures[key]) status = @"none";
        else {
            status = @"loading";
            if (![self.requested containsObject:key]) {
                [self.requested addObject:key];
                [[SLLyricsProvider shared] lyricsForTitle:np.title artist:np.artist ?: @"" album:np.album duration:np.duration
                                                 trackURI:np.trackURI trackKey:key completion:^(SLLyrics *res, NSString *err) {
                    if (!res) self.failures[key] = err ?: @"";
                    [self.requested removeObject:key];
                    [self schedule];
                }];
            }
        }
        state[@"trackKey"] = key;
        state[@"title"] = np.title;
        state[@"artist"] = np.artist ?: @"";
        state[@"duration"] = @(np.duration);
        state[@"position"] = @(np.currentTime);
        state[@"playing"] = @(np.isPlaying);
        state[@"hasArtwork"] = @(self.artworkKey != nil && [self.artworkKey isEqualToString:key]);
    }
    state[@"status"] = status;
    if ([status isEqualToString:@"idle"]) state[@"message"] = SLLoc(@"play_track");
    else if ([status isEqualToString:@"none"]) state[@"message"] = SLLoc(@"no_lyrics");
    if (self.palette.count) state[@"palette"] = self.palette;
    if (self.baseColor) state[@"base"] = self.baseColor;

    if (ly) {
        NSMutableArray *lines = [NSMutableArray array];
        for (SLLine *l in ly.lines) {
            [lines addObject:@{ @"s": @(l.start), @"e": @(l.end), @"t": l.text ?: @"", @"i": @(l.isInterlude) }];
        }
        state[@"lines"] = lines;
        state[@"synced"] = @(ly.type != SLLyricsTypeStatic);
        state[@"footer"] = [self footerFor:ly];
    }

    NSData *json = [NSJSONSerialization dataWithJSONObject:state options:0 error:nil];
    if (!json) return;
    [json writeToURL:[self.directory URLByAppendingPathComponent:@"state.json"] atomically:YES];

    double position = np.currentTime;
    CFTimeInterval nowStamp = CACurrentMediaTime();
    double predicted = self.lastPosition + (self.lastPlaying ? nowStamp - self.lastStamp : 0);
    BOOL jumped = self.lastStamp > 0 && fabs(position - predicted) > 2.0;
    self.lastPosition = position;
    self.lastStamp = nowStamp;
    self.lastPlaying = np.isPlaying;
    NSString *signature = [NSString stringWithFormat:@"%@|%@|%d|%lu|%@", key ?: @"", status, np.isPlaying,
                           (unsigned long)[state[@"lines"] count], self.palette.firstObject ?: @""];
    if (![signature isEqualToString:self.lastSignature ?: @""] || jumped) {
        self.lastSignature = signature;
        SLReloadWidgets();
    }
}

@end

void SLStartWidgetBridge(void) {
    static SLWidgetBridge *bridge;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        bridge = [SLWidgetBridge new];
        [bridge schedule];
    });
}
