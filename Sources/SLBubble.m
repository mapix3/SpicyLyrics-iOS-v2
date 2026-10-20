#import "SLBubble.h"
#import "SLLyricsViewController.h"
#import "SLNowPlaying.h"
#import "SLSettings.h"

extern UIWindow *SLKeyWindow(void);

static const CGFloat SLBubbleSize = 50;

@implementation SLBubble {
    NSTimer *_timer;
    CGPoint _dragStart;
}

+ (instancetype)shared {
    static SLBubble *b;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ b = [[SLBubble alloc] initWithFrame:CGRectMake(0, 0, SLBubbleSize, SLBubbleSize)]; });
    return b;
}

+ (void)install {
    SLBubble *b = [self shared];
    if (!b->_timer) {
        b->_timer = [NSTimer scheduledTimerWithTimeInterval:0.8 target:b selector:@selector(refresh) userInfo:nil repeats:YES];
        NSNotificationCenter *nc = [NSNotificationCenter defaultCenter];
        [nc addObserver:b selector:@selector(refresh) name:UIWindowDidBecomeKeyNotification object:nil];
        [nc addObserver:b selector:@selector(refresh) name:SLTrackDidChangeNotification object:nil];
        [nc addObserver:b selector:@selector(refresh) name:SLSettingsDidChangeNotification object:nil];
    }
    [b refresh];
}

- (instancetype)initWithFrame:(CGRect)frame {
    if ((self = [super initWithFrame:frame])) {
        self.layer.cornerRadius = SLBubbleSize / 2;
        self.layer.shadowColor = UIColor.blackColor.CGColor;
        self.layer.shadowOpacity = 0.35;
        self.layer.shadowRadius = 10;
        self.layer.shadowOffset = CGSizeMake(0, 4);

        UIVisualEffectView *blur = [[UIVisualEffectView alloc] initWithEffect:[UIBlurEffect effectWithStyle:UIBlurEffectStyleSystemChromeMaterialDark]];
        blur.frame = self.bounds;
        blur.layer.cornerRadius = SLBubbleSize / 2;
        blur.clipsToBounds = YES;
        blur.userInteractionEnabled = NO;
        [self addSubview:blur];

        UIImageView *icon = [[UIImageView alloc] initWithFrame:CGRectInset(self.bounds, 13, 13)];
        icon.image = [UIImage systemImageNamed:@"quote.bubble.fill"
                             withConfiguration:[UIImageSymbolConfiguration configurationWithPointSize:20 weight:UIImageSymbolWeightBold]];
        icon.contentMode = UIViewContentModeScaleAspectFit;
        icon.tintColor = [UIColor colorWithRed:0.12 green:0.84 blue:0.38 alpha:1];
        [self addSubview:icon];

        [self addGestureRecognizer:[[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(tap)]];
        [self addGestureRecognizer:[[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(pan:)]];
        self.alpha = 0;
        self.hidden = YES;
    }
    return self;
}

- (void)refresh {
    UIWindow *w = SLKeyWindow();
    BOOL want = w && [SLSettings shared].showBubble && [SLNowPlaying shared].title.length && ![SLLyricsViewController isPresented];
    if (want) {
        if (self.superview != w) {
            [self removeFromSuperview];
            [w addSubview:self];
            self.center = [self restingCenterIn:w preferred:[SLSettings shared].bubbleCenter];
        } else if (w.subviews.lastObject != self) {
            [w bringSubviewToFront:self];
        }
    }
    if (want == !self.hidden && (want ? self.alpha == 1 : YES)) return;
    if (want) self.hidden = NO;
    [UIView animateWithDuration:0.25 animations:^{ self.alpha = want ? 1 : 0; } completion:^(BOOL d) {
        if (!want) self.hidden = YES;
    }];
}

- (CGPoint)restingCenterIn:(UIView *)host preferred:(CGPoint)p {
    CGRect b = host.bounds;
    UIEdgeInsets safe = host.safeAreaInsets;
    CGFloat r = SLBubbleSize / 2 + 10;
    if (CGPointEqualToPoint(p, CGPointZero)) p = CGPointMake(b.size.width - r, b.size.height * 0.62);
    CGFloat x = p.x < b.size.width / 2 ? r + safe.left : b.size.width - r - safe.right;
    CGFloat y = MIN(MAX(p.y, safe.top + r + 40), b.size.height - safe.bottom - r - 90);
    return CGPointMake(x, y);
}

- (void)tap {
    [UIView animateWithDuration:0.12 animations:^{ self.transform = CGAffineTransformMakeScale(0.88, 0.88); } completion:^(BOOL d) {
        [UIView animateWithDuration:0.18 animations:^{ self.transform = CGAffineTransformIdentity; }];
    }];
    [SLLyricsViewController presentFromTopController];
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.4 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{ [self refresh]; });
}

- (void)pan:(UIPanGestureRecognizer *)g {
    UIView *host = self.superview;
    if (!host) return;
    if (g.state == UIGestureRecognizerStateBegan) _dragStart = self.center;
    CGPoint tr = [g translationInView:host];
    self.center = CGPointMake(_dragStart.x + tr.x, _dragStart.y + tr.y);
    if (g.state == UIGestureRecognizerStateEnded || g.state == UIGestureRecognizerStateCancelled) {
        CGPoint rest = [self restingCenterIn:host preferred:self.center];
        [SLSettings shared].bubbleCenter = rest;
        [UIView animateWithDuration:0.45 delay:0 usingSpringWithDamping:0.75 initialSpringVelocity:0.5 options:0 animations:^{
            self.center = rest;
        } completion:nil];
    }
}

@end
