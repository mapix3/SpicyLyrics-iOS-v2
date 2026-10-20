#import "SLBackgroundView.h"

static const NSUInteger SLBlobCount = 4;

static UIColor *SLTune(UIColor *c, CGFloat minB, CGFloat maxB, CGFloat satBoost) {
    CGFloat h = 0, s = 0, b = 0, a = 1;
    if (![c getHue:&h saturation:&s brightness:&b alpha:&a]) return c;
    s = MIN(1, s * satBoost + (s > 0.12 ? 0.06 : 0));
    b = MIN(maxB, MAX(minB, b));
    return [UIColor colorWithHue:h saturation:s brightness:b alpha:1];
}

NSArray<UIColor *> *SLArtworkPalette(UIImage *image) {
    const int S = 28;
    CGImageRef cg = image.CGImage;
    if (!cg) return nil;
    uint8_t *px = calloc(S * S * 4, 1);
    if (!px) return nil;
    CGColorSpaceRef cs = CGColorSpaceCreateDeviceRGB();
    CGContextRef ctx = CGBitmapContextCreate(px, S, S, 8, S * 4, cs, kCGImageAlphaPremultipliedLast);
    CGColorSpaceRelease(cs);
    if (!ctx) { free(px); return nil; }
    CGContextSetInterpolationQuality(ctx, kCGInterpolationMedium);
    CGContextDrawImage(ctx, CGRectMake(0, 0, S, S), cg);
    CGContextRelease(ctx);

    enum { Bins = 13 };
    double wsum[Bins] = {0}, rs[Bins] = {0}, gs[Bins] = {0}, bs[Bins] = {0};
    for (int i = 0; i < S * S; i++) {
        double r = px[i * 4] / 255.0, g = px[i * 4 + 1] / 255.0, b = px[i * 4 + 2] / 255.0;
        double mx = MAX(r, MAX(g, b)), mn = MIN(r, MIN(g, b)), d = mx - mn;
        double s = mx > 0 ? d / mx : 0, v = mx;
        int bin;
        double w;
        if (s < 0.16 || v < 0.08) {
            bin = Bins - 1;
            w = 0.25;
        } else {
            double h;
            if (mx == r) h = fmod((g - b) / d, 6);
            else if (mx == g) h = (b - r) / d + 2;
            else h = (r - g) / d + 4;
            h /= 6;
            if (h < 0) h += 1;
            bin = MIN(Bins - 2, (int)(h * (Bins - 1)));
            w = 0.3 + s * v * 2.2;
        }
        wsum[bin] += w; rs[bin] += r * w; gs[bin] += g * w; bs[bin] += b * w;
    }
    free(px);

    double *weights = wsum;
    NSMutableArray<NSNumber *> *order = [NSMutableArray array];
    for (int i = 0; i < Bins; i++) if (wsum[i] > 0) [order addObject:@(i)];
    [order sortUsingComparator:^NSComparisonResult(NSNumber *a, NSNumber *b) {
        return [@(weights[b.intValue]) compare:@(weights[a.intValue])];
    }];
    NSMutableArray<UIColor *> *colors = [NSMutableArray array];
    double total = 0;
    for (int i = 0; i < Bins; i++) total += wsum[i];
    for (NSNumber *n in order) {
        int i = n.intValue;
        if (colors.count && wsum[i] < total * 0.04) break;
        UIColor *c = [UIColor colorWithRed:rs[i] / wsum[i] green:gs[i] / wsum[i] blue:bs[i] / wsum[i] alpha:1];
        [colors addObject:SLTune(c, 0.38, 0.82, 1.25)];
        if (colors.count == SLBlobCount) break;
    }
    if (!colors.count) return nil;
    while (colors.count < SLBlobCount) {
        UIColor *base = colors.firstObject;
        CGFloat h = 0, s = 0, b = 0, a = 1;
        [base getHue:&h saturation:&s brightness:&b alpha:&a];
        CGFloat shift = (colors.count % 2 ? 0.06 : -0.06);
        [colors addObject:[UIColor colorWithHue:fmod(h + shift + 1, 1) saturation:s brightness:MIN(0.85, b * (colors.count % 2 ? 0.75 : 1.15)) alpha:1]];
    }
    return colors;
}

@implementation SLCardBackgroundView {
    NSArray<CAGradientLayer *> *_blobs;
    CAGradientLayer *_shade;
    CALayer *_dim;
    UIImage *_source;
    CGSize _animatedSize;
}

- (instancetype)initWithFrame:(CGRect)frame {
    if ((self = [super initWithFrame:frame])) {
        self.clipsToBounds = YES;
        self.userInteractionEnabled = NO;
        self.backgroundColor = [UIColor colorWithWhite:0.12 alpha:1];
        NSMutableArray *blobs = [NSMutableArray array];
        for (NSUInteger i = 0; i < SLBlobCount; i++) {
            CAGradientLayer *l = [CAGradientLayer layer];
            l.type = kCAGradientLayerRadial;
            l.startPoint = CGPointMake(0.5, 0.5);
            l.endPoint = CGPointMake(1, 1);
            l.locations = @[@0, @0.55, @1];
            l.colors = [self colorsFor:[UIColor colorWithWhite:0.3 alpha:1]];
            l.opacity = 0.9;
            [self.layer addSublayer:l];
            [blobs addObject:l];
        }
        _blobs = blobs;
        _dim = [CALayer layer];
        _dim.backgroundColor = [UIColor colorWithWhite:0 alpha:0.22].CGColor;
        [self.layer addSublayer:_dim];
        _shade = [CAGradientLayer layer];
        _shade.colors = @[(id)[UIColor colorWithWhite:0 alpha:0.18].CGColor,
                          (id)[UIColor colorWithWhite:0 alpha:0.0].CGColor,
                          (id)[UIColor colorWithWhite:0 alpha:0.35].CGColor];
        _shade.locations = @[@0, @0.4, @1];
        [self.layer addSublayer:_shade];
        _animated = YES;
    }
    return self;
}

