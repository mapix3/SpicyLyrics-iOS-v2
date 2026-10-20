#import "SLLyricsView.h"
#import "SLLocalization.h"
#import "SLBackgroundView.h"
#import "SLLineView.h"
#import "SLNowPlaying.h"
#import "SLLyricsProvider.h"
#import "SLSettings.h"
#import "SLRemote.h"
#import "SLSettingsViewController.h"

@interface SLWeakTickProxy : NSObject
@property (nonatomic, weak) id target;
@end

@interface SLLyricsView () <UIScrollViewDelegate>
- (void)tick;
@end

@implementation SLLyricsView {
    SLBackgroundView *_bg;
    UIView *_scrollHost;
    UIScrollView *_scroll;
    UILabel *_statusLabel, *_sourceLabel;
    UITextView *_attribution;      // подпись источника, всегда видна вместе с текстом
    UIButton *_resyncButton;
    UIActivityIndicatorView *_spinner;

    SLLyrics *_lyrics;
    NSArray<SLLineView *> *_lineViews;
    NSInteger _primary;
    NSIndexSet *_activeSet;
    CGFloat _builtWidth, _builtHeight;
    BOOL _builtTall;
    CADisplayLink *_link;
    NSString *_loadingKey;

    BOOL _userScrolling;
    CFTimeInterval _userScrollEnd;
}

- (instancetype)initWithMode:(SLLyricsViewMode)mode {
    if ((self = [super initWithFrame:CGRectZero])) {
        _mode = mode;
        _primary = NSIntegerMin;
        _activeSet = [NSIndexSet indexSet];
        _interactive = mode == SLLyricsViewModeFull;
        _showsAttribution = YES;
        _contentInsets = mode == SLLyricsViewModeFull ? UIEdgeInsetsMake(0, 24, 0, 24)
                       : mode == SLLyricsViewModeCompact ? UIEdgeInsetsMake(0, 16, 0, 16) : UIEdgeInsetsZero;
        self.clipsToBounds = YES;
        self.backgroundColor = UIColor.clearColor;
        self.overrideUserInterfaceStyle = UIUserInterfaceStyleDark;

        _bg = [SLBackgroundView new];
        _bg.hidden = YES;
        [self addSubview:_bg];

        _scrollHost = [UIView new];
        [self addSubview:_scrollHost];
        _scroll = [UIScrollView new];
        _scroll.delegate = self;
        _scroll.showsVerticalScrollIndicator = NO;
        _scroll.alwaysBounceVertical = YES;
        _scroll.contentInsetAdjustmentBehavior = UIScrollViewContentInsetAdjustmentNever;
        _scroll.scrollsToTop = NO;
        [_scrollHost addSubview:_scroll];

        CAGradientLayer *fade = [CAGradientLayer layer];
        fade.colors = @[(id)UIColor.clearColor.CGColor, (id)UIColor.blackColor.CGColor,
                        (id)UIColor.blackColor.CGColor, (id)UIColor.clearColor.CGColor];
        fade.locations = mode == SLLyricsViewModeFull ? @[@0, @0.08, @0.86, @1]
                       : mode == SLLyricsViewModeCompact ? @[@0, @0.12, @0.82, @1] : @[@0, @0.03, @0.7, @1];
        _scrollHost.layer.mask = fade;

        _statusLabel = [UILabel new];
        _statusLabel.textColor = [UIColor colorWithWhite:1 alpha:0.75];
        _statusLabel.font = [UIFont systemFontOfSize:mode == SLLyricsViewModeFull ? 19 : 15 weight:UIFontWeightSemibold];
        _statusLabel.textAlignment = mode == SLLyricsViewModeStrip ? NSTextAlignmentNatural : NSTextAlignmentCenter;
        _statusLabel.numberOfLines = 0;
        _statusLabel.alpha = 0;
        [self addSubview:_statusLabel];

        _spinner = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleMedium];
        _spinner.color = UIColor.whiteColor;
        _spinner.hidesWhenStopped = YES;
        [self addSubview:_spinner];

        _sourceLabel = [UILabel new];
        _sourceLabel.textColor = [UIColor colorWithWhite:1 alpha:0.45];
        _sourceLabel.font = [UIFont systemFontOfSize:12 weight:UIFontWeightMedium];
        _sourceLabel.numberOfLines = 0;

        _attribution = [UITextView new];
        _attribution.editable = NO;
        _attribution.scrollEnabled = NO;
        _attribution.backgroundColor = UIColor.clearColor;
        _attribution.textContainerInset = UIEdgeInsetsMake(6, 0, 6, 0);
        _attribution.textContainer.lineFragmentPadding = 0;
        _attribution.linkTextAttributes = @{ NSForegroundColorAttributeName: [UIColor colorWithWhite:1 alpha:0.85],
                                            NSUnderlineStyleAttributeName: @(NSUnderlineStyleSingle) };
        _attribution.hidden = YES;
        [self addSubview:_attribution];

        _resyncButton = [UIButton buttonWithType:UIButtonTypeSystem];
        [_resyncButton setTitle:[NSString stringWithFormat:@"  %@  ", SLLoc(@"resync")] forState:UIControlStateNormal];
        [_resyncButton setTitleColor:UIColor.blackColor forState:UIControlStateNormal];
        _resyncButton.titleLabel.font = [UIFont systemFontOfSize:14 weight:UIFontWeightSemibold];
        _resyncButton.backgroundColor = [UIColor colorWithWhite:1 alpha:0.92];
        _resyncButton.layer.cornerRadius = 17;
        _resyncButton.alpha = 0;
        [_resyncButton addTarget:self action:@selector(resync) forControlEvents:UIControlEventTouchUpInside];
        [self addSubview:_resyncButton];

        NSNotificationCenter *nc = [NSNotificationCenter defaultCenter];
        [nc addObserver:self selector:@selector(trackChanged) name:SLTrackDidChangeNotification object:nil];
        [nc addObserver:self selector:@selector(artworkChanged) name:SLArtworkDidChangeNotification object:nil];
        [nc addObserver:self selector:@selector(settingsChanged:) name:SLSettingsDidChangeNotification object:nil];
        [nc addObserver:self selector:@selector(playbackChanged) name:SLPlaybackDidChangeNotification object:nil];
        [nc addObserver:self selector:@selector(forceReload) name:@"SLForceReloadNotification" object:nil];
        UILongPressGestureRecognizer *lp = [[UILongPressGestureRecognizer alloc] initWithTarget:self action:@selector(longPress:)];
        lp.minimumPressDuration = 0.6;
        [self addGestureRecognizer:lp];
        self.interactive = _interactive;
    }
    return self;
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    [_link invalidate];
}

