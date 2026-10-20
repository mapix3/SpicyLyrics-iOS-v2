#import "SLBackgroundView.h"
#import <CoreImage/CoreImage.h>

@implementation SLBackgroundView {
    NSArray<CALayer *> *_blobs;
    CALayer *_dim;
    CAGradientLayer *_shade;
    UIImage *_source;
}

- (instancetype)initWithFrame:(CGRect)frame {
    if ((self = [super initWithFrame:frame])) {
        self.clipsToBounds = YES;
        self.backgroundColor = [UIColor colorWithWhite:0.07 alpha:1];
        self.userInteractionEnabled = NO;
        NSMutableArray *blobs = [NSMutableArray array];
        for (int i = 0; i < 3; i++) {
            CALayer *l = [CALayer layer];
            l.contentsGravity = kCAGravityResizeAspectFill;
            l.opacity = i == 0 ? 1.0 : 0.75;
            [self.layer addSublayer:l];
            [blobs addObject:l];
        }
        _blobs = blobs;
        _dim = [CALayer layer];
        _dim.backgroundColor = [UIColor colorWithWhite:0 alpha:0.32].CGColor;
        [self.layer addSublayer:_dim];
        _shade = [CAGradientLayer layer];
        _shade.colors = @[(id)[UIColor colorWithWhite:0 alpha:0.25].CGColor,
                          (id)[UIColor colorWithWhite:0 alpha:0.0].CGColor,
                          (id)[UIColor colorWithWhite:0 alpha:0.45].CGColor];
        _shade.locations = @[@0, @0.35, @1];
        [self.layer addSublayer:_shade];
        _animated = YES;
    }
    return self;
}

- (void)layoutSubviews {
    [super layoutSubviews];
    CGRect b = self.bounds;
    CGFloat side = MAX(b.size.width, b.size.height) * 1.7;
    CGPoint centers[3] = {
        CGPointMake(CGRectGetMidX(b), CGRectGetMidY(b)),
        CGPointMake(b.size.width * 0.05, b.size.height * 0.1),
        CGPointMake(b.size.width * 0.95, b.size.height * 0.9),
    };
    CGFloat scales[3] = { 1.0, 0.75, 0.8 };
    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    for (int i = 0; i < 3; i++) {
        _blobs[i].bounds = CGRectMake(0, 0, side * scales[i], side * scales[i]);
        _blobs[i].position = centers[i];
    }
    _dim.frame = b;
    _shade.frame = b;
    [CATransaction commit];
    [self updateAnimations];
}

- (void)setAnimated:(BOOL)animated {
    _animated = animated;
    [self updateAnimations];
}

- (void)didMoveToWindow {
    [super didMoveToWindow];
    [self updateAnimations];
}

- (void)updateAnimations {
    double durations[3] = { 48, 64, 80 };
    for (int i = 0; i < 3; i++) {
        CALayer *l = _blobs[i];
        if (!_animated || !self.window) { [l removeAnimationForKey:@"spin"]; continue; }
        if ([l animationForKey:@"spin"]) continue;
        CABasicAnimation *a = [CABasicAnimation animationWithKeyPath:@"transform.rotation.z"];
        a.fromValue = @(i * 1.3);
        a.toValue = @(i * 1.3 + ((i % 2) ? -2 * M_PI : 2 * M_PI));
        a.duration = durations[i];
        a.repeatCount = HUGE_VALF;
        a.removedOnCompletion = NO;
        [l addAnimation:a forKey:@"spin"];
    }
}

+ (UIImage *)blurred:(UIImage *)img {
    if (!img.CGImage && !img.CIImage) return nil;
    // уменьшаем, чтобы размытие было дешёвым и «огромным»
    CGSize small = CGSizeMake(96, 96);
    UIGraphicsImageRendererFormat *fmt = [UIGraphicsImageRendererFormat defaultFormat];
    fmt.scale = 1;
    UIImage *tiny = [[[UIGraphicsImageRenderer alloc] initWithSize:small format:fmt] imageWithActions:^(UIGraphicsImageRendererContext *ctx) {
        [img drawInRect:CGRectMake(0, 0, small.width, small.height)];
    }];
    CIImage *ci = [CIImage imageWithCGImage:tiny.CGImage];
    CIImage *clamped = [ci imageByClampingToExtent];
    CIFilter *blur = [CIFilter filterWithName:@"CIGaussianBlur"];
    [blur setValue:clamped forKey:kCIInputImageKey];
    [blur setValue:@10 forKey:kCIInputRadiusKey];
    CIFilter *cc = [CIFilter filterWithName:@"CIColorControls"];
    [cc setValue:blur.outputImage forKey:kCIInputImageKey];
    [cc setValue:@1.5 forKey:kCIInputSaturationKey];
    [cc setValue:@(-0.04) forKey:kCIInputBrightnessKey];
    CIImage *out = [cc.outputImage imageByCroppingToRect:ci.extent];
    static CIContext *ctx;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ ctx = [CIContext contextWithOptions:nil]; });
    CGImageRef cg = [ctx createCGImage:out fromRect:ci.extent];
    if (!cg) return nil;
    UIImage *res = [UIImage imageWithCGImage:cg];
    CGImageRelease(cg);
    return res;
}

- (void)setArtwork:(UIImage *)image {
    if (image == _source) return;
    _source = image;
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        UIImage *b = image ? [SLBackgroundView blurred:image] : nil;
        dispatch_async(dispatch_get_main_queue(), ^{
            if (image != self->_source) return;
            for (CALayer *l in self->_blobs) {
                CATransition *fade = [CATransition animation];
                fade.duration = 0.9;
                fade.type = kCATransitionFade;
                [l addAnimation:fade forKey:@"fade"];
                l.contents = (__bridge id)b.CGImage;
            }
        });
    });
}

@end
