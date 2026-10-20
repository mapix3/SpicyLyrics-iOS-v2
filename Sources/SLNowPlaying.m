#import "SLNowPlaying.h"
#import "SLSettings.h"
#import <MediaPlayer/MediaPlayer.h>
#import <QuartzCore/QuartzCore.h>

NSNotificationName const SLTrackDidChangeNotification = @"SLTrackDidChangeNotification";
NSNotificationName const SLPlaybackDidChangeNotification = @"SLPlaybackDidChangeNotification";
NSNotificationName const SLArtworkDidChangeNotification = @"SLArtworkDidChangeNotification";

@interface SLNowPlaying ()
@property (nonatomic, copy, readwrite) NSString *title;
@property (nonatomic, copy, readwrite) NSString *artist;
@property (nonatomic, copy, readwrite) NSString *album;
@property (nonatomic, copy, readwrite) NSString *trackURI;
@property (nonatomic, readwrite) double duration;
@property (nonatomic, strong, readwrite) UIImage *artwork;
@property (nonatomic, readwrite) BOOL isPlaying;
@property (nonatomic, copy, readwrite) NSString *trackKey;
@property (nonatomic) double elapsedAtUpdate;
@property (nonatomic) double rate;
@property (nonatomic) CFTimeInterval updateStamp;
@property (nonatomic, weak) id lastArtworkObject;
@end

@implementation SLNowPlaying

+ (instancetype)shared {
    static SLNowPlaying *s;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ s = [SLNowPlaying new]; });
    return s;
}

- (double)currentTime {
    double t = self.elapsedAtUpdate;
    if (self.isPlaying && self.rate > 0) t += (CACurrentMediaTime() - self.updateStamp) * self.rate;
    t += [SLSettings shared].syncOffsetMs / 1000.0;
    if (self.duration > 0) t = MIN(t, self.duration);
    return MAX(t, 0);
}

static NSString *SLFindTrackURI(NSDictionary *info) {
    for (id v in info.allValues) {
        if ([v isKindOfClass:[NSString class]] && [(NSString *)v hasPrefix:@"spotify:track:"]) return v;
    }
    return nil;
}

- (void)updateWithInfo:(NSDictionary *)info stamp:(CFTimeInterval)stamp {
    if (![NSThread isMainThread]) {
        NSDictionary *copy = [info copy];
        dispatch_async(dispatch_get_main_queue(), ^{ [self updateWithInfo:copy stamp:stamp]; });
        return;
    }
    if (!info.count) return;

    NSString *title = info[MPMediaItemPropertyTitle];
    NSString *artist = info[MPMediaItemPropertyArtist];
    NSString *album = info[MPMediaItemPropertyAlbumTitle];
    double duration = [info[MPMediaItemPropertyPlaybackDuration] doubleValue];
    NSString *key = [NSString stringWithFormat:@"%@|%@|%.0f", title ?: @"", artist ?: @"", duration];

    BOOL trackChanged = ![key isEqualToString:self.trackKey ?: @""];
    self.title = title;
    self.artist = artist;
    self.album = album;
    self.duration = duration;
    self.trackKey = key;
    NSString *uri = SLFindTrackURI(info);
    if (uri) self.trackURI = uri; else if (trackChanged) self.trackURI = nil;

    NSNumber *elapsed = info[MPNowPlayingInfoPropertyElapsedPlaybackTime];
    NSNumber *rate = info[MPNowPlayingInfoPropertyPlaybackRate];
    if (elapsed) {
        self.elapsedAtUpdate = elapsed.doubleValue;
        self.updateStamp = stamp;
    }
    if (rate) {
        if (!elapsed) { self.elapsedAtUpdate = [self rawTimeAt:stamp]; self.updateStamp = stamp; }
        self.rate = rate.doubleValue;
        self.isPlaying = rate.doubleValue > 0.01;
    }

    NSNotificationCenter *nc = [NSNotificationCenter defaultCenter];
    if (trackChanged) [nc postNotificationName:SLTrackDidChangeNotification object:self];
    [nc postNotificationName:SLPlaybackDidChangeNotification object:self];

    MPMediaItemArtwork *art = info[MPMediaItemPropertyArtwork];
    if (art && art != self.lastArtworkObject) {
        self.lastArtworkObject = art;
        dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^{
            UIImage *img = [art imageWithSize:CGSizeMake(640, 640)];
            dispatch_async(dispatch_get_main_queue(), ^{
                if (!img || self.lastArtworkObject != art) return;
                self.artwork = img;
                [[NSNotificationCenter defaultCenter] postNotificationName:SLArtworkDidChangeNotification object:self];
            });
        });
    } else if (!art && trackChanged) {
        self.lastArtworkObject = nil;
        self.artwork = nil;
        [nc postNotificationName:SLArtworkDidChangeNotification object:self];
    }
}

- (double)rawTime {
    return [self rawTimeAt:CACurrentMediaTime()];
}

- (double)rawTimeAt:(CFTimeInterval)t {
    double v = self.elapsedAtUpdate;
    if (self.isPlaying && self.rate > 0) v += MAX(0, t - self.updateStamp) * self.rate;
    return v;
}

- (void)updatePlaybackState:(NSInteger)state stamp:(CFTimeInterval)stamp {
    void (^apply)(void) = ^{
        BOOL playing = (state == 1);
        if (playing == self.isPlaying) return;
        self.elapsedAtUpdate = [self rawTimeAt:stamp];
        self.updateStamp = stamp;
        self.isPlaying = playing;
        if (playing && self.rate <= 0) self.rate = 1.0;
        [[NSNotificationCenter defaultCenter] postNotificationName:SLPlaybackDidChangeNotification object:self];
    };
    if ([NSThread isMainThread]) apply(); else dispatch_async(dispatch_get_main_queue(), apply);
}

- (void)setElapsedLocally:(double)elapsed {
    self.elapsedAtUpdate = elapsed;
    self.updateStamp = CACurrentMediaTime();
    [[NSNotificationCenter defaultCenter] postNotificationName:SLPlaybackDidChangeNotification object:self];
}

- (void)refreshFromCenter {
    NSDictionary *info = [MPNowPlayingInfoCenter defaultCenter].nowPlayingInfo;
    if (info.count && !self.trackKey) [self updateWithInfo:info stamp:CACurrentMediaTime()];
}

@end
