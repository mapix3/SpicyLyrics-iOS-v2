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

typedef NS_ENUM(NSInteger, SLHostKind) {
    SLHostKindStrip = 0,
    SLHostKindCard = 1,
};

static CGFloat SLHostCornerRadius(UIView *host) {
    if (host.layer.cornerRadius > 0) return host.layer.cornerRadius;
    for (UIView *v in host.subviews) if (v.layer.cornerRadius > 0 && CGRectEqualToRect(v.frame, host.bounds)) return v.layer.cornerRadius;
    UIView *p = host.superview;
    for (int i = 0; p && i < 3; i++, p = p.superview) if (p.layer.cornerRadius > 0) return p.layer.cornerRadius;
    return 12;
}

@interface SLPlayerLyricsOverlay : UIView <UIGestureRecognizerDelegate>
@property (nonatomic) BOOL standalone;
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
    if (!self.window || _standalone) return;
    __weak typeof(self) weakSelf = self;
    _guard = [NSTimer scheduledTimerWithTimeInterval:0.5 repeats:YES block:^(NSTimer *t) { [weakSelf conceal]; }];
    [self conceal];
}

- (void)setStandalone:(BOOL)standalone {
    _standalone = standalone;
    if (standalone && _kind == SLHostKindCard) self.layer.cornerRadius = 16;
}

- (void)conceal {
    UIView *host = self.superview;
    if (!host || _standalone) return;
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

- (void)touchesBegan:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event {}
- (void)touchesMoved:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event {}
- (void)touchesEnded:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event {}
- (void)touchesCancelled:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event {}

- (BOOL)gestureRecognizer:(UIGestureRecognizer *)g shouldBeRequiredToFailByGestureRecognizer:(UIGestureRecognizer *)other {
    return [other isKindOfClass:[UITapGestureRecognizer class]] && other.view != self && [self isDescendantOfView:other.view];
}

@end

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
    SEL tapped = NSSelectorFromString(@"lyricsTapped");
    if ([cls instancesRespondToSelector:tapped]) {
        SLHook(cls, tapped, ^id(IMP orig) {
            return ^(UIView *view) { [SLLyricsViewController presentFromTopController]; };
        });
    }
}

typedef NS_ENUM(NSInteger, SLCellMode) {
    SLCellModeNone = 0,
    SLCellModePrepend = 1,
    SLCellModeReplace = 2,
    SLCellModeCollapse = 3,
};

static const CGFloat SLCardHeight = 340;
static const CGFloat SLCardGap = 24;
static NSString *const SLNPVCollectionID = @"scrolling_npv_collection_view_accessibility_identifier";
static const void *SLModeKey = &SLModeKey;
static const void *SLCardKey = &SLCardKey;
static const void *SLDimmedKey = &SLDimmedKey;
static const void *SLMaskKey = &SLMaskKey;
static const CGFloat SLCardRadius = 16;

static BOOL SLIsNPVCell(UICollectionViewCell *cell) {
    UIView *cv = cell.superview;
    if ([cv isKindOfClass:[UICollectionView class]]) return [cv.accessibilityIdentifier isEqualToString:SLNPVCollectionID];
    UIView *content = cell.contentView.subviews.firstObject;
    return content && [NSStringFromClass([content class]) containsString:@"NowPlaying_ScrollAPI"];
}

static BOOL SLContainsLyricsCard(UIView *root) {
    NSMutableArray<UIView *> *queue = [NSMutableArray arrayWithObject:root];
    for (NSUInteger i = 0; i < queue.count && i < 60; i++) {
        UIView *v = queue[i];
        if ([v.accessibilityIdentifier isEqualToString:@"lyrics-card-view"] ||
            [NSStringFromClass([v class]) containsString:@"Lyrics_CardElementImpl"]) return YES;
        [queue addObjectsFromArray:v.subviews];
    }
    return NO;
}