#pragma mark - Window / display link

- (void)didMoveToWindow {
    [super didMoveToWindow];
    if (self.window) {
        if (!_link) {
            _link = [CADisplayLink displayLinkWithTarget:[self weakProxy] selector:@selector(tick)];
            if ([_link respondsToSelector:@selector(setPreferredFrameRateRange:)]) {
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wunguarded-availability-new"
                CAFrameRateRange r = { .minimum = 30, .maximum = 120, .preferred = 120 };
                _link.preferredFrameRateRange = r;
#pragma clang diagnostic pop
            }
            [_link addToRunLoop:[NSRunLoop mainRunLoop] forMode:NSRunLoopCommonModes];
        }
        [[SLNowPlaying shared] refreshFromCenter];
        [self artworkChanged];
        [self loadLyrics];
    } else {
        [_link invalidate];
        _link = nil;
    }
}

/// CADisplayLink держит target сильной ссылкой — разрываем цикл.
- (id)weakProxy {
    SLWeakTickProxy *p = [SLWeakTickProxy new];
    p.target = self;
    return p;
}

#pragma mark - Layout

- (void)layoutSubviews {
    [super layoutSubviews];
    CGRect b = self.bounds;
    _bg.frame = b;
    CGFloat safeBottom = self.safeAreaInsets.bottom;
    CGFloat attrH = 0;
    if (!_attribution.hidden) {
        CGFloat w = [self textWidth];
        attrH = ceil([_attribution sizeThatFits:CGSizeMake(w, CGFLOAT_MAX)].height);
        _attribution.frame = CGRectMake(_contentInsets.left, b.size.height - safeBottom - attrH - 4, w, attrH);
        attrH += 4;
    }
    _scrollHost.frame = CGRectMake(0, _contentInsets.top, b.size.width,
                                   MAX(0, b.size.height - _contentInsets.top - _contentInsets.bottom - (attrH ? attrH + safeBottom : 0)));
    _scroll.frame = _scrollHost.bounds;
    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    _scrollHost.layer.mask.frame = _scrollHost.bounds;
    [CATransaction commit];
    _statusLabel.frame = _mode == SLLyricsViewModeStrip
        ? CGRectMake(_contentInsets.left, _scrollHost.frame.origin.y, [self textWidth], _scrollHost.frame.size.height)
        : CGRectInset(_scrollHost.frame, _mode == SLLyricsViewModeFull ? 24 : 12, 0);
    _spinner.center = CGPointMake(CGRectGetMidX(_scrollHost.frame), CGRectGetMidY(_scrollHost.frame));
    _resyncButton.frame = CGRectMake((b.size.width - 190) / 2, CGRectGetMaxY(_scrollHost.frame) - 46, 190, 34);

    CGFloat width = [self textWidth];
    CGFloat height = _scroll.bounds.size.height;
    if (_lyrics && (fabs(width - _builtWidth) > 0.5 || _scroll.contentSize.height == 0 || [self isTall] != _builtTall)) [self buildLines];
    else if (_lyrics && fabs(height - _builtHeight) > 0.5) { [self updateInsets]; [self scrollToPrimaryAnimated:NO]; }
}

