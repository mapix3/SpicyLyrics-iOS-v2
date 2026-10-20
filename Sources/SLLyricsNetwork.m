#import "SLLyricsNetwork.h"
#import <objc/message.h>
#import "SLHook.h"
#import "SLLyricsProvider.h"
#import "SLSpotifyLyrics.h"
#import "SLDebug.h"
#import "SLNowPlaying.h"
#import "SLScrollsita.h"

static const void *SLReplaceKey = &SLReplaceKey;   // NSData — наш ответ вместо оригинального
static const void *SLCaptureKey = &SLCaptureKey;   // NSMutableData — копия настоящего ответа Spotify
static const void *SLTrackKey = &SLTrackKey;       // id трека
static const void *SLPatchKey = &SLPatchKey;       // scrollsita: uri трека, ответ правим целиком
static const void *SLPatchBufKey = &SLPatchBufKey; // scrollsita: накопленное тело
static const void *SLDumpKey = &SLDumpKey;         // диагностика: сохранить тело ответа под этим именем

/// spotify:track:<id>, если это запрос карточек плеера: .../scrollsita/v1/scroll/spotify:track:<id>
static NSString *SLScrollsitaTrackURI(id task) {
    if (![task isKindOfClass:[NSURLSessionTask class]]) return nil;
    NSURLSessionTask *t = task;
    NSString *path = (t.currentRequest.URL ?: t.originalRequest.URL).path;
    NSRange r = path ? [path rangeOfString:@"/scrollsita/v1/scroll/spotify:track:"] : NSMakeRange(NSNotFound, 0);
    if (r.location == NSNotFound) return nil;
    NSString *uri = [path substringFromIndex:r.location + @"/scrollsita/v1/scroll/".length];
    uri = [uri componentsSeparatedByString:@"/"].firstObject;
    return uri.length == @"spotify:track:".length + 22 ? uri : nil;
}

/// Диагностика: всё, что связано с текстом и карточками плеера.
static NSString *SLInterestingPath(id task) {
    if (![task isKindOfClass:[NSURLSessionTask class]]) return nil;
    NSURLRequest *r = [(NSURLSessionTask *)task currentRequest] ?: [(NSURLSessionTask *)task originalRequest];
    NSString *path = r.URL.path.lowercaseString;
    if ([path containsString:@"lyric"] || [path containsString:@"scrollsita"] || [path containsString:@"nowplaying"] || [path containsString:@"now-playing"])
        return [NSString stringWithFormat:@"%@ %@%@", r.HTTPMethod, r.URL.host, r.URL.path];
    return nil;
}

