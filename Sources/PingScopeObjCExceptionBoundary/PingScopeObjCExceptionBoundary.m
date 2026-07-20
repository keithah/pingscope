#import "PingScopeObjCExceptionBoundary.h"

id _Nullable PingScopePerformCatchingObjCException(id _Nullable (^operation)(void)) {
    @try {
        return operation();
    } @catch (__unused NSException *exception) {
        return nil;
    }
}
