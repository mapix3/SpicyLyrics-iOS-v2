#import "SLPlayerLyrics.h"
#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import "SLLyricsView.h"
#import "SLLyricsViewController.h"
#import "SLLocalization.h"
#import "SLHook.h"
#import "SLDebug.h"
#import "SLNowPlaying.h"
#import "SLSettingsViewController.h"
#import <objc/message.h>

typedef NS_ENUM(NSInteger, SLHostKind) {
    SLHostKindStrip = 0,   // строчка текста прямо на плеере (lyrics preview)
    SLHostKindCard = 1,    // карточка «Текст» под плеером (Lyrics_CardElementImpl.CardView)
};

static CGFloat SLHostCornerRadius(UIView *host) {
    if (host.layer.cornerRadius > 0) return host.layer.cornerRadius;
    for (UIView *v in host.subviews) if (v.layer.cornerRadius > 0 && CGRectEqualToRect(v.frame, host.bounds)) return v.layer.cornerRadius;
    UIView *p = host.superview;
    for (int i = 0; p && i < 3; i++, p = p.superview) if (p.layer.cornerRadius > 0) return p.layer.cornerRadius;
    return 12;
}

#pragma mark - Overlay

/// Наш текст поверх Spotify-шной вьюхи. Оригинальное содержимое прячется (alpha = 0),
/// сама вьюха Spotify остаётся — её размер, анимации появления и место в плеере не трогаем.
@interface SLPlayerLyricsOverlay : UIView <UIGestureRecognizerDelegate>
- (instancetype)initWithKind:(SLHostKind)kind;
- (void)conceal;
@end

@implementation SLPlayerLyricsOverlay {
    SLHostKind _kind;
    SLLyricsView *_lyrics;
    UILabel *_title;
    UIView *_expand;
    NSTimer *_guard;
}

- (instancetype)initWithKind:(SLHostKind)kind {
    if ((self = [super initWithFrame:CGRectZero])) {
        _kind = kind;
        BOOL card = kind == SLHostKindCard;
        self.clipsToBounds = YES;
        self.backgroundColor = card ? [UIColor colorWithWhite:0.07 alpha:1] : UIColor.clearColor;
        self.overrideUserInterfaceStyle = UIUserInterfaceStyleDark;

        _lyrics = [[SLLyricsView alloc] initWithMode:card ? SLLyricsViewModeCompact : SLLyricsViewModeStrip];
        _lyrics.interactive = NO;
        _lyrics.showsBackground = card;
        _lyrics.showsAttribution = card;
        if (card) _lyrics.contentInsets = UIEdgeInsetsMake(50, 16, 0, 16);
        [self addSubview:_lyrics];

        if (card) {
            self.layer.cornerRadius = 12;
            self.layer.cornerCurve = kCACornerCurveContinuous;

            _title = [UILabel new];
            _title.text = SLLoc(@"lyrics");
            _title.font = [UIFont systemFontOfSize:16 weight:UIFontWeightBold];
            _title.textColor = UIColor.whiteColor;
            [self addSubview:_title];

            _expand = [UIView new];
            _expand.backgroundColor = [UIColor colorWithWhite:1 alpha:0.14];
            _expand.layer.cornerRadius = 15;
            _expand.userInteractionEnabled = NO;
            UIImageView *icon = [[UIImageView alloc] initWithImage:
                [UIImage systemImageNamed:@"arrow.up.left.and.arrow.down.right"
                        withConfiguration:[UIImageSymbolConfiguration configurationWithPointSize:12 weight:UIImageSymbolWeightBold]]];
            icon.tintColor = UIColor.whiteColor;
            icon.contentMode = UIViewContentModeCenter;
            icon.frame = CGRectMake(0, 0, 30, 30);
            [_expand addSubview:icon];
            [self addSubview:_expand];
        }

        UITapGestureRecognizer *tap = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(open)];
        tap.delegate = self;
        [self addGestureRecognizer:tap];
        UILongPressGestureRecognizer *hold = [[UILongPressGestureRecognizer alloc] initWithTarget:self action:@selector(hold:)];
        hold.minimumPressDuration = 0.6;
        [self addGestureRecognizer:hold];

        self.isAccessibilityElement = YES;
        self.accessibilityLabel = SLLoc(@"lyrics");
        self.accessibilityTraits = UIAccessibilityTraitButton;
    }
    return self;
}

