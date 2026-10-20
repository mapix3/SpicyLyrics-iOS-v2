#import "SLRemote.h"
#import "SLNowPlaying.h"
#import <dlfcn.h>
#import <objc/message.h>

@interface SLRemoteEntry : NSObject
@property (nonatomic, weak) id target;
@property (nonatomic) SEL action;
@property (nonatomic, copy) id handler;
@property (nonatomic, weak) id token;
@end
@implementation SLRemoteEntry
@end

static NSMapTable<MPRemoteCommand *, NSMutableArray<SLRemoteEntry *> *> *SLEntries(void) {
    static NSMapTable *t;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ t = [NSMapTable weakToStrongObjectsMapTable]; });
    return t;
}

static NSMutableArray<SLRemoteEntry *> *SLEntriesFor(MPRemoteCommand *cmd) {
    NSMutableArray *a = [SLEntries() objectForKey:cmd];
    if (!a) { a = [NSMutableArray array]; [SLEntries() setObject:a forKey:cmd]; }
    return a;
}

@implementation SLRemote

+ (void)command:(MPRemoteCommand *)cmd addedTarget:(id)target action:(SEL)action {
    if (!cmd || !target || !action) return;
    @synchronized (self) {
        SLRemoteEntry *e = [SLRemoteEntry new];
        e.target = target; e.action = action;
        [SLEntriesFor(cmd) addObject:e];
    }
}

+ (void)command:(MPRemoteCommand *)cmd addedHandler:(id)handler token:(id)token {
    if (!cmd || !handler) return;
    @synchronized (self) {
        SLRemoteEntry *e = [SLRemoteEntry new];
        e.handler = handler; e.token = token;
        [SLEntriesFor(cmd) addObject:e];
    }
}

+ (void)command:(MPRemoteCommand *)cmd removedTarget:(id)target {
    if (!cmd) return;
    @synchronized (self) {
        NSMutableArray<SLRemoteEntry *> *a = SLEntriesFor(cmd);
        if (!target) { [a removeAllObjects]; return; }
        NSIndexSet *idx = [a indexesOfObjectsPassingTest:^BOOL(SLRemoteEntry *e, NSUInteger i, BOOL *stop) {
            return e.target == target || e.token == target;
        }];
        [a removeObjectsAtIndexes:idx];
    }
}

+ (BOOL)fire:(MPRemoteCommand *)cmd event:(id)event {
    NSArray<SLRemoteEntry *> *entries;
    @synchronized (self) { entries = [SLEntriesFor(cmd) copy]; }
    BOOL fired = NO;
    for (SLRemoteEntry *e in entries) {
        @try {
            if (e.handler) {
                NSInteger (^h)(id) = e.handler;
                h(event);
                fired = YES;
            } else if (e.target && e.action) {
                ((NSInteger (*)(id, SEL, id))objc_msgSend)(e.target, e.action, event);
                fired = YES;
            }
        } @catch (NSException *ex) {
            NSLog(@"[SpicyLyricsiOS] remote handler threw: %@", ex);
        }
    }
    return fired;
}

static id SLMakeEvent(NSString *className, MPRemoteCommand *cmd, NSDictionary *options) {
    Class cls = NSClassFromString(className) ?: NSClassFromString(@"MPRemoteCommandEvent");
    id ev = nil;
    SEL privInit = NSSelectorFromString(@"initWithCommand:mediaRemoteType:options:");
    @try {
        if ([cls instancesRespondToSelector:privInit]) {
            ev = ((id (*)(id, SEL, id, unsigned int, id))objc_msgSend)([cls alloc], privInit, cmd, 0, options);
        }
    } @catch (NSException *ex) { ev = nil; }
    if (!ev) ev = [[cls alloc] init];
    @try { [ev setValue:cmd forKey:@"command"]; } @catch (NSException *ex) {}
    return ev;
}

typedef void (*MRSetElapsedFn)(double);
typedef Boolean (*MRSendCommandFn)(int, CFDictionaryRef);

static void *SLMediaRemote(void) {
    static void *h;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ h = dlopen("/System/Library/PrivateFrameworks/MediaRemote.framework/MediaRemote", RTLD_LAZY); });
    return h;
}

+ (BOOL)seekTo:(double)seconds {
    seconds = MAX(0, seconds);
    MPRemoteCommand *cmd = [MPRemoteCommandCenter sharedCommandCenter].changePlaybackPositionCommand;
    id ev = SLMakeEvent(@"MPChangePlaybackPositionCommandEvent", cmd, @{ @"kMRMediaRemoteOptionPlaybackPosition": @(seconds) });
    @try { [ev setValue:@(seconds) forKey:@"positionTime"]; } @catch (NSException *ex) {}

    BOOL ok = [self fire:cmd event:ev];
    if (!ok) {
        MRSetElapsedFn fn = (MRSetElapsedFn)dlsym(SLMediaRemote(), "MRMediaRemoteSetElapsedTime");
        if (fn) { fn(seconds); ok = YES; }
    }
    if (ok) [[SLNowPlaying shared] setElapsedLocally:seconds];
    return ok;
}

+ (BOOL)togglePlayPause {
    MPRemoteCommandCenter *cc = [MPRemoteCommandCenter sharedCommandCenter];
    BOOL playing = [SLNowPlaying shared].isPlaying;
    MPRemoteCommand *cmd = cc.togglePlayPauseCommand;
    BOOL ok = [self fire:cmd event:SLMakeEvent(@"MPRemoteCommandEvent", cmd, @{})];
    if (!ok) {
        cmd = playing ? cc.pauseCommand : cc.playCommand;
        ok = [self fire:cmd event:SLMakeEvent(@"MPRemoteCommandEvent", cmd, @{})];
    }
    if (!ok) {
        MRSendCommandFn fn = (MRSendCommandFn)dlsym(SLMediaRemote(), "MRMediaRemoteSendCommand");
        if (fn) ok = fn(2 , NULL);
    }
    return ok;
}

@end
