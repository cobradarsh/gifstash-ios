#import <Foundation/Foundation.h>
#import "GSStore.h"

NS_ASSUME_NONNULL_BEGIN

/// `fraction` is 0...1, or negative while there is nothing to measure.
typedef void (^GSImportProgress)(NSString *stage, double fraction);

/// From a shared or copied link to clips in the library: reads the post, downloads the MP4, makes the GIF.
/// Callbacks arrive on the main queue.
@interface GSImporter : NSObject
@property (nonatomic, readonly) BOOL isBusy;
- (void)importText:(NSString *)text
          progress:(nullable GSImportProgress)progress
        completion:(void (^)(NSArray<GSItem *> *items, NSError *_Nullable error))completion;
@end

NS_ASSUME_NONNULL_END
