#import <Foundation/Foundation.h>

/// Test hooks. They do nothing unless Library/Caches/gs-diag exists in the app's data container when the app starts.
///   gifstash://_diag/<state|import|gifcheck|open|dismiss|copy|delete|snapshot>?...
/// The same URLs can be written, one a line, to Library/Caches/gs-diag-cmd. Answers go to Library/Caches/gs-diag.log.
BOOL GSDiagEnabled(void);
void GSDiagStart(void);
void GSDiagHandle(NSURL *url);
void GSDiagLog(NSString *event, NSDictionary *info);
