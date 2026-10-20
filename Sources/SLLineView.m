#import "SLLineView.h"

static inline CGFloat SLClamp01(CGFloat v) { return v < 0 ? 0 : (v > 1 ? 1 : v); }
static inline CGFloat SLEaseOut(CGFloat t) { return 1 - (1 - t) * (1 - t) * (1 - t); }

static const CGFloat SLDimAlpha = 0.35;

#pragma mark - Syllable

@interface SLSyllableView : UIView
@property (nonatomic, strong) SLWord *word;
@property (nonatomic, strong) UILabel *base;
@property (nonatomic, strong) UILabel *fill;
@property (nonatomic, strong) CAGradientLayer *mask;
@property (nonatomic) CGFloat progress;
@property (nonatomic) CGFloat liftAmount;
@end

@implementation SLSyllableView

- (instancetype)initWithWord:(SLWord *)word font:(UIFont *)font dim:(CGFloat)dim {
    if ((self = [super initWithFrame:CGRectZero])) {
        _word = word;
        _progress = -1;
        _liftAmount = font.pointSize * 0.07;
        NSString *text = [word.text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];

        _base = [UILabel new];
        _base.font = font;
        _base.text = text;
        _base.textColor = [UIColor colorWithWhite:1 alpha:dim];
        _base.lineBreakMode = NSLineBreakByClipping;
        [self addSubview:_base];

        _fill = [UILabel new];
        _fill.font = font;
        _fill.text = text;
        _fill.textColor = UIColor.whiteColor;
        _fill.lineBreakMode = NSLineBreakByClipping;
        _fill.layer.shadowColor = UIColor.whiteColor.CGColor;
        _fill.layer.shadowOffset = CGSizeZero;
        _fill.layer.shadowRadius = font.pointSize * 0.3;
        _fill.layer.shadowOpacity = 0;
        [self addSubview:_fill];

        _mask = [CAGradientLayer layer];
        _mask.startPoint = CGPointMake(0, 0.5);
        _mask.endPoint = CGPointMake(1, 0.5);
        _mask.colors = @[(id)UIColor.blackColor.CGColor, (id)UIColor.blackColor.CGColor,
                         (id)UIColor.clearColor.CGColor, (id)UIColor.clearColor.CGColor];
        _fill.layer.mask = _mask;
    }
    return self;
}

- (void)layoutSubviews {
    [super layoutSubviews];
    // bounds.width = точный шаг слога; сами надписи чуть шире, чтобы не обрезать выступающие глифы
    CGRect r = self.bounds;
    r.size.width += ceil(_base.font.pointSize * 0.35);
    _base.frame = r;
    _fill.frame = r;
    CGFloat p = _progress;
    _progress = -1;
    [self setProgress:MAX(p, 0) glow:0];
}

- (void)setProgress:(CGFloat)p glow:(CGFloat)glow {
    p = SLClamp01(p);
    if (fabs(p - _progress) < 0.002 && fabs(glow - _fill.layer.shadowOpacity) < 0.01) return;
    _progress = p;
    CGFloat W = MAX(self.bounds.size.width, 1);
    CGFloat H = self.bounds.size.height;
    CGFloat soft = MIN(14, W * 0.5);
    CGFloat edge = -soft / 2 + p * (W + soft);
    CGFloat maskW = 4 * W + soft;
    CGFloat half = (soft / 2) / maskW;

    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    _mask.frame = CGRectMake(edge - maskW / 2, -30, maskW, H + 60);
    _mask.locations = @[@0, @(0.5 - half), @(0.5 + half), @1];
    _fill.layer.shadowOpacity = glow;
    CGFloat lift = p <= 0 ? 0 : -_liftAmount * SLEaseOut(MIN(p * 1.6, 1));
    CGFloat scale = 1 + 0.035 * glow;
    // масштаб от левого края слога, чтобы он не наезжал на предыдущий
    CGFloat dx = (scale - 1) * self.bounds.size.width / 2;
    CGAffineTransform t = CGAffineTransformMakeTranslation(dx, lift);
    self.transform = CGAffineTransformScale(t, scale, scale);
    [CATransaction commit];
}

@end

#pragma mark - Interlude dots

@interface SLDotsView : UIView
@property (nonatomic, strong) NSArray<UIView *> *dots;
@end

@implementation SLDotsView

- (instancetype)initWithSize:(CGFloat)d {
    if ((self = [super initWithFrame:CGRectMake(0, 0, d * 3 + d * 0.8 * 2, d)])) {
        NSMutableArray *a = [NSMutableArray array];
        for (int i = 0; i < 3; i++) {
            UIView *v = [[UIView alloc] initWithFrame:CGRectMake(i * d * 1.8, 0, d, d)];
            v.backgroundColor = UIColor.whiteColor;
            v.layer.cornerRadius = d / 2;
            v.layer.shadowColor = UIColor.whiteColor.CGColor;
            v.layer.shadowRadius = d * 0.6;
            v.layer.shadowOffset = CGSizeZero;
            v.alpha = SLDimAlpha;
            [self addSubview:v];
            [a addObject:v];
        }
        _dots = a;
    }
    return self;
}

