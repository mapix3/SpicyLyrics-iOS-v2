#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSInteger, SLLyricsViewMode) {
    SLLyricsViewModeFull = 0,
    SLLyricsViewModeCompact = 1,
    SLLyricsViewModeStrip = 2,
};

@interface SLLyricsView : UIView
- (instancetype)initWithMode:(SLLyricsViewMode)mode;

@property (nonatomic, readonly) SLLyricsViewMode mode;
@property (nonatomic, readonly) BOOL hasLyrics;
@property (nonatomic) BOOL showsBackground;
@property (nonatomic) BOOL showsAttribution;
@property (nonatomic) BOOL interactive;
@property (nonatomic) UIEdgeInsets contentInsets;
@property (nonatomic, copy, nullable) void (^availabilityChanged)(BOOL hasLyrics);

- (void)reload;
- (void)resync;
@end

NS_ASSUME_NONNULL_END
