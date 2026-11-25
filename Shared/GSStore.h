#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

extern NSString *const GSStoreChangedNotification;     // in this process, on the main queue

/// One saved clip: `<id>.json` plus `<id>.gif`, `<id>.mp4` and `<id>.jpg` next to it.
@interface GSItem : NSObject
@property (nonatomic, copy) NSString *itemID;
@property (nonatomic, copy) NSString *kind;             // "gif" (a GIF on X) or "video"
@property (nonatomic, copy, nullable) NSString *tweetID;
@property (nonatomic, copy, nullable) NSString *author;
@property (nonatomic, copy, nullable) NSString *text;
@property (nonatomic, copy, nullable) NSString *sourceURL;
@property (nonatomic, copy, nullable) NSString *label;  // the user's own name for it
@property (nonatomic) NSInteger width;                  // of the GIF
@property (nonatomic) NSInteger height;
@property (nonatomic) NSInteger frames;
@property (nonatomic) double gifDuration;
@property (nonatomic) double videoDuration;
@property (nonatomic) long long gifBytes;
@property (nonatomic) long long videoBytes;
@property (nonatomic) NSInteger preset;
@property (nonatomic) BOOL trimmed;                     // the GIF stops before the video does
@property (nonatomic) BOOL favorite;
@property (nonatomic, strong) NSDate *savedAt;

- (NSDictionary *)dictionary;
+ (nullable instancetype)itemWithDictionary:(NSDictionary *)dictionary;
/// Height over width, for laying out a tile.
@property (nonatomic, readonly) double aspect;
/// What a search looks through.
@property (nonatomic, readonly) NSString *searchText;
@end

@interface GSStore : NSObject
+ (instancetype)shared;
/// For tests: keep the library in this folder instead.
+ (void)useRoot:(NSURL *)root;

@property (nonatomic, readonly) NSURL *rootURL;
@property (nonatomic, readonly) BOOL usesGroup;         // NO when the shared container could not be reached

/// Newest first. Reads the folder.
- (NSArray<GSItem *> *)allItems;
- (nullable GSItem *)itemWithID:(NSString *)itemID;
- (BOOL)saveItem:(GSItem *)item;
- (void)deleteItem:(GSItem *)item;
- (long long)totalBytes;

- (NSURL *)gifURLForID:(NSString *)itemID;
- (NSURL *)videoURLForID:(NSString *)itemID;
- (NSURL *)posterURLForID:(NSString *)itemID;

/// Settings both the app and the extension read.
@property (nonatomic) NSInteger preset;
@property (nonatomic) BOOL keyboardAnimates;            // the keyboard plays its clips (default) or shows stills
- (void)announceChange;
@end

NS_ASSUME_NONNULL_END