- (void)update:(double)t start:(double)start end:(double)end active:(BOOL)active {
    double span = MAX(end - start, 0.1);
    CGFloat p = SLClamp01((t - start) / span);
    for (NSUInteger i = 0; i < 3; i++) {
        CGFloat dp = active ? SLClamp01(p * 3 - i) : 0;
        _dots[i].alpha = SLDimAlpha + (1 - SLDimAlpha) * dp;
        _dots[i].layer.shadowOpacity = active ? dp * 0.8 : 0;
        _dots[i].transform = CGAffineTransformMakeTranslation(0, -2 * SLEaseOut(dp));
    }
    CGFloat breathe = active ? 1.0 + 0.1 * sin(t * 2 * M_PI / 2.0) : 1.0;
    CGFloat endFade = active ? SLClamp01((1 - p) / 0.06) : 1;   // в конце паузы точки «схлопываются»
    CGFloat s = breathe * (0.4 + 0.6 * endFade);
    self.transform = CGAffineTransformMakeScale(s, s);
}

@end

#pragma mark - Line

@implementation SLLineView {
    SLLyricsType _type;
    NSArray<SLSyllableView *> *_lead;
    NSArray<SLSyllableView *> *_bg;
    UIView *_bgContainer;
    SLDotsView *_dots;
    UILabel *_label;
}

- (instancetype)initWithLine:(SLLine *)line width:(CGFloat)width fontSize:(CGFloat)fontSize
                        type:(SLLyricsType)type backgroundVocals:(BOOL)showBackground {
    if ((self = [super initWithFrame:CGRectMake(0, 0, width, 10)])) {
        _line = line;
        _type = type;
        _state = (SLLineState)-1;
        UIFont *font = [UIFont systemFontOfSize:fontSize weight:UIFontWeightBold];
        BOOL right = line.oppositeAligned;

        if (line.isInterlude) {
            CGFloat d = round(fontSize * 0.42);
            _dots = [[SLDotsView alloc] initWithSize:d];
            CGRect f = _dots.frame;
            f.origin = CGPointMake(right ? width - f.size.width - 2 : 2, fontSize * 0.45);
            _dots.layer.anchorPoint = CGPointMake(right ? 1 : 0, 0.5);
            _dots.frame = f;
            [self addSubview:_dots];
            _contentHeight = f.size.height + fontSize * 0.9;
        } else if (type == SLLyricsTypeSyllable && line.words.count) {
            CGFloat y = 0;
            _lead = [self layoutWords:line.words font:font width:width right:right y:&y dim:SLDimAlpha into:self];
            if (showBackground && line.background.count) {
                UIFont *bgFont = [UIFont systemFontOfSize:round(fontSize * 0.62) weight:UIFontWeightBold];
                _bgContainer = [[UIView alloc] initWithFrame:CGRectMake(0, y + fontSize * 0.12, width, 10)];
                CGFloat by = 0;
                _bg = [self layoutWords:line.background font:bgFont width:width right:right y:&by dim:0.25 into:_bgContainer];
                CGRect f = _bgContainer.frame; f.size.height = by; _bgContainer.frame = f;
                _bgContainer.alpha = 0.85;
                [self addSubview:_bgContainer];
                y = CGRectGetMaxY(f);
            }
            _contentHeight = ceil(y);
        } else {
            BOOL isStatic = type == SLLyricsTypeStatic;
            _label = [UILabel new];
            _label.numberOfLines = 0;
            _label.font = isStatic ? [UIFont systemFontOfSize:round(fontSize * 0.8) weight:UIFontWeightBold] : font;
            _label.textColor = isStatic ? UIColor.whiteColor : [UIColor colorWithWhite:1 alpha:SLDimAlpha];
            _label.textAlignment = right ? NSTextAlignmentRight : NSTextAlignmentLeft;
            _label.text = line.text.length ? line.text : @" ";
            _label.layer.shadowColor = UIColor.whiteColor.CGColor;
            _label.layer.shadowOffset = CGSizeZero;
            _label.layer.shadowRadius = fontSize * 0.3;
            CGSize sz = [_label sizeThatFits:CGSizeMake(width, CGFLOAT_MAX)];
            _label.frame = CGRectMake(0, 0, width, ceil(sz.height));
            [self addSubview:_label];
            _contentHeight = ceil(sz.height);
        }
        CGRect f = self.frame; f.size.height = _contentHeight; self.frame = f;
    }
    return self;
}

