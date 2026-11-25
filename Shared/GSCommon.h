#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

extern NSString *const GSErrorDomain;
extern NSString *const GSAppGroup;                  // shared by the app and its share extension
extern NSString *const GSChangedDarwinName;         // posted across processes when the library changes

typedef NS_ENUM(NSInteger, GSErrorCode) {
    GSErrorNoLink = 1,
    GSErrorNetwork,
    GSErrorNoMedia,
    GSErrorRestricted,
    GSErrorVideo,
    GSErrorStorage,
    GSErrorCancelled,
};

/// An error whose description is a sentence that can be shown as it is.
NSError *GSMakeError(GSErrorCode code, NSString *message);

/// Memory this process is charged for, and how much more it may take before the system ends it (-1 when unknown).
double GSFootprintMB(void);
double GSAvailableMB(void);

/// "1.4 MB", "820 KB".
NSString *GSByteString(long long bytes);

NS_ASSUME_NONNULL_END
