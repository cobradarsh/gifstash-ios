#import "GSCommon.h"

NSString *const GSErrorDomain = @"GifStash";
NSString *const GSAppGroup = @"group.com.cobradarsh.gifstash";
NSString *const GSChangedDarwinName = @"com.cobradarsh.gifstash.changed";

NSError *GSMakeError(GSErrorCode code, NSString *message) {
    return [NSError errorWithDomain:GSErrorDomain code:code userInfo:@{NSLocalizedDescriptionKey: message ?: @"Something went wrong."}];
}

NSString *GSByteString(long long bytes) {
    if (bytes < 1000) return [NSString stringWithFormat:@"%lld B", bytes];
    if (bytes < 1000 * 1000) return [NSString stringWithFormat:@"%.0f KB", bytes / 1000.0];
    if (bytes < 10 * 1000 * 1000) return [NSString stringWithFormat:@"%.1f MB", bytes / 1000000.0];
    if (bytes < 1000LL * 1000 * 1000) return [NSString stringWithFormat:@"%.0f MB", bytes / 1000000.0];
    return [NSString stringWithFormat:@"%.1f GB", bytes / 1000000000.0];
}