/// Раскладка слогов: слоги одного слова держатся вместе, перенос — между словами.
- (NSArray<SLSyllableView *> *)layoutWords:(NSArray<SLWord *> *)words font:(UIFont *)font width:(CGFloat)width
                                     right:(BOOL)right y:(CGFloat *)yOut dim:(CGFloat)dim into:(UIView *)host {
    NSDictionary *attrs = @{ NSFontAttributeName: font };
    CGFloat spaceW = [@" " sizeWithAttributes:attrs].width;
    CGFloat lineH = ceil(font.lineHeight * 1.12);

    // группы слогов = слова
    NSMutableArray<NSMutableArray<SLWord *> *> *groups = [NSMutableArray array];
    NSMutableArray<SLWord *> *cur = nil;
    for (SLWord *w in words) {
        if (!cur) { cur = [NSMutableArray array]; [groups addObject:cur]; }
        [cur addObject:w];
        if (!w.partOfWord) cur = nil;
    }

    NSMutableArray<SLSyllableView *> *views = [NSMutableArray array];
    NSMutableArray<NSMutableArray<SLSyllableView *> *> *rows = [NSMutableArray arrayWithObject:[NSMutableArray array]];
    NSMutableArray<NSNumber *> *rowWidths = [NSMutableArray arrayWithObject:@0];
    CGFloat x = 0, y = 0;

    for (NSArray<SLWord *> *g in groups) {
        NSMutableArray<NSNumber *> *ws = [NSMutableArray array];
        CGFloat gw = 0;
        NSMutableString *prefix = [NSMutableString string];
        for (SLWord *w in g) {
            NSString *t = [w.text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
            // шаг слога = ширина «слово до него + он» минус «слово до него»: учитывает кернинг между слогами
            [prefix appendString:t];
            CGFloat end = [prefix sizeWithAttributes:attrs].width;
            CGFloat sw = MAX(end - gw, 1);
            [ws addObject:@(sw)];
            gw = end;
        }
        if (x > 0 && x + gw > width) {
            x = 0; y += lineH;
            [rows addObject:[NSMutableArray array]];
            [rowWidths addObject:@0];
        }
        for (NSUInteger i = 0; i < g.count; i++) {
            CGFloat sw = ws[i].doubleValue;
            if (x > 0 && x + sw > width) {     // слово шире строки — переносим посреди
                x = 0; y += lineH;
                [rows addObject:[NSMutableArray array]];
                [rowWidths addObject:@0];
            }
            SLSyllableView *v = [[SLSyllableView alloc] initWithWord:g[i] font:font dim:dim];
            v.frame = CGRectMake(x, y, MIN(sw, width), lineH);
            if (sw > width) v.base.adjustsFontSizeToFitWidth = v.fill.adjustsFontSizeToFitWidth = YES;
            [host addSubview:v];
            [views addObject:v];
            [rows.lastObject addObject:v];
            x += sw;
            rowWidths[rowWidths.count - 1] = @(x);
        }
        x += spaceW;
    }

    if (right) {
        for (NSUInteger r = 0; r < rows.count; r++) {
            CGFloat shift = width - rowWidths[r].doubleValue;
            for (SLSyllableView *v in rows[r]) { CGRect f = v.frame; f.origin.x += shift; v.frame = f; }
        }
    }
    *yOut += y + lineH;
    return views;
}

- (void)applySyllables:(NSArray<SLSyllableView *> *)views time:(double)t glow:(BOOL)glow {
    for (SLSyllableView *v in views) {
        SLWord *w = v.word;
        double dur = MAX(w.end - w.start, 0.03);
        CGFloat p = SLClamp01((t - w.start) / dur);
        CGFloat g = 0;
        // длинные слоги светятся, как «Emphasize» в Spicy Lyrics
        if (glow && p > 0 && p < 1 && dur >= 0.9) g = sin(M_PI * p) * MIN(0.9, 0.45 + (dur - 0.9) * 0.4);
        [v setProgress:p glow:g];
    }
}

- (void)updateWithTime:(double)t state:(SLLineState)state glow:(BOOL)glow {
    BOOL changed = state != _state;
    _state = state;

    if (_dots) {
        [_dots update:t start:_line.start end:_line.end active:state == SLLineStateActive];
        return;
    }

    if (_label) {
        if (_type == SLLyricsTypeStatic || !changed) return;
        BOOL on = state == SLLineStateActive;
        [UIView transitionWithView:_label duration:0.3 options:UIViewAnimationOptionTransitionCrossDissolve | UIViewAnimationOptionAllowUserInteraction animations:^{
            self->_label.textColor = on ? UIColor.whiteColor : [UIColor colorWithWhite:1 alpha:state == SLLineStatePast ? 0.55 : SLDimAlpha];
        } completion:nil];
        _label.layer.shadowOpacity = (on && glow) ? 0.35 : 0;
        return;
    }

    if (state == SLLineStateActive) {
        [self applySyllables:_lead time:t glow:glow];
        [self applySyllables:_bg time:t glow:glow];
        return;
    }
    if (!changed) return;
    // прошедшие — залиты, будущие — пустые; после перемотки тоже корректно
    CGFloat p = state == SLLineStatePast ? 1 : 0;
    for (SLSyllableView *v in _lead) [v setProgress:p glow:0];
    for (SLSyllableView *v in _bg) [v setProgress:p glow:0];
}

@end
