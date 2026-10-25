#import "SLLyricsViewController.h"
#import "SLLocalization.h"
#import "SLLyricsView.h"
#import "SLNowPlaying.h"
#import "SLSettingsViewController.h"
#import "SLRemote.h"
#import "SLHook.h"
#import <objc/runtime.h>
#import <objc/message.h>

static __weak SLLyricsViewController *SLCurrent;

UIWindow *SLKeyWindow(void) {
    for (UIScene *scene in UIApplication.sharedApplication.connectedScenes) {
        if (![scene isKindOfClass:[UIWindowScene class]]) continue;
        if (scene.activationState != UISceneActivationStateForegroundActive && scene.activationState != UISceneActivationStateForegroundInactive) continue;
        for (UIWindow *w in ((UIWindowScene *)scene).windows) if (w.isKeyWindow) return w;
    }
    for (UIScene *scene in UIApplication.sharedApplication.connectedScenes) {
        if ([scene isKindOfClass:[UIWindowScene class]]) {
            UIWindow *w = ((UIWindowScene *)scene).windows.firstObject;
            if (w) return w;
        }
    }
    return nil;
}

static void SLRefreshOrientations(UIViewController *vc) {
    SEL sel = NSSelectorFromString(@"setNeedsUpdateOfSupportedInterfaceOrientations");
    if ([vc respondsToSelector:sel]) ((void (*)(id, SEL))objc_msgSend)(vc, sel);
}

static NSString *SLTime(double t) {
    if (!(t >= 0) || isinf(t)) t = 0;
    NSInteger v = (NSInteger)floor(t);
    return [NSString stringWithFormat:@"%ld:%02ld", (long)(v / 60), (long)(v % 60)];
}

@implementation SLLyricsViewController {
    SLLyricsView *_lyricsView;
    UIView *_header;
    UIImageView *_cover;
    UILabel *_titleLabel, *_artistLabel;
    UIButton *_closeButton, *_settingsButton;

    UIView *_panel;
    UIImageView *_bigCover;
    UILabel *_bigTitle, *_bigArtist, *_elapsedLabel, *_remainingLabel;
    UIView *_track, *_fill;
    UIButton *_prevButton, *_playButton, *_nextButton;
    NSTimer *_progressTimer;
    BOOL _scrubbing;
    double _scrubTime;
}

+ (BOOL)isPresented { return SLCurrent != nil; }

+ (void)installOrientationSupport {
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        SEL sel = @selector(supportedInterfaceOrientationsForWindow:);
        SLHook([UIApplication class], sel, ^id(IMP orig) {
            return ^UIInterfaceOrientationMask(UIApplication *app, UIWindow *window) {
                UIInterfaceOrientationMask mask = ((UIInterfaceOrientationMask (*)(id, SEL, id))orig)(app, sel, window);
                if (SLCurrent && !SLCurrent.isBeingDismissed) mask |= UIInterfaceOrientationMaskAllButUpsideDown;
                return mask;
            };
        });
        Class delegate = NSClassFromString(@"_TtC24MusicApp_ContainerWiring18SpotifyAppDelegate");
        SEL dsel = @selector(application:supportedInterfaceOrientationsForWindow:);
        if (delegate && class_getInstanceMethod(delegate, dsel)) {
            SLHook(delegate, dsel, ^id(IMP orig) {
                return ^UIInterfaceOrientationMask(id me, UIApplication *app, UIWindow *window) {
                    UIInterfaceOrientationMask mask = ((UIInterfaceOrientationMask (*)(id, SEL, id, id))orig)(me, dsel, app, window);
                    if (SLCurrent && !SLCurrent.isBeingDismissed) mask |= UIInterfaceOrientationMaskAllButUpsideDown;
                    return mask;
                };
            });
        }
    });
}

+ (void)presentFromTopController {
    if (SLCurrent) return;
    UIViewController *top = SLKeyWindow().rootViewController;
    while (top.presentedViewController && !top.presentedViewController.isBeingDismissed) top = top.presentedViewController;
    if (!top) return;
    SLLyricsViewController *vc = [SLLyricsViewController new];
    vc.modalPresentationStyle = UIModalPresentationFullScreen;
    [top presentViewController:vc animated:YES completion:nil];
}

- (UIStatusBarStyle)preferredStatusBarStyle { return UIStatusBarStyleLightContent; }
- (UIInterfaceOrientationMask)supportedInterfaceOrientations { return UIInterfaceOrientationMaskAllButUpsideDown; }
- (BOOL)prefersHomeIndicatorAutoHidden { return self.isLandscape; }

