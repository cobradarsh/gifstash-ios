#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// One GIF or video of a post.
@interface GSMedia : NSObject
@property (nonatomic, copy) NSString *kind;             // "gif" or "video"
@property (nonatomic, strong) NSURL *videoURL;          // an MP4 (X stores its GIFs as MP4 too)
@property (nonatomic, strong, nullable) NSURL *posterURL;
@property (nonatomic) NSInteger width;
@property (nonatomic) NSInteger height;
@property (nonatomic) double duration;                  // seconds, 0 when not known
@property (nonatomic) NSInteger position;               // 1-based place among the post's media
@end

/// A link the user shared or copied, taken apart.
@interface GSLink : NSObject
@property (nonatomic, copy, nullable) NSString *tweetID;
@property (nonatomic) NSInteger mediaPosition;          // from ".../video/2", else 0
@property (nonatomic, strong, nullable) NSURL *directVideoURL;
@property (nonatomic, strong, nullable) NSURL *shortURL;   // t.co, still to be followed
@property (nonatomic, readonly) BOOL isUsable;
@end

/// X (Twitter): reads links, and the public feed that X's own embed widget uses (no account needed).
@interface GSTweet : NSObject
@property (nonatomic, copy) NSString *tweetID;
@property (nonatomic, copy, nullable) NSString *author;         // screen name, without the @
@property (nonatomic, copy, nullable) NSString *text;
@property (nonatomic, copy) NSArray<GSMedia *> *media;          // GIFs and videos only

+ (GSLink *)linkInText:(nullable NSString *)text;

/// The feed's `token`, as the widget works it out: ((id / 1e15) * pi) in base 36 without zeros and the dot.
+ (NSString *)embedTokenForID:(NSString *)tweetID;
+ (NSURL *)embedURLForID:(NSString *)tweetID;
+ (NSURL *)pageURLForID:(NSString *)tweetID;

+ (nullable GSTweet *)tweetFromEmbedJSON:(id)json tweetID:(NSString *)tweetID error:(NSError **)error;
@end

NS_ASSUME_NONNULL_END