- (void)dealloc { [_guard invalidate]; }

- (void)layoutSubviews {
    [super layoutSubviews];
    CGRect b = self.bounds;
    _lyrics.frame = b;
    if (_kind == SLHostKindCard) {
        _expand.frame = CGRectMake(b.size.width - 16 - 30, 12, 30, 30);
        _title.frame = CGRectMake(16, 15, MAX(0, CGRectGetMinX(_expand.frame) - 24), 24);
    }
}

- (void)didMoveToWindow {
    [super didMoveToWindow];
    [_guard invalidate];
    _guard = nil;
    if (!self.window) return;
    // Spotify может вернуть своему содержимому alpha (смена трека, анимации) — периодически прячем снова
    __weak typeof(self) weakSelf = self;
    _guard = [NSTimer scheduledTimerWithTimeInterval:0.5 repeats:YES block:^(NSTimer *t) { [weakSelf conceal]; }];
    [self conceal];
}

- (void)conceal {
    UIView *host = self.superview;
    if (!host) return;
    for (UIView *v in host.subviews) {
        if (v == self || v.alpha == 0) continue;
        v.alpha = 0;
        v.accessibilityElementsHidden = YES;
    }
    if (host.subviews.lastObject != self) [host bringSubviewToFront:self];
    if (!CGRectEqualToRect(self.frame, host.bounds)) self.frame = host.bounds;
    if (_kind == SLHostKindCard) {
        CGFloat r = SLHostCornerRadius(host);
        if (fabs(self.layer.cornerRadius - r) > 0.5) self.layer.cornerRadius = r;
    }
}

- (void)hold:(UILongPressGestureRecognizer *)g {
    if (g.state != UIGestureRecognizerStateBegan) return;
    [SLSettingsViewController presentFrom:nil];
}

- (void)open {
    [[[UIImpactFeedbackGenerator alloc] initWithStyle:UIImpactFeedbackStyleLight] impactOccurred];
    if (_kind == SLHostKindCard) {
        [UIView animateWithDuration:0.1 animations:^{ self.transform = CGAffineTransformMakeScale(0.97, 0.97); } completion:^(BOOL d) {
            [UIView animateWithDuration:0.2 animations:^{ self.transform = CGAffineTransformIdentity; }];
        }];
    }
    [SLLyricsViewController presentFromTopController];
}

// Тапы не уходят дальше по цепочке (в ячейку, к обработчикам Spotify)
- (void)touchesBegan:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event {}
- (void)touchesMoved:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event {}
- (void)touchesEnded:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event {}
- (void)touchesCancelled:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event {}

// Тапы Spotify на родительских вьюхах (открыть его собственный текст) ждут, пока не сработает наш
- (BOOL)gestureRecognizer:(UIGestureRecognizer *)g shouldBeRequiredToFailByGestureRecognizer:(UIGestureRecognizer *)other {
    return [other isKindOfClass:[UITapGestureRecognizer class]] && other.view != self && [self isDescendantOfView:other.view];
}

@end

#pragma mark - Hooks

static const void *SLOverlayKey = &SLOverlayKey;

static NSMutableSet<NSString *> *SLInstalled(void) {
    static NSMutableSet *s;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ s = [NSMutableSet set]; });
    return s;
}

static Class SLFindClass(NSArray<NSString *> *names) {
    for (NSString *n in names) {
        Class c = NSClassFromString(n);
        if (c) return c;
    }
    return nil;
}