/// Строчка на плеере, растянутая Spotify на большую область (режим «текст вместо обложки»).
- (BOOL)isTall {
    return _mode == SLLyricsViewModeStrip && self.bounds.size.height > 220;
}

- (CGFloat)textWidth {
    return self.bounds.size.width - _contentInsets.left - _contentInsets.right;
}

- (void)setInteractive:(BOOL)interactive {
    _interactive = interactive;
    _scroll.scrollEnabled = interactive;
    self.userInteractionEnabled = interactive;
}

- (void)setShowsBackground:(BOOL)showsBackground {
    _showsBackground = showsBackground;
    _bg.hidden = !showsBackground;
    _bg.animated = [SLSettings shared].dynamicBackground;
}

- (void)setShowsAttribution:(BOOL)showsAttribution {
    _showsAttribution = showsAttribution;
    [self updateAttribution];
}

- (void)artworkChanged {
    if (_showsBackground) [_bg setArtwork:[SLNowPlaying shared].artwork];
}

#pragma mark - Loading

- (void)trackChanged {
    [self loadLyrics];
}

- (void)forceReload {
    _loadingKey = nil;
    if (self.window) [self loadLyrics];
}

- (void)longPress:(UILongPressGestureRecognizer *)g {
    if (g.state != UIGestureRecognizerStateBegan) return;
    UIResponder *r = self;
    while (r && ![r isKindOfClass:[UIViewController class]]) r = r.nextResponder;
    [SLSettingsViewController presentFrom:(UIViewController *)r];
}

- (void)playbackChanged {
    // после перемотки — сразу к нужной строке
    if (!_userScrolling) _userScrollEnd = 0;
}

- (void)settingsChanged:(NSNotification *)n {
    _bg.animated = [SLSettings shared].dynamicBackground;
    _builtWidth = 0;
    [self setNeedsLayout];
}

- (void)setStatus:(NSString *)s loading:(BOOL)loading {
    _statusLabel.text = s;
    _statusLabel.numberOfLines = _mode == SLLyricsViewModeStrip ? 2 : 0;
    if (loading) [_spinner startAnimating]; else [_spinner stopAnimating];
    [UIView animateWithDuration:0.25 animations:^{ self->_statusLabel.alpha = (s.length && !loading) ? 1 : 0; }];
}

- (void)setLyrics:(SLLyrics *)ly {
    BOOL had = _lyrics != nil;
    _lyrics = ly;
    _builtWidth = 0;
    [self updateAttribution];
    [self layoutIfNeeded];
    [self buildLines];
    if (had != (ly != nil) && self.availabilityChanged) self.availabilityChanged(ly != nil);
}

- (BOOL)hasLyrics { return _lyrics != nil; }