- (BOOL)isLandscape {
    CGSize s = self.viewIfLoaded.bounds.size;
    return s.width > s.height;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    SLCurrent = self;
    self.view.backgroundColor = UIColor.blackColor;
    self.overrideUserInterfaceStyle = UIUserInterfaceStyleDark;

    _lyricsView = [[SLLyricsView alloc] initWithMode:SLLyricsViewModeFull];
    _lyricsView.showsBackground = YES;
    [self.view addSubview:_lyricsView];

    _header = [UIView new];
    [self.view addSubview:_header];
    _cover = [UIImageView new];
    _cover.contentMode = UIViewContentModeScaleAspectFill;
    _cover.clipsToBounds = YES;
    _cover.layer.cornerRadius = 8;
    _cover.backgroundColor = [UIColor colorWithWhite:1 alpha:0.1];
    _cover.userInteractionEnabled = YES;
    [_cover addGestureRecognizer:[[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(togglePlay)]];
    [_header addSubview:_cover];

    _titleLabel = [self label:17 weight:UIFontWeightBold alpha:1];
    [_header addSubview:_titleLabel];
    _artistLabel = [self label:15 weight:UIFontWeightMedium alpha:0.65];
    [_header addSubview:_artistLabel];

    UIImageSymbolConfiguration *cfg = [UIImageSymbolConfiguration configurationWithPointSize:15 weight:UIImageSymbolWeightBold];
    _closeButton = [self roundButton:[UIImage systemImageNamed:@"chevron.down" withConfiguration:cfg] action:@selector(close)];
    _settingsButton = [self roundButton:[UIImage systemImageNamed:@"slider.horizontal.3" withConfiguration:cfg] action:@selector(openSettings)];
    [self.view addSubview:_closeButton];
    [self.view addSubview:_settingsButton];

    UISwipeGestureRecognizer *down = [[UISwipeGestureRecognizer alloc] initWithTarget:self action:@selector(close)];
    down.direction = UISwipeGestureRecognizerDirectionDown;
    [_header addGestureRecognizer:down];

    [self buildPanel];

    NSNotificationCenter *nc = [NSNotificationCenter defaultCenter];
    [nc addObserver:self selector:@selector(updateHeader) name:SLTrackDidChangeNotification object:nil];
    [nc addObserver:self selector:@selector(updateHeader) name:SLArtworkDidChangeNotification object:nil];
    [nc addObserver:self selector:@selector(updateProgress) name:SLPlaybackDidChangeNotification object:nil];
    [self updateHeader];
}

- (UILabel *)label:(CGFloat)size weight:(UIFontWeight)weight alpha:(CGFloat)alpha {
    UILabel *l = [UILabel new];
    l.font = [UIFont systemFontOfSize:size weight:weight];
    l.textColor = [UIColor colorWithWhite:1 alpha:alpha];
    return l;
}

- (void)buildPanel {
    _panel = [UIView new];
    _panel.hidden = YES;
    [self.view addSubview:_panel];

    _bigCover = [UIImageView new];
    _bigCover.contentMode = UIViewContentModeScaleAspectFill;
    _bigCover.clipsToBounds = YES;
    _bigCover.layer.cornerRadius = 10;
    _bigCover.layer.cornerCurve = kCACornerCurveContinuous;
    _bigCover.backgroundColor = [UIColor colorWithWhite:1 alpha:0.1];
    [_panel addSubview:_bigCover];

    _bigTitle = [self label:17 weight:UIFontWeightBold alpha:1];
    _bigArtist = [self label:15 weight:UIFontWeightMedium alpha:0.65];
    [_panel addSubview:_bigTitle];
    [_panel addSubview:_bigArtist];

    _track = [UIView new];
    _track.backgroundColor = [UIColor colorWithWhite:1 alpha:0.22];
    _track.layer.cornerRadius = 2;
    _fill = [UIView new];
    _fill.backgroundColor = [UIColor colorWithWhite:1 alpha:0.9];
    _fill.layer.cornerRadius = 2;
    [_track addSubview:_fill];
    [_panel addSubview:_track];
    UIView *scrubArea = [UIView new];
    scrubArea.tag = 7;
    [scrubArea addGestureRecognizer:[[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(scrub:)]];
    [scrubArea addGestureRecognizer:[[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(scrub:)]];
    [_panel addSubview:scrubArea];

    _elapsedLabel = [self label:12 weight:UIFontWeightMedium alpha:0.6];
    _remainingLabel = [self label:12 weight:UIFontWeightMedium alpha:0.6];
    _elapsedLabel.font = [UIFont monospacedDigitSystemFontOfSize:12 weight:UIFontWeightMedium];
    _remainingLabel.font = [UIFont monospacedDigitSystemFontOfSize:12 weight:UIFontWeightMedium];
    _remainingLabel.textAlignment = NSTextAlignmentRight;
    [_panel addSubview:_elapsedLabel];
    [_panel addSubview:_remainingLabel];

    _prevButton = [self controlButton:@"backward.fill" size:24 action:@selector(previous)];
    _playButton = [self controlButton:@"pause.fill" size:34 action:@selector(togglePlay)];
    _nextButton = [self controlButton:@"forward.fill" size:24 action:@selector(next)];
}

- (UIButton *)controlButton:(NSString *)symbol size:(CGFloat)size action:(SEL)sel {
    UIButton *b = [UIButton buttonWithType:UIButtonTypeSystem];
    [b setImage:[UIImage systemImageNamed:symbol withConfiguration:[UIImageSymbolConfiguration configurationWithPointSize:size weight:UIImageSymbolWeightBold]]
       forState:UIControlStateNormal];
    b.tintColor = UIColor.whiteColor;
    [b addTarget:self action:sel forControlEvents:UIControlEventTouchUpInside];
    [_panel addSubview:b];
    return b;
}

- (void)viewDidAppear:(BOOL)animated {
    [super viewDidAppear:animated];
    SLRefreshOrientations(self);
    __weak typeof(self) weakSelf = self;
    [_progressTimer invalidate];
    _progressTimer = [NSTimer scheduledTimerWithTimeInterval:0.25 repeats:YES block:^(NSTimer *t) { [weakSelf updateProgress]; }];
    [self updateProgress];
}

- (void)viewDidDisappear:(BOOL)animated {
    [super viewDidDisappear:animated];
    [_progressTimer invalidate];
    _progressTimer = nil;
}

- (void)dealloc {
    [_progressTimer invalidate];
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    CGRect b = self.view.bounds;
    UIEdgeInsets safe = self.view.safeAreaInsets;
    BOOL land = self.isLandscape;
    _header.hidden = land;
    _panel.hidden = !land;
    _lyricsView.frame = b;

    if (!land) {
        CGFloat side = 20 + MAX(safe.left, safe.right);
        _header.frame = CGRectMake(0, safe.top + 4, b.size.width, 64);
        _cover.frame = CGRectMake(side, 8, 48, 48);
        _closeButton.frame = CGRectMake(b.size.width - side - 36, safe.top + 18, 36, 36);
        _settingsButton.frame = CGRectMake(CGRectGetMinX(_closeButton.frame) - 44, safe.top + 18, 36, 36);
        CGFloat textX = CGRectGetMaxX(_cover.frame) + 12;
        CGFloat textW = CGRectGetMinX(_settingsButton.frame) - 8 - textX;
        _titleLabel.frame = CGRectMake(textX, 11, textW, 22);
        _artistLabel.frame = CGRectMake(textX, 33, textW, 19);
        _lyricsView.contentInsets = UIEdgeInsetsMake(CGRectGetMaxY(_header.frame), side + 4, 0, side + 4);
    } else {
        CGFloat left = MAX(safe.left, 16) + 24;
        CGFloat right = MAX(safe.right, 16) + 16;
        CGFloat top = MAX(safe.top, 12) + 12;
        CGFloat bottom = MAX(safe.bottom, 12) + 8;
        CGFloat availH = b.size.height - top - bottom;
        CGFloat controlsH = 138;
        CGFloat coverSide = floor(MIN(b.size.width * 0.34, availH - controlsH));
        coverSide = MAX(coverSide, 80);
        CGFloat panelW = MAX(coverSide, 220);
        CGFloat panelH = coverSide + controlsH;
        _panel.frame = CGRectMake(left, top + floor((availH - panelH) / 2), panelW, panelH);
        _bigCover.frame = CGRectMake(floor((panelW - coverSide) / 2), 0, coverSide, coverSide);
        CGFloat y = coverSide + 14;
        _bigTitle.frame = CGRectMake(0, y, panelW, 21);
        _bigArtist.frame = CGRectMake(0, y + 22, panelW, 19);
        y += 54;
        _track.frame = CGRectMake(0, y, panelW, 4);
        [_panel viewWithTag:7].frame = CGRectMake(0, y - 14, panelW, 32);
        _elapsedLabel.frame = CGRectMake(0, y + 9, panelW / 2, 15);
        _remainingLabel.frame = CGRectMake(panelW / 2, y + 9, panelW / 2, 15);
        CGFloat cy = y + 50;
        _playButton.frame = CGRectMake(panelW / 2 - 28, cy - 28, 56, 56);
        _prevButton.frame = CGRectMake(panelW / 2 - 28 - 70, cy - 22, 44, 44);
        _nextButton.frame = CGRectMake(panelW / 2 + 28 + 26, cy - 22, 44, 44);
        _closeButton.frame = CGRectMake(b.size.width - right - 36, top, 36, 36);
        _settingsButton.frame = CGRectMake(CGRectGetMinX(_closeButton.frame) - 44, top, 36, 36);
        CGFloat lyricsX = CGRectGetMaxX(_panel.frame) + 36;
        _lyricsView.contentInsets = UIEdgeInsetsMake(top, lyricsX, 0, right + 8);
        [self updateProgress];
    }
    [_lyricsView setNeedsLayout];
}

- (void)viewWillTransitionToSize:(CGSize)size withTransitionCoordinator:(id<UIViewControllerTransitionCoordinator>)coordinator {
    [super viewWillTransitionToSize:size withTransitionCoordinator:coordinator];
    [coordinator animateAlongsideTransition:nil completion:^(id<UIViewControllerTransitionCoordinatorContext> ctx) {
        [self setNeedsUpdateOfHomeIndicatorAutoHidden];
    }];
}

- (UIButton *)roundButton:(UIImage *)img action:(SEL)sel {
    UIButton *b = [UIButton buttonWithType:UIButtonTypeSystem];
    [b setImage:img forState:UIControlStateNormal];
    b.tintColor = UIColor.whiteColor;
    b.backgroundColor = [UIColor colorWithWhite:1 alpha:0.14];
    b.layer.cornerRadius = 18;
    [b addTarget:self action:sel forControlEvents:UIControlEventTouchUpInside];
    return b;
}

- (void)updateHeader {
    SLNowPlaying *np = [SLNowPlaying shared];
    _titleLabel.text = np.title ?: SLLoc(@"nothing_playing");
    _artistLabel.text = np.artist ?: @"";
    _cover.image = np.artwork;
    _bigTitle.text = _titleLabel.text;
    _bigArtist.text = _artistLabel.text;
    _bigCover.image = np.artwork;
    [self updateProgress];
}

- (void)updateProgress {
    if (_panel.hidden) return;
    SLNowPlaying *np = [SLNowPlaying shared];
    double d = MAX(np.duration, 0);
    double t = _scrubbing ? _scrubTime : MIN(np.currentTime, d > 0 ? d : np.currentTime);
    CGFloat w = _track.bounds.size.width;
    _fill.frame = CGRectMake(0, 0, d > 0 ? round(w * MIN(1, MAX(0, t / d))) : 0, _track.bounds.size.height);
    _elapsedLabel.text = SLTime(t);
    _remainingLabel.text = d > 0 ? [@"-" stringByAppendingString:SLTime(d - t)] : @"";
    NSString *symbol = np.isPlaying ? @"pause.fill" : @"play.fill";
    if (![objc_getAssociatedObject(_playButton, @selector(updateProgress)) isEqual:symbol]) {
        objc_setAssociatedObject(_playButton, @selector(updateProgress), symbol, OBJC_ASSOCIATION_COPY_NONATOMIC);
        [_playButton setImage:[UIImage systemImageNamed:symbol withConfiguration:[UIImageSymbolConfiguration configurationWithPointSize:34 weight:UIImageSymbolWeightBold]]
                     forState:UIControlStateNormal];
    }
}

- (void)scrub:(UIGestureRecognizer *)g {
    double d = [SLNowPlaying shared].duration;
    if (d <= 0) return;
    CGFloat x = [g locationInView:_track].x;
    _scrubTime = d * MIN(1, MAX(0, x / MAX(1, _track.bounds.size.width)));
    if ([g isKindOfClass:[UITapGestureRecognizer class]] || g.state == UIGestureRecognizerStateEnded) {
        _scrubbing = NO;
        [SLRemote seekTo:_scrubTime];
    } else if (g.state == UIGestureRecognizerStateCancelled || g.state == UIGestureRecognizerStateFailed) {
        _scrubbing = NO;
    } else {
        _scrubbing = YES;
    }
    [self updateProgress];
}

- (void)close {
    [self dismissViewControllerAnimated:YES completion:^{
        SLRefreshOrientations(SLKeyWindow().rootViewController);
    }];
}

- (void)togglePlay { [SLRemote togglePlayPause]; dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.3 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{ [self updateProgress]; }); }
- (void)next { [SLRemote nextTrack]; }
- (void)previous { [SLRemote previousTrack]; }
- (void)openSettings { [SLSettingsViewController presentFrom:self]; }

@end
