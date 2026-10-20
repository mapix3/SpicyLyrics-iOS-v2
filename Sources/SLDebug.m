#import "SLDebug.h"

static dispatch_queue_t SLDebugQueue(void) {
    static dispatch_queue_t q;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ q = dispatch_queue_create("SpicyLyricsiOS.debug", DISPATCH_QUEUE_SERIAL); });
    return q;
}

/// Папка пересоздаётся при каждом запуске Spotify — в ней только текущая сессия.
static NSURL *SLDebugDir(void) {
    static NSURL *dir;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        NSFileManager *fm = NSFileManager.defaultManager;
        NSURL *docs = [fm URLsForDirectory:NSDocumentDirectory inDomains:NSUserDomainMask].firstObject;
        dir = [docs URLByAppendingPathComponent:@"SpicyLyricsiOS-debug" isDirectory:YES];
        [fm removeItemAtURL:dir error:nil];
        [fm createDirectoryAtURL:dir withIntermediateDirectories:YES attributes:nil error:nil];
    });
    return dir;
}

static void SLAppend(NSString *file, NSString *text) {
    NSURL *url = [SLDebugDir() URLByAppendingPathComponent:file];
    NSData *data = [text dataUsingEncoding:NSUTF8StringEncoding];
    NSFileHandle *h = [NSFileHandle fileHandleForWritingToURL:url error:nil];
    if (!h) { [data writeToURL:url atomically:NO]; return; }
    [h seekToEndOfFile];
    [h writeData:data];
    [h closeFile];
}

void SLLog(NSString *format, ...) {
    va_list args;
    va_start(args, format);
    NSString *msg = [[NSString alloc] initWithFormat:format arguments:args];
    va_end(args);
    NSString *stamp = [NSString stringWithFormat:@"%.3f", CFAbsoluteTimeGetCurrent()];
    BOOL main = [NSThread isMainThread];
    dispatch_async(SLDebugQueue(), ^{
        SLAppend(@"log.txt", [NSString stringWithFormat:@"%@ %@ %@\n", stamp, main ? @"[M]" : @"[B]", msg]);
    });
}

void SLDebugSaveBody(NSString *prefix, NSData *data) {
    if (!data) return;
    NSData *copy = [data copy];
    dispatch_async(SLDebugQueue(), ^{
        static NSMutableDictionary<NSString *, NSNumber *> *counts;
        if (!counts) counts = [NSMutableDictionary dictionary];
        NSInteger n = counts[prefix].integerValue;
        if (n >= 12) return;
        counts[prefix] = @(n + 1);
        NSString *name = [NSString stringWithFormat:@"%@-%02ld.bin", prefix, (long)n];
        [copy writeToURL:[SLDebugDir() URLByAppendingPathComponent:name] atomically:NO];
        SLAppend(@"log.txt", [NSString stringWithFormat:@"%.3f saved %@ (%lu bytes)\n", CFAbsoluteTimeGetCurrent(), name, (unsigned long)copy.length]);
    });
}

static void SLDescribe(UIView *v, NSInteger depth, NSMutableString *out, NSUInteger *lines) {
    if (depth > 30 || *lines > 4000) return;
    (*lines)++;
    NSMutableString *line = [NSMutableString string];
    for (NSInteger i = 0; i < depth; i++) [line appendString:@"  "];
    CGRect f = v.frame;
    [line appendFormat:@"%@ (%.0f,%.0f %.0fx%.0f)", NSStringFromClass([v class]), f.origin.x, f.origin.y, f.size.width, f.size.height];
    if (v.hidden) [line appendString:@" hidden"];
    if (v.alpha < 0.99) [line appendFormat:@" a=%.2f", v.alpha];
    if ([v isKindOfClass:[UIScrollView class]]) {
        UIScrollView *s = (UIScrollView *)v;
        [line appendFormat:@" inset=%@ size=%@ off=%@", NSStringFromUIEdgeInsets(s.contentInset),
                           NSStringFromCGSize(s.contentSize), NSStringFromCGPoint(s.contentOffset)];
    }
    if ([v isKindOfClass:[UICollectionViewCell class]]) {
        UICollectionView *cv = (UICollectionView *)v.superview;
        if ([cv isKindOfClass:[UICollectionView class]]) {
            NSIndexPath *ip = [cv indexPathForCell:(UICollectionViewCell *)v];
            if (ip) [line appendFormat:@" ip=%ld.%ld", (long)ip.section, (long)ip.item];
        }
    }
    if ([v isKindOfClass:[UILabel class]]) {
        NSString *t = ((UILabel *)v).text ?: @"";
        if (t.length > 40) t = [[t substringToIndex:40] stringByAppendingString:@"…"];
        [line appendFormat:@" \"%@\"", t];
    }
    if (v.accessibilityIdentifier.length) [line appendFormat:@" id=%@", v.accessibilityIdentifier];
    UIResponder *next = v.nextResponder;
    if ([next isKindOfClass:[UIViewController class]]) [line appendFormat:@" vc=%@", NSStringFromClass([next class])];
    [out appendString:line];
    [out appendString:@"\n"];
    for (UIView *s in v.subviews) SLDescribe(s, depth + 1, out, lines);
}

void SLDebugDumpViews(NSString *name, UIView *root) {
    if (!root) return;
    NSMutableString *out = [NSMutableString string];
    NSUInteger lines = 0;
    SLDescribe(root, 0, out, &lines);
    dispatch_async(SLDebugQueue(), ^{
        static NSInteger n;
        NSString *file = [NSString stringWithFormat:@"views-%02ld-%@.txt", (long)n++, name];
        [out writeToURL:[SLDebugDir() URLByAppendingPathComponent:file] atomically:NO encoding:NSUTF8StringEncoding error:nil];
        SLAppend(@"log.txt", [NSString stringWithFormat:@"%.3f saved %@\n", CFAbsoluteTimeGetCurrent(), file]);
    });
}

void SLDebugShare(UIViewController *from, UIView *sourceView) {
    dispatch_async(SLDebugQueue(), ^{
        NSArray<NSURL *> *files = [NSFileManager.defaultManager contentsOfDirectoryAtURL:SLDebugDir()
                                                             includingPropertiesForKeys:nil options:0 error:nil] ?: @[];
        files = [files sortedArrayUsingComparator:^NSComparisonResult(NSURL *a, NSURL *b) {
            return [a.lastPathComponent compare:b.lastPathComponent];
        }];
        dispatch_async(dispatch_get_main_queue(), ^{
            if (!files.count) return;
            UIActivityViewController *vc = [[UIActivityViewController alloc] initWithActivityItems:files applicationActivities:nil];
            vc.popoverPresentationController.sourceView = sourceView ?: from.view;
            vc.popoverPresentationController.sourceRect = (sourceView ?: from.view).bounds;
            [from presentViewController:vc animated:YES completion:nil];
        });
    });
}