/// «Текст: Spicy Lyrics · загрузил X · синхронизировал Y» со ссылками на профили.
- (void)updateAttribution {
    if (!_lyrics || !_showsAttribution) { _attribution.hidden = YES; [self setNeedsLayout]; return; }
    UIFont *font = [UIFont systemFontOfSize:12 weight:UIFontWeightSemibold];
    NSDictionary *plain = @{ NSFontAttributeName: font, NSForegroundColorAttributeName: [UIColor colorWithWhite:1 alpha:0.55] };
    NSMutableAttributedString *a = [[NSMutableAttributedString alloc] initWithString:SLLocFormat(@"lyrics_from", _lyrics.source ?: @"—") attributes:plain];
    void (^person)(NSString *, NSString *, NSString *) = ^(NSString *label, NSString *name, NSString *url) {
        if (!name.length) return;
        [a appendAttributedString:[[NSAttributedString alloc] initWithString:[NSString stringWithFormat:@" · %@ ", label] attributes:plain]];
        NSMutableDictionary *link = [plain mutableCopy];
        NSURL *u = url.length ? [NSURL URLWithString:url] : nil;
        if (u) link[NSLinkAttributeName] = u;
        [a appendAttributedString:[[NSAttributedString alloc] initWithString:name attributes:link]];
    };
    person(SLLoc(@"uploaded_by"), _lyrics.uploaderName, _lyrics.uploaderURL);
    person(SLLoc(@"synced_by"), _lyrics.makerName, _lyrics.makerURL);
    _attribution.attributedText = a;
    _attribution.hidden = NO;
    [self setNeedsLayout];
}

- (void)reload {
    [[SLLyricsProvider shared] clearCache];
    _loadingKey = nil;
    [self loadLyrics];
}

- (void)loadLyrics {
    SLNowPlaying *np = [SLNowPlaying shared];
    if (!np.title.length) {
        [self setLyrics:nil];
        [self setStatus:SLLoc(@"play_track") loading:NO];
        return;
    }
    NSString *key = np.trackKey;
    if ([_loadingKey isEqualToString:key]) return;
    _loadingKey = key;

    SLLyrics *cached = [[SLLyricsProvider shared] cachedLyricsForKey:key];
    if (cached) { [self setStatus:@"" loading:NO]; [self setLyrics:cached]; return; }

    [self setLyrics:nil];
    [self setStatus:@"" loading:YES];
    [[SLLyricsProvider shared] lyricsForTitle:np.title artist:np.artist ?: @"" album:np.album duration:np.duration
                                     trackURI:np.trackURI trackKey:key completion:^(SLLyrics *ly, NSString *err) {
        if (![key isEqualToString:self->_loadingKey]) return;
        if (ly) [self setStatus:@"" loading:NO]; else [self showNoLyrics:err];
        [self setLyrics:ly];
    }];
}

/// «No lyrics found for this song» на языке Spotify.
/// На полноэкранном — ниже мелко причина, если это не обычное «текста нет» (нет ключа, сервер недоступен и т.п.).
- (void)showNoLyrics:(NSString *)detail {
    NSString *main = SLLoc(@"no_lyrics");
    BOOL plain = !detail.length || [detail isEqualToString:SLLoc(@"err_spicy_none")];
    if (_mode != SLLyricsViewModeFull || plain) { [self setStatus:main loading:NO]; return; }
    [self setStatus:main loading:NO];
    NSMutableAttributedString *a = [[NSMutableAttributedString alloc] initWithString:main attributes:@{
        NSFontAttributeName: _statusLabel.font, NSForegroundColorAttributeName: _statusLabel.textColor }];
    [a appendAttributedString:[[NSAttributedString alloc] initWithString:[@"\n" stringByAppendingString:detail] attributes:@{
        NSFontAttributeName: [UIFont systemFontOfSize:13 weight:UIFontWeightMedium],
        NSForegroundColorAttributeName: [UIColor colorWithWhite:1 alpha:0.4] }]];
    _statusLabel.attributedText = a;
}

#pragma mark - Build

- (CGFloat)fontSize {
    CGFloat base = _mode == SLLyricsViewModeFull ? 30 : _mode == SLLyricsViewModeCompact ? 22 : ([self isTall] ? 26 : 20);
    return round(base * [SLSettings shared].fontScale);
}

