#import "SLSettings.h"

NSNotificationName const SLSettingsDidChangeNotification = @"SLSettingsDidChangeNotification";

#define SLKey(k) (@"SpicyLyricsiOS." k)

@implementation SLSettings {
    NSUserDefaults *_d;
}

+ (instancetype)shared {
    static SLSettings *s;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ s = [SLSettings new]; });
    return s;
}

- (instancetype)init {
    if ((self = [super init])) {
        _d = [NSUserDefaults standardUserDefaults];
        [_d registerDefaults:@{
            SLKey("offset"): @0,
            SLKey("fontScale"): @1.0,
            SLKey("dynamicBg"): @YES,
            SLKey("bubble2"): @YES,
            SLKey("bgVocals"): @YES,
            SLKey("glow"): @YES,
        }];
    }
    return self;
}

- (void)changed { [[NSNotificationCenter defaultCenter] postNotificationName:SLSettingsDidChangeNotification object:self]; }

- (NSInteger)syncOffsetMs { return [_d integerForKey:SLKey("offset")]; }
- (void)setSyncOffsetMs:(NSInteger)v { [_d setInteger:v forKey:SLKey("offset")]; [self changed]; }

- (CGFloat)fontScale { return MIN(MAX([_d doubleForKey:SLKey("fontScale")], 0.7), 1.6); }
- (void)setFontScale:(CGFloat)v { [_d setDouble:v forKey:SLKey("fontScale")]; [self changed]; }

- (BOOL)dynamicBackground { return [_d boolForKey:SLKey("dynamicBg")]; }
- (void)setDynamicBackground:(BOOL)v { [_d setBool:v forKey:SLKey("dynamicBg")]; [self changed]; }

- (BOOL)showBubble { return [_d boolForKey:SLKey("bubble2")]; }
- (void)setShowBubble:(BOOL)v { [_d setBool:v forKey:SLKey("bubble2")]; [self changed]; }

- (BOOL)wordGlow { return [_d boolForKey:SLKey("glow")]; }
- (void)setWordGlow:(BOOL)v { [_d setBool:v forKey:SLKey("glow")]; [self changed]; }

- (BOOL)showBackgroundVocals { return [_d boolForKey:SLKey("bgVocals")]; }
- (void)setShowBackgroundVocals:(BOOL)v { [_d setBool:v forKey:SLKey("bgVocals")]; [self changed]; }


- (CGPoint)bubbleCenter {
    NSString *s = [_d stringForKey:SLKey("bubbleCenter")];
    return s ? CGPointFromString(s) : CGPointZero;
}
- (void)setBubbleCenter:(CGPoint)p { [_d setObject:NSStringFromCGPoint(p) forKey:SLKey("bubbleCenter")]; }

@end
