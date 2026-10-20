#import "SLLyricsViewController.h"
#import "SLLocalization.h"
#import "SLLyricsView.h"
#import "SLNowPlaying.h"
#import "SLSettingsViewController.h"
#import "SLRemote.h"

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

/// Полноэкранный экран текста, открывается тапом по тексту на плеере.
@implementation SLLyricsViewController {
    SLLyricsView *_lyricsView;
    UIView *_header;
    UIImageView *_cover;
    UILabel *_titleLabel, *_artistLabel;
    UIButton *_closeButton, *_settingsButton;
}

+ (BOOL)isPresented { return SLCurrent != nil; }

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
- (UIInterfaceOrientationMask)supportedInterfaceOrientations { return UIInterfaceOrientationMaskAll; }

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

    _titleLabel = [UILabel new];
    _titleLabel.font = [UIFont systemFontOfSize:17 weight:UIFontWeightBold];
    _titleLabel.textColor = UIColor.whiteColor;
    [_header addSubview:_titleLabel];
    _artistLabel = [UILabel new];
    _artistLabel.font = [UIFont systemFontOfSize:15 weight:UIFontWeightMedium];
    _artistLabel.textColor = [UIColor colorWithWhite:1 alpha:0.65];
    [_header addSubview:_artistLabel];

    UIImageSymbolConfiguration *cfg = [UIImageSymbolConfiguration configurationWithPointSize:15 weight:UIImageSymbolWeightBold];
    _closeButton = [self roundButton:[UIImage systemImageNamed:@"chevron.down" withConfiguration:cfg] action:@selector(close)];
    _settingsButton = [self roundButton:[UIImage systemImageNamed:@"slider.horizontal.3" withConfiguration:cfg] action:@selector(openSettings)];
    [_header addSubview:_closeButton];
    [_header addSubview:_settingsButton];

    UISwipeGestureRecognizer *down = [[UISwipeGestureRecognizer alloc] initWithTarget:self action:@selector(close)];
    down.direction = UISwipeGestureRecognizerDirectionDown;
    [_header addGestureRecognizer:down];

    NSNotificationCenter *nc = [NSNotificationCenter defaultCenter];
    [nc addObserver:self selector:@selector(updateHeader) name:SLTrackDidChangeNotification object:nil];
    [nc addObserver:self selector:@selector(updateHeader) name:SLArtworkDidChangeNotification object:nil];
    [self updateHeader];
}

- (void)dealloc { [[NSNotificationCenter defaultCenter] removeObserver:self]; }

- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    CGRect b = self.view.bounds;
    UIEdgeInsets safe = self.view.safeAreaInsets;
    CGFloat side = 20 + MAX(safe.left, safe.right);
    _header.frame = CGRectMake(0, safe.top + 4, b.size.width, 64);
    _cover.frame = CGRectMake(side, 8, 48, 48);
    _closeButton.frame = CGRectMake(b.size.width - side - 36, 14, 36, 36);
    _settingsButton.frame = CGRectMake(CGRectGetMinX(_closeButton.frame) - 44, 14, 36, 36);
    CGFloat textX = CGRectGetMaxX(_cover.frame) + 12;
    CGFloat textW = CGRectGetMinX(_settingsButton.frame) - 8 - textX;
    _titleLabel.frame = CGRectMake(textX, 11, textW, 22);
    _artistLabel.frame = CGRectMake(textX, 33, textW, 19);

    CGFloat top = CGRectGetMaxY(_header.frame);
    _lyricsView.frame = b;
    _lyricsView.contentInsets = UIEdgeInsetsMake(top, side + 4, 0, side + 4);
    // текст ниже шапки: двигаем скролл, фон оставляем на весь экран
    [_lyricsView setNeedsLayout];
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
}

- (void)close { [self dismissViewControllerAnimated:YES completion:nil]; }
- (void)togglePlay { [SLRemote togglePlayPause]; }
- (void)openSettings { [SLSettingsViewController presentFrom:self]; }

@end
