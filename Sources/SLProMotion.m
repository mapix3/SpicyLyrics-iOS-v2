#import "SLProMotion.h"
#import "SLHook.h"

static NSString *const SLProMotionKey = @"CADisableMinimumFrameDurationOnPhone";

void SLEnableProMotion(void) {
    NSBundle *main = NSBundle.mainBundle;
    // словарь Info.plist главного бандла CoreFoundation держит изменяемым — его же читает QuartzCore
    @try {
        NSDictionary *info = main.infoDictionary;
        if (![info[SLProMotionKey] boolValue] && [info respondsToSelector:@selector(setObject:forKey:)])
            [(NSMutableDictionary *)info setObject:@YES forKey:SLProMotionKey];
    } @catch (NSException *e) {}

    // на случай, если ключ спрашивают через NSBundle
    SEL sel = @selector(objectForInfoDictionaryKey:);
    SLHook([NSBundle class], sel, ^id(IMP orig) {
        return ^id(NSBundle *bundle, NSString *key) {
            if (bundle == NSBundle.mainBundle && [key isEqualToString:SLProMotionKey]) return @YES;
            return ((id (*)(id, SEL, id))orig)(bundle, sel, key);
        };
    });
}
