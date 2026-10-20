#import <Foundation/Foundation.h>
#import <objc/runtime.h>

static inline BOOL SLHook(Class cls, SEL sel, id (^makeBlock)(IMP orig)) {
    if (!cls) return NO;
    Method m = class_getInstanceMethod(cls, sel);
    if (!m) return NO;
    IMP orig = method_getImplementation(m);
    IMP repl = imp_implementationWithBlock(makeBlock(orig));
    if (!class_addMethod(cls, sel, repl, method_getTypeEncoding(m))) method_setImplementation(m, repl);
    return YES;
}
