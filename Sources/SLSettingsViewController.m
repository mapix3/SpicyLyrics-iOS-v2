#import "SLSettingsViewController.h"
#import "SLLocalization.h"
#import "SLSettings.h"
#import "SLLyricsProvider.h"
#import "SLDebug.h"

extern UIWindow *SLKeyWindow(void);

@implementation SLSettingsViewController {
    UILabel *_offsetLabel;
}

+ (void)presentFrom:(UIViewController *)presenter {
    UIViewController *top = presenter ?: SLKeyWindow().rootViewController;
    while (top.presentedViewController && !top.presentedViewController.isBeingDismissed) top = top.presentedViewController;
    if (!top || [top isKindOfClass:self]) return;
    SLSettingsViewController *vc = [self new];
    vc.modalPresentationStyle = UIModalPresentationPageSheet;
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wunguarded-availability-new"
    if ([vc respondsToSelector:@selector(sheetPresentationController)]) {
        UISheetPresentationController *sheet = vc.sheetPresentationController;
        sheet.detents = @[UISheetPresentationControllerDetent.mediumDetent, UISheetPresentationControllerDetent.largeDetent];
        sheet.prefersGrabberVisible = YES;
        sheet.prefersEdgeAttachedInCompactHeight = YES;
        sheet.widthFollowsPreferredContentSizeWhenEdgeAttached = YES;
        sheet.prefersScrollingExpandsWhenScrolledToEdge = NO;
    }
    vc.preferredContentSize = CGSizeMake(440, 0);
#pragma clang diagnostic pop
    [top presentViewController:vc animated:YES completion:nil];
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.overrideUserInterfaceStyle = UIUserInterfaceStyleDark;
    self.view.backgroundColor = [UIColor colorWithWhite:0.09 alpha:1];
    SLSettings *s = [SLSettings shared];

    UIScrollView *scroll = [UIScrollView new];
    scroll.translatesAutoresizingMaskIntoConstraints = NO;
    scroll.alwaysBounceVertical = YES;
    [self.view addSubview:scroll];

    UIStackView *stack = [UIStackView new];
    stack.axis = UILayoutConstraintAxisVertical;
    stack.spacing = 16;
    stack.translatesAutoresizingMaskIntoConstraints = NO;
    [scroll addSubview:stack];
    [NSLayoutConstraint activateConstraints:@[
        [scroll.topAnchor constraintEqualToAnchor:self.view.topAnchor],
        [scroll.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor],
        [scroll.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [scroll.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [stack.topAnchor constraintEqualToAnchor:scroll.contentLayoutGuide.topAnchor constant:28],
        [stack.bottomAnchor constraintEqualToAnchor:scroll.contentLayoutGuide.bottomAnchor constant:-28],
        [stack.centerXAnchor constraintEqualToAnchor:scroll.frameLayoutGuide.centerXAnchor],
        [stack.widthAnchor constraintLessThanOrEqualToConstant:480],
        [stack.leadingAnchor constraintGreaterThanOrEqualToAnchor:scroll.safeAreaLayoutGuide.leadingAnchor constant:22],
        [stack.trailingAnchor constraintLessThanOrEqualToAnchor:scroll.safeAreaLayoutGuide.trailingAnchor constant:-22],
    ]];
    NSLayoutConstraint *fill = [stack.widthAnchor constraintEqualToAnchor:scroll.frameLayoutGuide.widthAnchor constant:-44];
    fill.priority = UILayoutPriorityDefaultHigh;
    fill.active = YES;

    UIStackView *head = [UIStackView new];
    head.axis = UILayoutConstraintAxisHorizontal;
    head.alignment = UIStackViewAlignmentCenter;
    UILabel *title = [UILabel new];
    title.text = @"Spicy Lyrics";
    title.font = [UIFont systemFontOfSize:26 weight:UIFontWeightHeavy];
    title.textColor = UIColor.whiteColor;
    UIButton *close = [UIButton buttonWithType:UIButtonTypeSystem];
    UIImageSymbolConfiguration *cfg = [UIImageSymbolConfiguration configurationWithPointSize:14 weight:UIImageSymbolWeightBold];
    [close setImage:[UIImage systemImageNamed:@"xmark" withConfiguration:cfg] forState:UIControlStateNormal];
    close.tintColor = UIColor.whiteColor;
    close.backgroundColor = [UIColor colorWithWhite:1 alpha:0.12];
    close.layer.cornerRadius = 16;
    [close.widthAnchor constraintEqualToConstant:32].active = YES;
    [close.heightAnchor constraintEqualToConstant:32].active = YES;
    [close addTarget:self action:@selector(closeTapped) forControlEvents:UIControlEventTouchUpInside];
    [head addArrangedSubview:title];
    [head addArrangedSubview:close];
    [stack addArrangedSubview:head];

    [stack addArrangedSubview:[self caption:SLLoc(@"size")]];
    UISlider *size = [UISlider new];
    size.minimumValue = 0.7; size.maximumValue = 1.6; size.value = s.fontScale;
    size.minimumValueImage = [UIImage systemImageNamed:@"textformat.size.smaller"];
    size.maximumValueImage = [UIImage systemImageNamed:@"textformat.size.larger"];
    size.tintColor = UIColor.whiteColor;
    [size addTarget:self action:@selector(sizeChanged:) forControlEvents:UIControlEventTouchUpInside | UIControlEventTouchUpOutside];
    [stack addArrangedSubview:size];

    UIStackView *offRow = [UIStackView new];
    offRow.axis = UILayoutConstraintAxisHorizontal;
    _offsetLabel = [UILabel new];
    _offsetLabel.textColor = UIColor.whiteColor;
    _offsetLabel.font = [UIFont monospacedDigitSystemFontOfSize:16 weight:UIFontWeightMedium];
    _offsetLabel.text = SLLocFormat(@"offset", (long)s.syncOffsetMs);
    UIStepper *step = [UIStepper new];
    step.minimumValue = -3000; step.maximumValue = 3000; step.stepValue = 50; step.value = s.syncOffsetMs;
    [step addTarget:self action:@selector(offsetChanged:) forControlEvents:UIControlEventValueChanged];
    [offRow addArrangedSubview:_offsetLabel];
    [offRow addArrangedSubview:step];
    [stack addArrangedSubview:offRow];

    [stack addArrangedSubview:[self switchRow:SLLoc(@"bg_vocals") on:s.showBackgroundVocals action:@selector(bgVocalsChanged:)]];
    [stack addArrangedSubview:[self switchRow:SLLoc(@"glow") on:s.wordGlow action:@selector(glowChanged:)]];
    [stack addArrangedSubview:[self switchRow:SLLoc(@"anim_bg") on:s.dynamicBackground action:@selector(bgChanged:)]];

    UIButton *reload = [UIButton buttonWithType:UIButtonTypeSystem];
    [reload setTitle:SLLoc(@"reload") forState:UIControlStateNormal];
    reload.titleLabel.font = [UIFont systemFontOfSize:17 weight:UIFontWeightSemibold];
    reload.tintColor = UIColor.whiteColor;
    reload.backgroundColor = [UIColor colorWithWhite:1 alpha:0.12];
    reload.layer.cornerRadius = 12;
    [reload.heightAnchor constraintEqualToConstant:46].active = YES;
    [reload addTarget:self action:@selector(reloadTapped) forControlEvents:UIControlEventTouchUpInside];
    [stack addArrangedSubview:reload];

    UIButton *debug = [UIButton buttonWithType:UIButtonTypeSystem];
    [debug setTitle:@"Export debug" forState:UIControlStateNormal];
    debug.titleLabel.font = [UIFont systemFontOfSize:15 weight:UIFontWeightSemibold];
    debug.tintColor = [UIColor colorWithWhite:1 alpha:0.7];
    [debug.heightAnchor constraintEqualToConstant:40].active = YES;
    [debug addTarget:self action:@selector(exportDebug:) forControlEvents:UIControlEventTouchUpInside];
    [stack addArrangedSubview:debug];

    UILabel *hint = [self caption:SLLoc(@"hint")];
    hint.numberOfLines = 0;
    [stack addArrangedSubview:hint];
}

- (UILabel *)caption:(NSString *)text {
    UILabel *l = [UILabel new];
    l.text = text;
    l.textColor = [UIColor colorWithWhite:1 alpha:0.55];
    l.font = [UIFont systemFontOfSize:13 weight:UIFontWeightSemibold];
    return l;
}

- (UIView *)switchRow:(NSString *)title on:(BOOL)on action:(SEL)sel {
    UIStackView *row = [UIStackView new];
    row.axis = UILayoutConstraintAxisHorizontal;
    UILabel *l = [UILabel new];
    l.text = title;
    l.textColor = UIColor.whiteColor;
    l.font = [UIFont systemFontOfSize:16 weight:UIFontWeightMedium];
    UISwitch *sw = [UISwitch new];
    sw.on = on;
    [sw addTarget:self action:sel forControlEvents:UIControlEventValueChanged];
    [row addArrangedSubview:l];
    [row addArrangedSubview:sw];
    return row;
}

- (void)reloadAll {
    [[SLLyricsProvider shared] clearCache];
    if (self.onReload) self.onReload();
    [[NSNotificationCenter defaultCenter] postNotificationName:@"SLForceReloadNotification" object:nil];
}

- (void)sizeChanged:(UISlider *)s { [SLSettings shared].fontScale = s.value; }
- (void)offsetChanged:(UIStepper *)s {
    [SLSettings shared].syncOffsetMs = (NSInteger)s.value;
    _offsetLabel.text = SLLocFormat(@"offset", (long)s.value);
}
- (void)bgVocalsChanged:(UISwitch *)s { [SLSettings shared].showBackgroundVocals = s.on; }
- (void)glowChanged:(UISwitch *)s { [SLSettings shared].wordGlow = s.on; }
- (void)bgChanged:(UISwitch *)s { [SLSettings shared].dynamicBackground = s.on; }
- (void)exportDebug:(UIButton *)sender { SLDebugShare(self, sender); }

- (void)closeTapped { [self dismissViewControllerAnimated:YES completion:nil]; }

- (UIInterfaceOrientationMask)supportedInterfaceOrientations { return UIInterfaceOrientationMaskAllButUpsideDown; }

- (void)reloadTapped {
    [self reloadAll];
    [self dismissViewControllerAnimated:YES completion:nil];
}

@end