static void SLAttach(UIView *host, SLHostKind kind) {
    if (!host.window) return;
    SLPlayerLyricsOverlay *ov = objc_getAssociatedObject(host, SLOverlayKey);
    // вложенные вьюхи текста Spotify: наш текст уже стоит на внешней — внутренний не нужен
    for (UIView *p = host.superview; p; p = p.superview) {
        if (objc_getAssociatedObject(p, SLOverlayKey)) {
            if (ov) { [ov removeFromSuperview]; objc_setAssociatedObject(host, SLOverlayKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC); }
            return;
        }
    }
    if (!ov) {
        SLLog(@"overlay %@ on %@ %@", kind == SLHostKindCard ? @"card" : @"strip", NSStringFromClass([host class]), NSStringFromCGRect(host.frame));
        ov = [[SLPlayerLyricsOverlay alloc] initWithKind:kind];
        objc_setAssociatedObject(host, SLOverlayKey, ov, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    if (ov.superview != host) {
        ov.frame = host.bounds;
        [host addSubview:ov];
    }
    [ov conceal];
}

static void SLHookHost(NSString *tag, NSArray<NSString *> *names, SLHostKind kind) {
    if ([SLInstalled() containsObject:tag]) return;
    Class cls = SLFindClass(names);
    if (!cls) return;
    [SLInstalled() addObject:tag];
    for (NSString *name in @[@"layoutSubviews", @"didMoveToWindow"]) {
        SEL sel = NSSelectorFromString(name);
        SLHook(cls, sel, ^id(IMP orig) {
            return ^(UIView *view) {
                ((void (*)(id, SEL))orig)(view, sel);
                SLAttach(view, kind);
            };
        });
    }
    // если тап всё-таки дошёл до Spotify — открываем наш экран, а не его
    SEL tapped = NSSelectorFromString(@"lyricsTapped");
    if ([cls instancesRespondToSelector:tapped]) {
        SLHook(cls, tapped, ^id(IMP orig) {
            return ^(UIView *view) { [SLLyricsViewController presentFromTopController]; };
        });
    }
}

/// Spotify запрашивает текст только у треков, у которых он сам знает про текст (has_lyrics).
/// В его remote config есть флаг ios-feature-lyrics.enable_has_lyrics_check_bypass — включаем его,
/// тогда запрос уходит для любого трека, а 404 подменяет SLLyricsNetwork.
void SLInstallLyricsConfigHook(void) {
    static BOOL done;
    if (done) return;
    Class cls = SLFindClass(@[@"_TtC24Lyrics_ConfigurationImpl37SPTLyrics_ConfigurationImplProperties",
                              @"Lyrics_ConfigurationImpl.SPTLyrics_ConfigurationImplProperties"]);
    Ivar flag = cls ? class_getInstanceVariable(cls, "enableHasLyricsCheckBypass") : NULL;
    if (!flag) return;
    ptrdiff_t offset = ivar_getOffset(flag);
    SEL sel = NSSelectorFromString(@"initWithConfigurationProvider:");
    done = SLHook(cls, sel, ^id(IMP orig) {
        return ^id(id me, id provider) {
            id obj = ((id (*)(id, SEL, id))orig)(me, sel, provider);
            if (obj) {
                uint8_t *p = (uint8_t *)(__bridge void *)obj + offset;
                SLLog(@"lyrics config: enableHasLyricsCheckBypass was %d", *p);
                if (*p <= 1) *p = 1;   // Bool — пишем только если там действительно 0/1
            }
            return obj;
        };
    });
}

/// Только обычные треки (не реклама, не подкасты, не локальные файлы).
static BOOL SLIsMusicTrack(id track) {
    static SEL uriSel;
    if (!uriSel) uriSel = NSSelectorFromString(@"URI");
    if (![track respondsToSelector:uriSel]) return NO;
    id uri = ((id (*)(id, SEL))objc_msgSend)(track, uriSel);
    NSString *s = [uri isKindOfClass:[NSURL class]] ? [uri absoluteString] : ([uri isKindOfClass:[NSString class]] ? uri : nil);
    return [s hasPrefix:@"spotify:track:"];
}

static void SLNoteForced(id track, NSString *via) {
    static NSMutableSet *seen;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ seen = [NSMutableSet set]; });
    NSString *key = [NSString stringWithFormat:@"%p-%@", track, via];
    @synchronized (seen) {
        if ([seen containsObject:key] || seen.count > 200) return;
        [seen addObject:key];
    }
    SLLog(@"has_lyrics forced via %@", via);
}

