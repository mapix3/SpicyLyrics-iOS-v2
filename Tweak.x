#import <UIKit/UIKit.h>
#import <MediaPlayer/MediaPlayer.h>
#import <objc/runtime.h>
#import "Sources/SLNowPlaying.h"
#import "Sources/SLRemote.h"
#import "Sources/SLPlayerLyrics.h"
#import "Sources/SLLyricsNetwork.h"
#import "Sources/SLDebug.h"
#import "Sources/SLProMotion.h"
#import "Sources/SLWidgetBridge.h"
#import "Sources/SLLyricsProvider.h"

static BOOL SLAddingHandler;

%hook MPNowPlayingInfoCenter

- (void)setNowPlayingInfo:(NSDictionary *)info {
    CFTimeInterval stamp = CACurrentMediaTime();
    %orig;
    [[SLNowPlaying shared] updateWithInfo:info stamp:stamp];
}

- (void)setPlaybackState:(MPNowPlayingPlaybackState)state {
    CFTimeInterval stamp = CACurrentMediaTime();
    %orig;
    [[SLNowPlaying shared] updatePlaybackState:state stamp:stamp];
}

%end

%hook MPRemoteCommand

- (id)addTargetWithHandler:(MPRemoteCommandHandlerStatus (^)(MPRemoteCommandEvent *))handler {
    BOOL was = SLAddingHandler;
    SLAddingHandler = YES;
    id token = %orig;
    SLAddingHandler = was;
    [SLRemote command:self addedHandler:handler token:token];
    return token;
}

- (void)addTarget:(id)target action:(SEL)action {
    %orig;
    if (!SLAddingHandler) [SLRemote command:self addedTarget:target action:action];
}

- (void)removeTarget:(id)target {
    %orig;
    [SLRemote command:self removedTarget:target];
}

- (void)removeTarget:(id)target action:(SEL)action {
    %orig;
    [SLRemote command:self removedTarget:target];
}

%end

static void SLHookTaskResume(Class cls) {
    SEL sel = @selector(resume);
    Method m = class_getInstanceMethod(cls, sel);
    if (!m) return;
    IMP orig = method_getImplementation(m);
    IMP repl = imp_implementationWithBlock(^(NSURLSessionTask *task) {
        @try {
            NSURLRequest *r = task.currentRequest ?: task.originalRequest;
            if (r) [[SLLyricsProvider shared] observeRequest:r];
            NSString *path = r.URL.path.lowercaseString;
            if ([path containsString:@"lyric"] || [path containsString:@"scrollsita"])
                SLLog(@"resume %@ %@%@ (%@)", r.HTTPMethod, r.URL.host, r.URL.path, NSStringFromClass([task class]));
        } @catch (NSException *e) {}
        ((void (*)(id, SEL))orig)(task, sel);
    });
    if (!class_addMethod(cls, sel, repl, method_getTypeEncoding(m))) method_setImplementation(m, repl);
}

static void SLInstallNetworkSniffer(void) {
    NSURLSession *s = [NSURLSession sessionWithConfiguration:[NSURLSessionConfiguration ephemeralSessionConfiguration]];
    NSURLSessionTask *t = [s dataTaskWithURL:[NSURL URLWithString:@"https://localhost/"]];
    Class cls = [t class];
    [t cancel];
    [s invalidateAndCancel];
    if (cls) SLHookTaskResume(cls);
}

static void SLPrefetch(void) {
    SLNowPlaying *np = [SLNowPlaying shared];
    if (!np.title.length || !np.trackKey) return;
    [[SLLyricsProvider shared] lyricsForTitle:np.title artist:np.artist ?: @"" album:np.album duration:np.duration
                                     trackURI:np.trackURI trackKey:np.trackKey completion:^(SLLyrics *ly, NSString *err) {}];
}

static NSString *const SLLaunchGuardKey = @"SpicyLyricsiOS.launchCrashes";

static BOOL SLSafeMode(void) {
    static BOOL safeMode;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        NSUserDefaults *d = [NSUserDefaults standardUserDefaults];
        NSInteger crashes = [d integerForKey:SLLaunchGuardKey];
        safeMode = crashes >= 3;
        [d setInteger:safeMode ? 0 : crashes + 1 forKey:SLLaunchGuardKey];
        [d synchronize];
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(20 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            [[NSUserDefaults standardUserDefaults] setInteger:0 forKey:SLLaunchGuardKey];
        });
    });
    return safeMode;
}

static void SLInstallSpotifyHooks(void) {
    if (SLSafeMode()) return;
    SLInstallPlayerHooks();
    SLInstallVirtualCard();
    SLInstallLyricsNetworkHooks();
    SLInstallDebugHooks();
    SLStartWidgetBridge();
}

%ctor {
    @autoreleasepool {
        SLEnableProMotion();
        SLInstallNetworkSniffer();
        SLLog(@"launch: Spotify %@ (%@), safeMode=%d",
              [NSBundle.mainBundle objectForInfoDictionaryKey:@"CFBundleShortVersionString"],
              [NSBundle.mainBundle objectForInfoDictionaryKey:@"CFBundleVersion"], SLSafeMode());
        dispatch_async(dispatch_get_main_queue(), ^{ SLInstallSpotifyHooks(); });
        NSNotificationCenter *nc = [NSNotificationCenter defaultCenter];
        [nc addObserverForName:UIApplicationDidFinishLaunchingNotification object:nil queue:[NSOperationQueue mainQueue]
                    usingBlock:^(NSNotification *n) {
            SLInstallSpotifyHooks();
        }];
        [nc addObserverForName:SLTrackDidChangeNotification object:nil queue:[NSOperationQueue mainQueue]
                    usingBlock:^(NSNotification *n) {
            NSString *key = [SLNowPlaying shared].trackKey;
            SLLog(@"track: %@ uri=%@", key, [SLNowPlaying shared].trackURI ?: @"-");
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.2 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                if ([key isEqualToString:[SLNowPlaying shared].trackKey]) SLPrefetch();
            });
        }];
    }
}