- (NSArray *)colorsFor:(UIColor *)c {
    return @[(id)c.CGColor, (id)[c colorWithAlphaComponent:0.55].CGColor, (id)[c colorWithAlphaComponent:0].CGColor];
}

- (void)layoutSubviews {
    [super layoutSubviews];
    CGRect b = self.bounds;
    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    CGFloat d = MAX(b.size.width, b.size.height) * 1.15;
    for (NSUInteger i = 0; i < _blobs.count; i++) {
        _blobs[i].bounds = CGRectMake(0, 0, d, d);
        _blobs[i].position = [self restingPoint:i in:b];
    }
    _dim.frame = b;
    _shade.frame = b;
    [CATransaction commit];
    if (!CGSizeEqualToSize(b.size, _animatedSize)) [self updateAnimations];
}

- (CGPoint)restingPoint:(NSUInteger)i in:(CGRect)b {
    static const CGFloat pts[4][2] = { {0.15, 0.2}, {0.85, 0.25}, {0.25, 0.85}, {0.8, 0.8} };
    return CGPointMake(b.size.width * pts[i % 4][0], b.size.height * pts[i % 4][1]);
}

- (void)setAnimated:(BOOL)animated {
    _animated = animated;
    _animatedSize = CGSizeZero;
    [self updateAnimations];
}

- (void)didMoveToWindow {
    [super didMoveToWindow];
    _animatedSize = CGSizeZero;
    [self updateAnimations];
}

- (void)updateAnimations {
    CGRect b = self.bounds;
    for (CAGradientLayer *l in _blobs) [l removeAnimationForKey:@"drift"];
    if (!_animated || !self.window || b.size.width < 1 || b.size.height < 1) return;
    _animatedSize = b.size;
    static const CGFloat paths[4][5][2] = {
        { {0.15, 0.2}, {0.45, 0.05}, {0.6, 0.45}, {0.25, 0.6}, {0.15, 0.2} },
        { {0.85, 0.25}, {0.6, 0.6}, {0.95, 0.75}, {1.0, 0.1}, {0.85, 0.25} },
        { {0.25, 0.85}, {0.05, 0.5}, {0.4, 0.35}, {0.55, 1.0}, {0.25, 0.85} },
        { {0.8, 0.8}, {0.45, 0.95}, {0.3, 0.55}, {0.75, 0.4}, {0.8, 0.8} },
    };
    static const double durations[4] = { 19, 23, 27, 31 };
    for (NSUInteger i = 0; i < _blobs.count; i++) {
        NSMutableArray *values = [NSMutableArray array];
        for (int k = 0; k < 5; k++)
            [values addObject:[NSValue valueWithCGPoint:CGPointMake(b.size.width * paths[i % 4][k][0], b.size.height * paths[i % 4][k][1])]];
        CAKeyframeAnimation *a = [CAKeyframeAnimation animationWithKeyPath:@"position"];
        a.values = values;
        a.duration = durations[i % 4];
        a.calculationMode = kCAAnimationCubic;
        a.repeatCount = HUGE_VALF;
        a.removedOnCompletion = NO;
        a.timeOffset = durations[i % 4] * 0.37 * i;
        [_blobs[i] addAnimation:a forKey:@"drift"];
    }
}

- (void)setArtwork:(UIImage *)image {
    if (image == _source) return;
    _source = image;
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        NSArray<UIColor *> *palette = image ? SLArtworkPalette(image) : nil;
        dispatch_async(dispatch_get_main_queue(), ^{
            if (image != self->_source) return;
            [self applyPalette:palette];
        });
    });
}

- (void)applyPalette:(NSArray<UIColor *> *)palette {
    UIColor *base = palette.count ? SLTune(palette[0], 0.16, 0.26, 1.1) : [UIColor colorWithWhite:0.12 alpha:1];
    [UIView animateWithDuration:0.9 animations:^{ self.backgroundColor = base; }];
    for (NSUInteger i = 0; i < _blobs.count; i++) {
        CAGradientLayer *l = _blobs[i];
        UIColor *c = palette.count ? palette[i % palette.count] : [UIColor colorWithWhite:0.3 alpha:1];
        NSArray *to = [self colorsFor:c];
        CABasicAnimation *fade = [CABasicAnimation animationWithKeyPath:@"colors"];
        fade.fromValue = ((CAGradientLayer *)l.presentationLayer ?: l).colors;
        fade.toValue = to;
        fade.duration = 0.9;
        fade.timingFunction = [CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionEaseInEaseOut];
        l.colors = to;
        [l addAnimation:fade forKey:@"colors"];
    }
}

@end
