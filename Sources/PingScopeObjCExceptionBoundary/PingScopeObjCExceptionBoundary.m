#import "PingScopeObjCExceptionBoundary.h"

id _Nullable PingScopePerformCatchingObjCException(id _Nullable (^operation)(void)) {
    @try {
        return operation();
    } @catch (NSException *exception) {
        NSLog(@"PingScope caught Objective-C exception %@: %@",
              exception.name,
              exception.reason ?: @"<no reason>");
        return nil;
    }
}
