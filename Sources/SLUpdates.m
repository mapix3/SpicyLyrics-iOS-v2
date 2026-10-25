#import "SLUpdates.h"
#import "SLLocalization.h"
#import <objc/runtime.h>

#ifndef SL_VERSION
#define SL_VERSION "0"
#endif

extern UIWindow *SLKeyWindow(void);

static NSString *const SLManifestURL = @"https://raw.githubusercontent.com/mapix3/SpicyLyrics-iOS-v2/main/update.json";
static NSString *const SLSkippedKey = @"SpicyLyricsiOS.skippedVersion";
static NSString *const SLLastCheckKey = @"SpicyLyricsiOS.lastUpdateCheck";

@implementation SLUpdateInfo
@end

static NSComparisonResult SLCompareVersions(NSString *a, NSString *b) {
    NSArray *pa = [a componentsSeparatedByString:@"."], *pb = [b componentsSeparatedByString:@"."];
    for (NSUInteger i = 0; i < MAX(pa.count, pb.count); i++) {
        NSInteger x = i < pa.count ? [pa[i] integerValue] : 0;
        NSInteger y = i < pb.count ? [pb[i] integerValue] : 0;
        if (x != y) return x < y ? NSOrderedAscending : NSOrderedDescending;
    }
    return NSOrderedSame;
}

static NSString *SLHTTPS(id v) {
    return [v isKindOfClass:[NSString class]] && [v hasPrefix:@"https://"] ? v : nil;
}

static NSString *SLNotes(id v) {
    if ([v isKindOfClass:[NSString class]]) return [v length] ? v : nil;
    if (![v isKindOfClass:[NSDictionary class]]) return nil;
    id n = v[SLLanguage()] ?: v[@"en"];
    return [n isKindOfClass:[NSString class]] && [n length] ? n : nil;
}

static UIViewController *SLTopController(UIViewController *from) {
    UIViewController *top = from ?: SLKeyWindow().rootViewController;
    while (top.presentedViewController && !top.presentedViewController.isBeingDismissed) top = top.presentedViewController;
    return top;
}

static BOOL SLInLiveContainer(void) {
    NSString *path = NSBundle.mainBundle.bundlePath;
    return NSProcessInfo.processInfo.environment[@"LC_HOME_PATH"] != nil
        || [path containsString:@"/Documents/Applications/"] || [path containsString:@"/LiveContainer/"];
}

static BOOL SLInLiveProcess(void) {
    Class d = [NSUserDefaults class];
    SEL live = NSSelectorFromString(@"isLiveProcess");
    Method m = class_getClassMethod(d, live);
    if (m) return ((BOOL (*)(id, SEL))method_getImplementation(m))(d, live);
    SEL lcMain = NSSelectorFromString(@"lcMainBundle");
    m = class_getClassMethod(d, lcMain);
    if (m) {
        NSBundle *b = ((NSBundle *(*)(id, SEL))method_getImplementation(m))(d, lcMain);
        return [b.bundlePath hasSuffix:@"LiveProcess.appex"];
    }
    return NO;
}

static BOOL SLInstalledByTrollStore(void) {
    NSString *marker = [[NSBundle.mainBundle.bundlePath stringByDeletingLastPathComponent] stringByAppendingPathComponent:@"_TrollStore"];
    return [[NSFileManager defaultManager] fileExistsAtPath:marker];
}

static void SLOpenChain(NSArray<NSURL *> *urls, NSUInteger i, NSURL *fallback) {
    if (i >= urls.count) {
        if (fallback) [UIApplication.sharedApplication openURL:fallback options:@{} completionHandler:nil];
        return;
    }
    [UIApplication.sharedApplication openURL:urls[i] options:@{} completionHandler:^(BOOL ok) {
        if (!ok) SLOpenChain(urls, i + 1, fallback);
    }];
}

static void SLInstall(SLUpdateInfo *info, UIViewController *presenter) {
    NSURL *page = info.url ? [NSURL URLWithString:info.url] : nil;
    if (!info.ipa) {
        if (page) [UIApplication.sharedApplication openURL:page options:@{} completionHandler:nil];
        return;
    }
    NSMutableCharacterSet *allowed = [NSMutableCharacterSet alphanumericCharacterSet];
    [allowed addCharactersInString:@"-._~"];
    NSString *enc = [info.ipa stringByAddingPercentEncodingWithAllowedCharacters:allowed] ?: info.ipa;

    if (SLInLiveContainer()) {
        if (SLInLiveProcess()) {
            NSURL *u = [NSURL URLWithString:[@"livecontainer://install?url=" stringByAppendingString:enc]];
            if (u) [UIApplication.sharedApplication openURL:u options:@{} completionHandler:nil];
            return;
        }
        UIAlertController *a = [UIAlertController alertControllerWithTitle:@"LiveContainer" message:SLLoc(@"upd_lc") preferredStyle:UIAlertControllerStyleAlert];
        [a addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleCancel handler:nil]];
        [SLTopController(presenter) presentViewController:a animated:YES completion:nil];
        return;
    }

    NSMutableArray<NSString *> *links = [NSMutableArray array];
    if (SLInstalledByTrollStore()) [links addObject:[@"apple-magnifier://install?url=" stringByAppendingString:enc]];
    [links addObjectsFromArray:@[
        [@"sidestore://install?url=" stringByAppendingString:enc],
        [@"altstore://install?url=" stringByAppendingString:enc],
        [@"feather://install/" stringByAppendingString:enc],
        [@"esign://install?url=" stringByAppendingString:enc],
        [@"scarlet://install=" stringByAppendingString:enc],
    ]];
    NSString *side = [[[@"sidestore://install?url=" stringByAppendingString:enc] dataUsingEncoding:NSUTF8StringEncoding] base64EncodedStringWithOptions:0];
    NSString *q = [side stringByAddingPercentEncodingWithAllowedCharacters:[NSCharacterSet alphanumericCharacterSet]] ?: side;
    [links addObject:[@"livecontainer://livecontainer-launch?bundle-name=builtinSideStore&open-url=" stringByAppendingString:q]];

    NSMutableArray<NSURL *> *urls = [NSMutableArray array];
    for (NSString *l in links) {
        NSURL *u = [NSURL URLWithString:l];
        if (u) [urls addObject:u];
    }
    SLOpenChain(urls, 0, page ?: [NSURL URLWithString:info.ipa]);
}