- (void)buildLines {
    for (UIView *v in _scroll.subviews) [v removeFromSuperview];
    _lineViews = @[];
    _primary = NSIntegerMin;
    _activeSet = [NSIndexSet indexSet];
    if (!_lyrics) { _scroll.contentSize = CGSizeZero; return; }

    CGFloat width = [self textWidth];
    if (width <= 60 || self.bounds.size.height <= 20) return;
    _builtWidth = width;
    _builtTall = [self isTall];

    BOOL synced = _lyrics.type != SLLyricsTypeStatic;
    CGFloat font = [self fontSize];
    CGFloat gap = synced ? round(font * 0.72) : round(font * 0.35);
    BOOL bgVocals = [SLSettings shared].showBackgroundVocals;
    CGFloat x = _contentInsets.left, y = 0;

    NSMutableArray *views = [NSMutableArray array];
    for (SLLine *line in _lyrics.lines) {
        SLLineView *lv = [[SLLineView alloc] initWithLine:line width:width fontSize:font type:_lyrics.type backgroundVocals:bgVocals];
        lv.layer.anchorPoint = CGPointMake(line.oppositeAligned ? 1 : 0, 0.5);
        lv.frame = CGRectMake(x, y, width, lv.contentHeight);
        if (synced && !line.isInterlude) {
            [lv addGestureRecognizer:[[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(lineTapped:)]];
        }
        if (synced) {
            [lv updateWithTime:-1 state:SLLineStateFuture glow:NO];
            lv.alpha = line.isInterlude ? 0 : 0.8;
        }
        [_scroll addSubview:lv];
        [views addObject:lv];
        y += lv.contentHeight + gap;
    }

    NSString *src = _lyrics.songwriters.count ? SLLocFormat(@"songwriters", [_lyrics.songwriters componentsJoinedByString:@", "]) : @"";
    _sourceLabel.text = src;
    CGSize ss = [_sourceLabel sizeThatFits:CGSizeMake(width, CGFLOAT_MAX)];
    _sourceLabel.frame = CGRectMake(x, y + 16, width, ceil(ss.height));
    _sourceLabel.hidden = _mode != SLLyricsViewModeFull;
    [_scroll addSubview:_sourceLabel];
    y = CGRectGetMaxY(_sourceLabel.frame) + 24;

    _lineViews = views;
    [self updateInsets];
    _scroll.contentSize = CGSizeMake(self.bounds.size.width, y);
    _scroll.contentOffset = CGPointMake(0, -_scroll.contentInset.top);
    [self tick];
    [self scrollToPrimaryAnimated:NO];
}

- (void)updateInsets {
    CGFloat h = _scroll.bounds.size.height;
    _builtHeight = h;
    CGFloat anchor = [self anchorFraction];
    BOOL synced = _lyrics.type != SLLyricsTypeStatic;
    _scroll.contentInset = synced ? UIEdgeInsetsMake(h * anchor, 0, h * (1 - anchor), 0) : UIEdgeInsetsMake(24, 0, 60, 0);
}

- (CGFloat)anchorFraction {
    return _mode == SLLyricsViewModeFull ? 0.3 : _mode == SLLyricsViewModeCompact ? 0.32 : ([self isTall] ? 0.3 : 0.06);
}

#pragma mark - Sync

- (NSInteger)primaryIndexAt:(double)t {
    NSArray<SLLine *> *lines = _lyrics.lines;
    NSInteger lo = 0, hi = (NSInteger)lines.count - 1, ans = -1;
    while (lo <= hi) {
        NSInteger mid = (lo + hi) / 2;
        if (lines[mid].start <= t) { ans = mid; lo = mid + 1; } else hi = mid - 1;
    }
    return ans;
}

- (void)tick {
    if (!_lyrics || _lyrics.type == SLLyricsTypeStatic || !_lineViews.count) return;
    double t = [[SLNowPlaying shared] currentTime];
    NSArray<SLLine *> *lines = _lyrics.lines;
    NSInteger primary = [self primaryIndexAt:t];

    // активны все строки, которые сейчас звучат (перекрытия, дуэты)
    NSMutableIndexSet *active = [NSMutableIndexSet indexSet];
    for (NSInteger i = MAX(0, primary - 4); i <= primary && i < (NSInteger)lines.count; i++) {
        if (lines[i].start <= t && t < lines[i].end) [active addIndex:i];
    }
    if (primary >= 0 && !lines[primary].isInterlude) [active addIndex:primary]; // держим, пока не началась следующая

    BOOL glow = [SLSettings shared].wordGlow;
    if (primary != _primary || ![active isEqualToIndexSet:_activeSet]) {
        BOOL primaryChanged = primary != _primary;
        _primary = primary;
        _activeSet = [active copy];
        [self applyStatesAt:t];
        if (primaryChanged && !_userScrolling && CACurrentMediaTime() - _userScrollEnd > 3.0) [self scrollToPrimaryAnimated:YES];
    }
    [_activeSet enumerateIndexesUsingBlock:^(NSUInteger i, BOOL *stop) {
        if (i < self->_lineViews.count) [self->_lineViews[i] updateWithTime:t state:SLLineStateActive glow:glow];
    }];

    if (_interactive) {
        BOOL detached = _userScrolling || CACurrentMediaTime() - _userScrollEnd <= 3.0;
        CGFloat want = detached ? 1 : 0;
        if (_resyncButton.alpha != want) [UIView animateWithDuration:0.25 animations:^{ self->_resyncButton.alpha = want; }];
        if (!detached && _userScrollEnd > 0) { _userScrollEnd = 0; [self scrollToPrimaryAnimated:YES]; }
    }
}

- (void)applyStatesAt:(double)t {
    NSInteger n = _lineViews.count;
    NSInteger primary = _primary;
    NSIndexSet *active = _activeSet;
    [UIView animateWithDuration:0.4 delay:0 options:UIViewAnimationOptionAllowUserInteraction | UIViewAnimationOptionBeginFromCurrentState animations:^{
        for (NSInteger i = 0; i < n; i++) {
            SLLineView *lv = self->_lineViews[i];
            BOOL isActive = [active containsIndex:i];
            SLLineState st = isActive ? SLLineStateActive : (i <= primary ? SLLineStatePast : SLLineStateFuture);
            if (st != lv.state) [lv updateWithTime:t state:st glow:NO];
            NSInteger d = labs(i - MAX(primary, 0));
            CGFloat alpha, scale;
            if (isActive) { alpha = 1; scale = 1; }
            else if (st == SLLineStatePast) { alpha = MAX(0.22, 0.5 - 0.07 * (d - 1)); scale = 0.97; }
            else { alpha = MAX(0.4, 0.85 - 0.1 * (d - 1)); scale = 0.97; }
            if (lv.line.isInterlude && !isActive) { alpha = 0; scale = 0.6; }
            lv.alpha = alpha;
            lv.transform = CGAffineTransformMakeScale(scale, scale);
        }
    } completion:nil];
}

- (void)scrollToPrimaryAnimated:(BOOL)animated {
    if (_lyrics.type == SLLyricsTypeStatic || !_lineViews.count) return;
    NSInteger idx = MAX(_primary, 0);
    if (idx >= (NSInteger)_lineViews.count) return;
    SLLineView *lv = _lineViews[idx];
    CGFloat h = _scroll.bounds.size.height;
    CGFloat targetY = CGRectGetMinY(lv.frame) - h * [self anchorFraction];
    CGFloat minY = -_scroll.contentInset.top;
    CGFloat maxY = MAX(minY, _scroll.contentSize.height + _scroll.contentInset.bottom - h);
    targetY = MIN(MAX(targetY, minY), maxY);
    if (!animated) { _scroll.contentOffset = CGPointMake(0, targetY); return; }
    [UIView animateWithDuration:0.8 delay:0 usingSpringWithDamping:0.88 initialSpringVelocity:0
                        options:UIViewAnimationOptionAllowUserInteraction | UIViewAnimationOptionBeginFromCurrentState
                     animations:^{ self->_scroll.contentOffset = CGPointMake(0, targetY); } completion:nil];
}

- (void)resync {
    _userScrolling = NO;
    _userScrollEnd = 0;
    [self scrollToPrimaryAnimated:YES];
}

- (void)lineTapped:(UITapGestureRecognizer *)g {
    if (!_interactive || _lyrics.type == SLLyricsTypeStatic) return;
    SLLineView *lv = (SLLineView *)g.view;
    double target = lv.line.start - [SLSettings shared].syncOffsetMs / 1000.0 + 0.01;
    [SLRemote seekTo:target];
    [self resync];
}

#pragma mark - UIScrollViewDelegate

- (void)scrollViewWillBeginDragging:(UIScrollView *)scrollView {
    [scrollView.layer removeAllAnimations];
    _userScrolling = YES;
}

- (void)scrollViewDidEndDragging:(UIScrollView *)scrollView willDecelerate:(BOOL)decelerate {
    if (!decelerate) { _userScrolling = NO; _userScrollEnd = CACurrentMediaTime(); }
}

- (void)scrollViewDidEndDecelerating:(UIScrollView *)scrollView {
    _userScrolling = NO;
    _userScrollEnd = CACurrentMediaTime();
}

@end

#pragma mark - Weak proxy

@implementation SLWeakTickProxy
- (void)tick { [(SLLyricsView *)self.target tick]; }
@end