static const double SLSpicyWait = 8.0;             // сколько держим ответ Spotify, пока ждём Spicy

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
            NSInteger status = [response isKindOfClass:[NSHTTPURLResponse class]] ? [(NSHTTPURLResponse *)response statusCode] : 0;
            NSString *scrollURI = status == 200 ? SLScrollsitaTrackURI(task) : nil;
            if (scrollURI) {
                // карточки плеера присылает сервер; для треков без текста Spotify в них нет секции Lyrics — добавим
                objc_setAssociatedObject(task, SLPatchKey, scrollURI, OBJC_ASSOCIATION_COPY_NONATOMIC);
                objc_setAssociatedObject(task, SLPatchBufKey, [NSMutableData data], OBJC_ASSOCIATION_RETAIN_NONATOMIC);
                SLLog(@"scrollsita %@ — will patch", scrollURI);
                call(me, selResp, session, task, response, handler);
                return;
            }
            NSString *interesting = SLInterestingPath(task);
            if (interesting) {
                SLLog(@"HTTP %ld %@ [%@] track=\"%@\"", (long)status, interesting, NSStringFromClass([me class]), [SLNowPlaying shared].title ?: @"");
                if (!tid && status == 200) {
                    NSString *p = [interesting.lowercaseString containsString:@"scrollsita"] ? @"scrollsita" : @"other";
                    objc_setAssociatedObject(task, SLCaptureKey, [NSMutableData data], OBJC_ASSOCIATION_RETAIN_NONATOMIC);
                    objc_setAssociatedObject(task, SLDumpKey, p, OBJC_ASSOCIATION_COPY_NONATOMIC);
                }
            }
            if (!tid || (status != 200 && status != 404)) { call(me, selResp, session, task, response, handler); return; }

            SLLog(@"lyrics request track=%@ status=%ld", tid, (long)status);
            if (status == 200) {
                // у Spotify текст есть — оставляем как есть, но запоминаем как запасной
                objc_setAssociatedObject(task, SLCaptureKey, [NSMutableData data], OBJC_ASSOCIATION_RETAIN_NONATOMIC);
                objc_setAssociatedObject(task, SLTrackKey, tid, OBJC_ASSOCIATION_COPY_NONATOMIC);
                call(me, selResp, session, task, response, handler);
                return;
            }

            // 404: у Spotify текста нет — без ответа 200 он не покажет ни строчку, ни карточку.
            // Держим ответ, пока не узнаем, что есть у Spicy, и отдаём Spotify наш текст.
            __block BOOL fired = NO;
            void (^respond)(SLLyrics *) = ^(SLLyrics *ly) {
                if (fired) return;
                fired = YES;
                NSData *body = SLSpotifyResponseFromLyrics(ly);
                NSHTTPURLResponse *ok = [[NSHTTPURLResponse alloc] initWithURL:response.URL ?: task.currentRequest.URL
                                                                    statusCode:200 HTTPVersion:@"HTTP/2"
                                                                  headerFields:@{ @"Content-Type": @"application/protobuf" }];
                objc_setAssociatedObject(task, SLReplaceKey, body, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
                SLLog(@"lyrics 404 -> 200 track=%@ spicy=%@ (%lu bytes)", tid, ly ? @"yes" : @"no", (unsigned long)body.length);
                call(me, selResp, session, task, ok ?: response, handler);
            };
            [[SLLyricsProvider shared] spicyLyricsForTrackId:tid completion:^(SLLyrics *ly, NSString *err) { respond(ly); }];
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(SLSpicyWait * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{ respond(nil); });
        };
    });

    SLHook(cls, selData, ^id(IMP orig) {
        void (*call)(id, SEL, id, id, id) = (void (*)(id, SEL, id, id, id))orig;
        return ^(id me, NSURLSession *session, NSURLSessionDataTask *task, NSData *data) {
            if (objc_getAssociatedObject(task, SLReplaceKey)) return;   // тело 404 Spotify не нужно
            NSMutableData *patchBuf = objc_getAssociatedObject(task, SLPatchBufKey);
            if (patchBuf) { if (data) [patchBuf appendData:data]; return; }   // отдадим целиком в конце
            NSMutableData *capture = objc_getAssociatedObject(task, SLCaptureKey);
            if (capture && data) [capture appendData:data];
            call(me, selData, session, task, data);
        };
    });

    SLHook(cls, selDone, ^id(IMP orig) {
        void (*call)(id, SEL, id, id, id) = (void (*)(id, SEL, id, id, id))orig;
        return ^(id me, NSURLSession *session, NSURLSessionTask *task, NSError *error) {
            NSData *body = objc_getAssociatedObject(task, SLReplaceKey);
            if (body) {
                objc_setAssociatedObject(task, SLReplaceKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
                // получатель текста в Spotify 9.1.6x+ живёт на главном потоке
                dispatch_async(dispatch_get_main_queue(), ^{
                    ((void (*)(id, SEL, id, id, id))objc_msgSend)(me, selData, session, task, body);
                    call(me, selDone, session, task, nil);
                });
                return;
            }
            NSString *patchURI = objc_getAssociatedObject(task, SLPatchKey);
            if (patchURI) {
                NSMutableData *buf = objc_getAssociatedObject(task, SLPatchBufKey);
                objc_setAssociatedObject(task, SLPatchKey, nil, OBJC_ASSOCIATION_COPY_NONATOMIC);
                objc_setAssociatedObject(task, SLPatchBufKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
                NSData *body = buf ?: [NSData data];
                if (!error && body.length) {
                    size_t outLen = 0;
                    uint8_t *patched = SLScrollsitaAddLyrics(body.bytes, body.length, patchURI.UTF8String, &outLen);
                    if (patched) {
                        body = [NSData dataWithBytesNoCopy:patched length:outLen freeWhenDone:YES];
                        SLLog(@"scrollsita %@ patched %lu -> %lu", patchURI, (unsigned long)buf.length, (unsigned long)outLen);
                        SLDebugSaveBody(@"scrollsita-patched", body);
                    } else {
                        SLLog(@"scrollsita %@ unchanged (%lu bytes)", patchURI, (unsigned long)buf.length);
                        SLDebugSaveBody(@"scrollsita", body);
                    }
                }
                ((void (*)(id, SEL, id, id, id))objc_msgSend)(me, selData, session, task, body);
                call(me, selDone, session, task, error);
                return;
            }
            NSMutableData *capture = objc_getAssociatedObject(task, SLCaptureKey);
            if (capture) {
                NSString *tid = objc_getAssociatedObject(task, SLTrackKey);
                NSString *dump = objc_getAssociatedObject(task, SLDumpKey);
                objc_setAssociatedObject(task, SLCaptureKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
                if (!error && tid) [[SLLyricsProvider shared] storeSpotifyResponse:[capture copy] trackId:tid];
                if (!error && tid) SLDebugSaveBody(@"spotify-lyrics", capture);
                if (!error && dump) SLDebugSaveBody(dump, capture);
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