@implementation SLUpdates

+ (NSString *)currentVersion { return @SL_VERSION; }

+ (void)check:(void (^)(SLUpdateInfo *, BOOL))completion {
    NSURLRequest *req = [NSURLRequest requestWithURL:[NSURL URLWithString:SLManifestURL]
                                         cachePolicy:NSURLRequestReloadIgnoringLocalCacheData timeoutInterval:15];
    NSURLSession *s = [NSURLSession sessionWithConfiguration:[NSURLSessionConfiguration ephemeralSessionConfiguration]];
    [[s dataTaskWithRequest:req completionHandler:^(NSData *data, NSURLResponse *resp, NSError *err) {
        SLUpdateInfo *info = nil;
        BOOL failed = YES;
        if (data && data.length <= 16384 && [(NSHTTPURLResponse *)resp statusCode] == 200) {
            NSDictionary *o = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
            if ([o isKindOfClass:[NSDictionary class]] && [o[@"version"] isKindOfClass:[NSString class]]) {
                failed = NO;
                if (SLCompareVersions(o[@"version"], [self currentVersion]) == NSOrderedDescending) {
                    info = [SLUpdateInfo new];
                    info.version = o[@"version"];
                    info.notes = SLNotes(o[@"notes"]);
                    info.ipa = SLHTTPS(o[@"ipa"]);
                    info.url = SLHTTPS(o[@"url"]);
                }
            }
        }
        [s finishTasksAndInvalidate];
        dispatch_async(dispatch_get_main_queue(), ^{ completion(info, failed); });
    }] resume];
}

+ (void)checkOnLaunch {
    static BOOL started;
    if (started) return;
    started = YES;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(8 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        [self checkIfDue];
    });
    [[NSNotificationCenter defaultCenter] addObserverForName:UIApplicationWillEnterForegroundNotification object:nil
                                                       queue:[NSOperationQueue mainQueue] usingBlock:^(NSNotification *n) {
        [self checkIfDue];
    }];
}

+ (void)checkIfDue {
    NSUserDefaults *d = [NSUserDefaults standardUserDefaults];
    NSTimeInterval now = [NSDate date].timeIntervalSince1970;
    if (now - [d doubleForKey:SLLastCheckKey] < 6 * 3600) return;
    [d setDouble:now forKey:SLLastCheckKey];
    [self check:^(SLUpdateInfo *info, BOOL failed) {
        if (failed) [d removeObjectForKey:SLLastCheckKey];
        if (!info || [[d stringForKey:SLSkippedKey] isEqualToString:info.version]) return;
        [self presentUpdate:info from:nil];
    }];
}

+ (void)presentUpdate:(SLUpdateInfo *)info from:(UIViewController *)presenter {
    UIViewController *top = SLTopController(presenter);
    if (!top || [top isKindOfClass:[UIAlertController class]]) return;
    NSString *msg = SLLocFormat(@"upd_text", info.version);
    if (info.notes) msg = [msg stringByAppendingFormat:@"\n\n%@", info.notes];
    UIAlertController *a = [UIAlertController alertControllerWithTitle:SLLoc(@"upd_title") message:msg preferredStyle:UIAlertControllerStyleAlert];
    __weak UIViewController *weakTop = top;
    [a addAction:[UIAlertAction actionWithTitle:SLLoc(@"upd_install") style:UIAlertActionStyleDefault handler:^(UIAlertAction *x) {
        SLInstall(info, weakTop);
    }]];
    [a addAction:[UIAlertAction actionWithTitle:SLLoc(@"upd_skip") style:UIAlertActionStyleDestructive handler:^(UIAlertAction *x) {
        [[NSUserDefaults standardUserDefaults] setObject:info.version forKey:SLSkippedKey];
    }]];
    [a addAction:[UIAlertAction actionWithTitle:SLLoc(@"upd_later") style:UIAlertActionStyleCancel handler:nil]];
    [top presentViewController:a animated:YES completion:nil];
}

@end