static void SLApplyCellMode(UICollectionViewCell *cell) {
    SLCellMode mode = [objc_getAssociatedObject(cell, SLModeKey) integerValue];
    SLPlayerLyricsOverlay *card = objc_getAssociatedObject(cell, SLCardKey);
    UIView *content = cell.contentView;
    CGRect b = cell.bounds;

    if (mode == SLCellModePrepend || mode == SLCellModeReplace) {
        if (!card) {
            card = [[SLPlayerLyricsOverlay alloc] initWithKind:SLHostKindCard];
            card.standalone = YES;
            objc_setAssociatedObject(cell, SLCardKey, card, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        }
        if (card.superview != cell) [cell addSubview:card];
        else if (cell.subviews.lastObject != card) [cell bringSubviewToFront:card];
        CGRect f = CGRectMake(0, 0, b.size.width, MIN(SLCardHeight, b.size.height));
        if (!CGRectEqualToRect(card.frame, f)) card.frame = f;
    } else if (card.superview) {
        [card removeFromSuperview];
    }

    CAShapeLayer *mask = objc_getAssociatedObject(cell, SLMaskKey);
    if (mode == SLCellModePrepend) {
        CGFloat d = SLCardHeight + SLCardGap;
        CGRect f = CGRectMake(0, d, b.size.width, MAX(0, b.size.height - d));
        if (!CGRectEqualToRect(content.frame, f)) content.frame = f;
        if (!mask) {
            mask = [CAShapeLayer layer];
            objc_setAssociatedObject(cell, SLMaskKey, mask, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        }
        UIBezierPath *path = [UIBezierPath bezierPathWithRoundedRect:CGRectMake(0, 0, b.size.width, SLCardHeight) cornerRadius:SLCardRadius];
        [path appendPath:[UIBezierPath bezierPathWithRoundedRect:f cornerRadius:SLCardRadius]];
        [CATransaction begin];
        [CATransaction setDisableActions:YES];
        mask.frame = cell.bounds;
        mask.path = path.CGPath;
        [CATransaction commit];
        if (cell.layer.mask != mask) cell.layer.mask = mask;
    } else if (mask && cell.layer.mask == mask) {
        cell.layer.mask = nil;
    }
    BOOL dim = mode == SLCellModeReplace || mode == SLCellModeCollapse;
    BOOL dimmed = [objc_getAssociatedObject(cell, SLDimmedKey) boolValue];
    if (dim != dimmed) {
        content.alpha = dim ? 0 : 1;
        content.userInteractionEnabled = !dim;
        objc_setAssociatedObject(cell, SLDimmedKey, @(dim), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    cell.clipsToBounds = mode != SLCellModeNone;
}

static const void *SLGapKey = &SLGapKey;

static BOOL SLVisibleIn(UIView *v, UIView *root) {
    if (!v.window) return NO;
    for (UIView *p = v; p && p != root; p = p.superview) if (p.hidden || p.alpha < 0.01) return NO;
    return YES;
}

static BOOL SLHasVisibleText(UIView *root) {
    NSMutableArray<UIView *> *queue = [NSMutableArray arrayWithObject:root];
    for (NSUInteger i = 0; i < queue.count && i < 80; i++) {
        UIView *v = queue[i];
        if (v.hidden || v.alpha < 0.01) continue;
        if ([v isKindOfClass:[UILabel class]] && ((UILabel *)v).text.length && v.bounds.size.width > 1) return YES;
        [queue addObjectsFromArray:v.subviews];
    }
    return NO;
}

@interface SLGapStripController : NSObject
@property (nonatomic, weak) UIView *root;
@property (nonatomic, strong) SLPlayerLyricsOverlay *strip;
@property (nonatomic, strong) NSTimer *timer;
@property (nonatomic) CFTimeInterval lastUpdate;
- (void)update;
@end

@implementation SLGapStripController

- (void)dealloc { [_timer invalidate]; }

- (void)ensureTimer {
    if (self.timer) return;
    __weak typeof(self) weakSelf = self;
    self.timer = [NSTimer scheduledTimerWithTimeInterval:0.4 repeats:YES block:^(NSTimer *t) {
        SLGapStripController *c = weakSelf;
        if (!c.root.window) { [t invalidate]; c.timer = nil; return; }
        [c update];
    }];
}

- (void)setShown:(BOOL)shown {
    CGFloat want = shown ? 1 : 0;
    if (self.strip.alpha == want) return;
    [UIView animateWithDuration:0.2 animations:^{ self.strip.alpha = want; }];
    self.strip.userInteractionEnabled = shown;
}

- (void)update {
    UIView *root = self.root;
    if (!root.window) return;
    self.lastUpdate = CACurrentMediaTime();
    [self ensureTimer];
    if (!self.strip) {
        self.strip = [[SLPlayerLyricsOverlay alloc] initWithKind:SLHostKindStrip];
        self.strip.standalone = YES;
        self.strip.alpha = 0;
    }
    if (self.strip.superview != root) [root addSubview:self.strip];
    else if (root.subviews.lastObject != self.strip) [root bringSubviewToFront:self.strip];

    CGRect art = CGRectNull, best = CGRectNull;
    CGFloat info = CGFLOAT_MAX, floating = CGFLOAT_MAX;
    BOOL spotifyStrip = NO;
    CGRect bounds = root.bounds;
    NSMutableArray<UIView *> *queue = [NSMutableArray arrayWithArray:root.subviews];
    for (NSUInteger i = 0; i < queue.count && i < 3000; i++) {
        UIView *v = queue[i];
        if (v == self.strip || v.hidden || v.alpha < 0.01) continue;
        if ([v isKindOfClass:[SLPlayerLyricsOverlay class]]) {
            if (!((SLPlayerLyricsOverlay *)v).standalone && v.bounds.size.height > 8 && SLVisibleIn(v, root)) {
                CGRect r = [v convertRect:v.bounds toView:root];
                if (CGRectIntersectsRect(r, bounds)) spotifyStrip = YES;
            }
            continue;
        }
        NSString *cls = NSStringFromClass([v class]);
        NSString *owner = [v.nextResponder isKindOfClass:[UIViewController class]] ? NSStringFromClass([v.nextResponder class]) : nil;
        if ([cls containsString:@"CoverArtTiltView"] && SLVisibleIn(v, root)) {
            CGRect r = [v convertRect:v.bounds toView:root];
            CGRect vis = CGRectIntersection(r, bounds);
            if (!CGRectIsNull(vis) && (CGRectIsNull(best) || vis.size.width * vis.size.height > best.size.width * best.size.height)) {
                best = vis; art = r;
            }
            continue;
        }
        if ([cls containsString:@"LyricsElementWrapperView"] || [cls containsString:@"LyricsContainerView"] ||
            [cls containsString:@"CanvasNowPlayingLyricsView"]) {
            if (v.bounds.size.height > 8 && SLVisibleIn(v, root)) {
                CGRect r = [v convertRect:v.bounds toView:root];
                if (CGRectIntersectsRect(r, bounds)) { spotifyStrip = YES; continue; }
            }
        }
        if ([owner containsString:@"InformationElementsUnit"] && SLVisibleIn(v, root)) {
            info = MIN(info, CGRectGetMinY([v convertRect:v.bounds toView:root]));
            continue;
        }
        if ([owner containsString:@"FloatingElementsUnit"] && v.bounds.size.height > 1 && SLVisibleIn(v, root) && SLHasVisibleText(v)) {
            floating = MIN(floating, CGRectGetMinY([v convertRect:v.bounds toView:root]));
            continue;
        }
        if (v.bounds.size.width > 0) [queue addObjectsFromArray:v.subviews];
    }

    CGFloat top = CGRectGetMaxY(art);
    CGFloat bottom = MIN(info, floating) - 8;
    CGFloat h = MIN(bottom - top, 110);
    BOOL show = !CGRectIsNull(art) && !spotifyStrip && info < CGFLOAT_MAX && h >= 48;
    if (show) {
        CGRect f = CGRectMake(CGRectGetMinX(art), top, art.size.width, h);
        if (!CGRectEqualToRect(self.strip.frame, f)) self.strip.frame = f;
    }
    [self setShown:show];
}

@end

static void SLInstallGapStrip(void) {
    static BOOL done;
    if (done) return;
    Class cls = SLFindClass(@[@"_TtC19NowPlaying_ViewImpl24NowPlayingViewController", @"NowPlaying_ViewImpl.NowPlayingViewController"]);
    SEL sel = @selector(viewDidLayoutSubviews);
    done = SLHook(cls, sel, ^id(IMP orig) {
        return ^(UIViewController *vc) {
            ((void (*)(id, SEL))orig)(vc, sel);
            UIView *root = vc.viewIfLoaded;
            if (!root.window) return;
            SLGapStripController *c = objc_getAssociatedObject(root, SLGapKey);
            if (!c) {
                c = [SLGapStripController new];
                c.root = root;
                objc_setAssociatedObject(root, SLGapKey, c, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
            }
            if (CACurrentMediaTime() - c.lastUpdate > 0.15) [c update];
        };
    });
    SLLog(@"gap strip: NowPlayingViewController %@", done ? @"ok" : @"missing");
}

void SLInstallVirtualCard(void) {
    SLInstallGapStrip();
    static BOOL done;
    if (done) return;
    Class cls = SLFindClass(@[@"_TtC12Element_List18CollectionViewCell", @"Element_List.CollectionViewCell"]);
    if (!cls) { SLLog(@"virtual card: Element_List.CollectionViewCell missing"); return; }
    done = YES;

    SEL fit = @selector(preferredLayoutAttributesFittingAttributes:);
    BOOL a = SLHook(cls, fit, ^id(IMP orig) {
        return ^UICollectionViewLayoutAttributes *(UICollectionViewCell *cell, UICollectionViewLayoutAttributes *attrs) {
            UICollectionViewLayoutAttributes *res = ((id (*)(id, SEL, id))orig)(cell, fit, attrs);
            SLCellMode mode = SLCellModeNone;
            if (SLIsNPVCell(cell) && res) {
                NSIndexPath *ip = attrs.indexPath;
                BOOL first = ip.section == 0 && ip.item == 0;
                BOOL lyrics = SLContainsLyricsCard(cell.contentView);
                mode = first ? (lyrics ? SLCellModeReplace : SLCellModePrepend) : (lyrics ? SLCellModeCollapse : SLCellModeNone);
                CGSize size = res.size;
                if (mode == SLCellModePrepend) size.height += SLCardHeight + SLCardGap;
                else if (mode == SLCellModeReplace) size.height = SLCardHeight;
                else if (mode == SLCellModeCollapse) size.height = 0;
                if (mode != SLCellModeNone) {
                    res = [res copy];
                    res.size = size;
                }
            }
            if ([objc_getAssociatedObject(cell, SLModeKey) integerValue] != mode) {
                objc_setAssociatedObject(cell, SLModeKey, @(mode), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
                [cell setNeedsLayout];
            }
            return res;
        };
    });

    SEL layout = @selector(layoutSubviews);
    BOOL b = SLHook(cls, layout, ^id(IMP orig) {
        return ^(UICollectionViewCell *cell) {
            ((void (*)(id, SEL))orig)(cell, layout);
            if (objc_getAssociatedObject(cell, SLModeKey) || objc_getAssociatedObject(cell, SLCardKey)) SLApplyCellMode(cell);
        };
    });

    SEL reuse = @selector(prepareForReuse);
    SLHook(cls, reuse, ^id(IMP orig) {
        return ^(UICollectionViewCell *cell) {
            ((void (*)(id, SEL))orig)(cell, reuse);
            if (!objc_getAssociatedObject(cell, SLModeKey)) return;
            objc_setAssociatedObject(cell, SLModeKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
            SLApplyCellMode(cell);
        };
    });
    SLLog(@"virtual card: fit=%d layout=%d", a, b);
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
    SLHookHost(@"strip.canvas", @[@"_TtC17Canvas_CommonImpl26CanvasNowPlayingLyricsView",
                                  @"Canvas_CommonImpl.CanvasNowPlayingLyricsView"], SLHostKindStrip);
    SLHookHost(@"strip.container", @[@"_TtC22Lyrics_NPVContainerKit19LyricsContainerView",
                                     @"Lyrics_NPVContainerKit.LyricsContainerView"], SLHostKindStrip);
    SLHookHost(@"strip.legacy", @[@"_TtC28NowPlaying_ContentLayersImpl25LegacyLyricsContainerView",
                                  @"NowPlaying_ContentLayersImpl.LegacyLyricsContainerView"], SLHostKindStrip);
    SLHookHost(@"strip.element", @[@"_TtC25Lyrics_NPVElementsKitImpl26LyricsElementContainerView",
                                   @"Lyrics_NPVElementsKitImpl.LyricsElementContainerView"], SLHostKindStrip);
}
