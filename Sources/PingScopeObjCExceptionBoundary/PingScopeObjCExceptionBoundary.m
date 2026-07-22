#import "PingScopeObjCExceptionBoundary.h"
#import <os/log.h>

id _Nullable PingScopePerformCatchingObjCException(id _Nullable (^operation)(void)) {
    @try {
        return operation();
    } @catch (NSException *exception) {
        os_log_with_type(
            OS_LOG_DEFAULT,
            OS_LOG_TYPE_ERROR,
            "PingScope caught Objective-C exception %{public}@: %{private}@",
            exception.name ?: @"<unknown>",
            exception.reason ?: @"<no reason>"
        );
        return nil;
    }
}