void SLInstallHasLyricsHooks(void) {
    static BOOL done;
    if (done) return;
    done = YES;
    Class cls = NSClassFromString(@"SPTPlayerTrack");
    if (!cls) { SLLog(@"has_lyrics hooks: SPTPlayerTrack missing"); return; }
    SEL hasLyrics = NSSelectorFromString(@"spt_hasLyrics");
    SEL metaKey = NSSelectorFromString(@"metadataValueForKey:");
    SEL meta = NSSelectorFromString(@"metadata");
    BOOL a = SLHook(cls, hasLyrics, ^id(IMP orig) {
        return ^BOOL(id track) {
            if (((BOOL (*)(id, SEL))orig)(track, hasLyrics)) return YES;
            if (!SLIsMusicTrack(track)) return NO;
            SLNoteForced(track, @"spt_hasLyrics");
            return YES;
        };
    });
    BOOL b = SLHook(cls, metaKey, ^id(IMP orig) {
        return ^id(id track, id key) {
            id v = ((id (*)(id, SEL, id))orig)(track, metaKey, key);
            if (![key isKindOfClass:[NSString class]] || ![key isEqualToString:@"has_lyrics"]) return v;
            if ([v isEqual:@"true"] || !SLIsMusicTrack(track)) return v;
            SLNoteForced(track, @"metadataValueForKey");
            return @"true";
        };
    });
    BOOL c = SLHook(cls, meta, ^id(IMP orig) {
        return ^NSDictionary *(id track) {
            NSDictionary *m = ((NSDictionary *(*)(id, SEL))orig)(track, meta);
            if (![m isKindOfClass:[NSDictionary class]] || [m[@"has_lyrics"] isEqual:@"true"] || !SLIsMusicTrack(track)) return m;
            NSMutableDictionary *mm = [m mutableCopy];
            mm[@"has_lyrics"] = @"true";
            return [mm copy];
        };
    });
    SLLog(@"has_lyrics hooks: spt_hasLyrics=%d metadataValueForKey=%d metadata=%d", a, b, c);
}

void SLInstallDebugHooks(void) {
    static BOOL done;
    if (done) return;
    Class cls = SLFindClass(@[@"_TtC21NowPlaying_ScrollImpl23NPVScrollViewController", @"NowPlaying_ScrollImpl.NPVScrollViewController"]);
    SEL sel = @selector(viewDidAppear:);
    done = SLHook(cls, sel, ^id(IMP orig) {
        return ^(UIViewController *vc, BOOL animated) {
            ((void (*)(id, SEL, BOOL))orig)(vc, sel, animated);
            __weak UIViewController *weakVC = vc;
            for (NSNumber *delay in @[@1.5, @5.0]) {
                dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(delay.doubleValue * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                    UIViewController *v = weakVC;
                    if (!v.viewIfLoaded.window) return;
                    NSString *title = [[SLNowPlaying shared].title ?: @"" stringByReplacingOccurrencesOfString:@"/" withString:@"_"];
                    SLDebugDumpViews([NSString stringWithFormat:@"npv-%@", title], v.view);
                });
            }
        };
    });
    SLLog(@"debug hooks: NPVScrollViewController %@", done ? @"ok" : @"missing");
}

void SLInstallPlayerHooks(void) {
    // строчка текста на плеере — в 9.1.x встречается в нескольких вариантах
    SLHookHost(@"strip.canvas", @[@"_TtC17Canvas_CommonImpl26CanvasNowPlayingLyricsView",
                                  @"Canvas_CommonImpl.CanvasNowPlayingLyricsView"], SLHostKindStrip);
    SLHookHost(@"strip.container", @[@"_TtC22Lyrics_NPVContainerKit19LyricsContainerView",
                                     @"Lyrics_NPVContainerKit.LyricsContainerView"], SLHostKindStrip);
    SLHookHost(@"strip.legacy", @[@"_TtC28NowPlaying_ContentLayersImpl25LegacyLyricsContainerView",
                                  @"NowPlaying_ContentLayersImpl.LegacyLyricsContainerView"], SLHostKindStrip);
    SLHookHost(@"strip.element", @[@"_TtC25Lyrics_NPVElementsKitImpl26LyricsElementContainerView",
                                   @"Lyrics_NPVElementsKitImpl.LyricsElementContainerView"], SLHostKindStrip);
    SLHookHost(@"card", @[@"_TtC22Lyrics_CardElementImpl8CardView",
                          @"Lyrics_CardElementImpl.CardView"], SLHostKindCard);
}
