#import "SLLyricsNetwork.h"
#import "SLHook.h"
#import "SLLyricsProvider.h"
#import "SLDebug.h"

static const void *SLCaptureKey = &SLCaptureKey;   // NSMutableData — копия ответа Spotify
static const void *SLTrackKey = &SLTrackKey;       // id трека

/// id трека, если это запрос текста Spotify: .../color-lyrics/v2/track/<id>[/image/...]
static NSString *SLLyricsTrackId(id task) {
    if (![task isKindOfClass:[NSURLSessionTask class]]) return nil;
    NSURLSessionTask *t = task;
    NSString *path = (t.currentRequest.URL ?: t.originalRequest.URL).path;
    NSRange r = path ? [path rangeOfString:@"/color-lyrics/v2/track/"] : NSMakeRange(NSNotFound, 0);
    if (r.location == NSNotFound) return nil;
    NSString *tid = [[path substringFromIndex:NSMaxRange(r)] componentsSeparatedByString:@"/"].firstObject;
    return tid.length == 22 ? tid : nil;
}

static void SLHookDelegate(Class cls) {
    SEL selResp = @selector(URLSession:dataTask:didReceiveResponse:completionHandler:);
    SEL selData = @selector(URLSession:dataTask:didReceiveData:);
    SEL selDone = @selector(URLSession:task:didCompleteWithError:);
    if (!class_getInstanceMethod(cls, selResp) || !class_getInstanceMethod(cls, selData) || !class_getInstanceMethod(cls, selDone)) return;

    SLHook(cls, selResp, ^id(IMP orig) {
        void (*call)(id, SEL, id, id, id, id) = (void (*)(id, SEL, id, id, id, id))orig;
        return ^(id me, NSURLSession *session, NSURLSessionDataTask *task, NSURLResponse *response, id handler) {
            NSString *tid = SLLyricsTrackId(task);
            if (tid) {
                NSInteger status = [response isKindOfClass:[NSHTTPURLResponse class]] ? [(NSHTTPURLResponse *)response statusCode] : 0;
                SLLog(@"spotify lyrics %@ status=%ld", tid, (long)status);
                if (status == 200) {
                    objc_setAssociatedObject(task, SLCaptureKey, [NSMutableData data], OBJC_ASSOCIATION_RETAIN_NONATOMIC);
                    objc_setAssociatedObject(task, SLTrackKey, tid, OBJC_ASSOCIATION_COPY_NONATOMIC);
                }
            }
            call(me, selResp, session, task, response, handler);
        };
    });

    SLHook(cls, selData, ^id(IMP orig) {
        void (*call)(id, SEL, id, id, id) = (void (*)(id, SEL, id, id, id))orig;
        return ^(id me, NSURLSession *session, NSURLSessionDataTask *task, NSData *data) {
            NSMutableData *capture = objc_getAssociatedObject(task, SLCaptureKey);
            if (capture && data) [capture appendData:data];
            call(me, selData, session, task, data);
        };
    });

    SLHook(cls, selDone, ^id(IMP orig) {
        void (*call)(id, SEL, id, id, id) = (void (*)(id, SEL, id, id, id))orig;
        return ^(id me, NSURLSession *session, NSURLSessionTask *task, NSError *error) {
            NSMutableData *capture = objc_getAssociatedObject(task, SLCaptureKey);
            if (capture) {
                NSString *tid = objc_getAssociatedObject(task, SLTrackKey);
                objc_setAssociatedObject(task, SLCaptureKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
                if (!error && tid) [[SLLyricsProvider shared] storeSpotifyResponse:[capture copy] trackId:tid];
            }
            call(me, selDone, session, task, error);
        };
    });
}

void SLInstallLyricsNetworkHooks(void) {
    static NSMutableSet *done;
    if (!done) done = [NSMutableSet set];
    for (NSString *name in @[@"SPTDataLoaderService",
                             @"_TtC26Connectivity_HttpClientKit20HttpClientURLSession",
                             @"Connectivity_HttpClientKit.HttpClientURLSession"]) {
        Class cls = NSClassFromString(name);
        if (!cls || [done containsObject:NSStringFromClass(cls)]) continue;
        [done addObject:NSStringFromClass(cls)];
        SLHookDelegate(cls);
    }
}
