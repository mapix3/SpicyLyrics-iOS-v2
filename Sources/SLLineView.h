#import <UIKit/UIKit.h>
#import "SLLyrics.h"

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSInteger, SLLineState) {
    SLLineStateFuture = 0,
    SLLineStateActive = 1,
    SLLineStatePast = 2,
};

@interface SLLineView : UIView
@property (nonatomic, strong, readonly) SLLine *line;
@property (nonatomic, readonly) SLLineState state;
@property (nonatomic, readonly) CGFloat contentHeight;

- (instancetype)initWithLine:(SLLine *)line
                       width:(CGFloat)width
                    fontSize:(CGFloat)fontSize
                        type:(SLLyricsType)type
              backgroundVocals:(BOOL)showBackground;
- (void)updateWithTime:(double)t state:(SLLineState)state glow:(BOOL)glow;
@end

NS_ASSUME_NONNULL_END
