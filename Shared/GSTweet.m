#import "GSTweet.h"
#import "GSCommon.h"
#include <float.h>
#include <math.h>
#include <stdlib.h>

@implementation GSMedia
@end

@implementation GSLink
- (BOOL)isUsable {
    return self.tweetID.length > 0 || self.directVideoURL != nil || self.shortURL != nil;
}
@end

static id GSDig(id root, NSArray<NSString *> *path) {
    id value = root;
    for (NSString *key in path) {
        if (![value isKindOfClass:NSDictionary.class]) return nil;
        value = ((NSDictionary *)value)[key];
    }
    return value == NSNull.null ? nil : value;
}

static NSString *GSString(id value) {
    if ([value isKindOfClass:NSString.class]) return value;
    if ([value isKindOfClass:NSNumber.class]) return [value stringValue];
    return nil;
}

static NSArray *GSArray(id value) {
    return [value isKindOfClass:NSArray.class] ? value : @[];
}

static NSRegularExpression *GSRegex(NSString *pattern) {
    return [NSRegularExpression regularExpressionWithPattern:pattern options:NSRegularExpressionCaseInsensitive error:NULL];
}

static NSString *GSGroup(NSTextCheckingResult *match, NSUInteger index, NSString *text) {
    if (!match || index >= match.numberOfRanges) return nil;
    NSRange range = [match rangeAtIndex:index];
    return range.location == NSNotFound ? nil : [text substringWithRange:range];
}

/// JavaScript's Number.prototype.toString(36) for a positive number (V8's digit-by-digit way).
static NSString *GSBase36(double value) {
    static const char digits[] = "0123456789abcdefghijklmnopqrstuvwxyz";
    double integer = floor(value);
    double fraction = value - integer;
    double delta = 0.5 * (nextafter(value, INFINITY) - value);
    if (delta < DBL_TRUE_MIN) delta = DBL_TRUE_MIN;
    NSMutableString *tail = [NSMutableString new];
    if (fraction >= delta) {
        do {
            fraction *= 36;
            delta *= 36;
            int digit = (int)fraction;
            [tail appendFormat:@"%c", digits[digit]];
            fraction -= digit;
            if (fraction > 0.5 || (fraction == 0.5 && (digit & 1))) {
                if (fraction + delta > 1) {
                    // Round up, carrying into the digits before.
                    while (YES) {
                        if (tail.length == 0) { integer += 1; break; }
                        unichar last = [tail characterAtIndex:tail.length - 1];
                        [tail deleteCharactersInRange:NSMakeRange(tail.length - 1, 1)];
                        const char *at = strchr(digits, (char)last);
                        int d = at ? (int)(at - digits) : 0;
                        if (d + 1 < 36) { [tail appendFormat:@"%c", digits[d + 1]]; break; }
                    }
                    break;
                }
            }
        } while (fraction >= delta);
    }
    NSMutableString *head = [NSMutableString new];
    double rest = integer;
    do {
        double r = fmod(rest, 36);
        [head insertString:[NSString stringWithFormat:@"%c", digits[(int)r]] atIndex:0];
        rest = (rest - r) / 36;
    } while (rest > 0);
    return tail.length ? [NSString stringWithFormat:@"%@.%@", head, tail] : head;
}

@implementation GSTweet

+ (GSLink *)linkInText:(NSString *)text {
    GSLink *link = [GSLink new];
    if (text.length == 0) return link;
    NSRange all = NSMakeRange(0, text.length);

    static NSRegularExpression *status, *shortLink, *anyURL;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        status = GSRegex(@"(?:^|[^\\w.-])(?:https?://)?(?:[\\w-]+\\.)*"
                         @"(?:twitter\\.com|x\\.com|fxtwitter\\.com|vxtwitter\\.com|fixupx\\.com|fixvx\\.com|twittpr\\.com|nitter\\.net)"
                         @"/(?:#!/)?(?:\\w+|i/web)/status(?:es)?/(\\d{5,25})(?:/(?:video|photo)/(\\d))?");
        shortLink = GSRegex(@"https?://t\\.co/\\w+");
        anyURL = GSRegex(@"https?://[^\\s<>\"']+");
    });

    NSTextCheckingResult *match = [status firstMatchInString:text options:0 range:all];
    if (match) {
        link.tweetID = GSGroup(match, 1, text);
        link.mediaPosition = [GSGroup(match, 2, text) integerValue];
        return link;
    }
    for (NSTextCheckingResult *found in [anyURL matchesInString:text options:0 range:all]) {
        NSString *raw = [text substringWithRange:found.range];
        // A sentence around the link can leave its full stop or bracket on the end.
        while (raw.length && [@".,;:!?)]}'\"" containsString:[raw substringFromIndex:raw.length - 1]]) {
            raw = [raw substringToIndex:raw.length - 1];
        }
        NSURL *url = [NSURL URLWithString:raw];
        NSString *extension = url.pathExtension.lowercaseString;
        if (url.host.length && ([extension isEqualToString:@"mp4"] || [extension isEqualToString:@"m4v"]
                                || [extension isEqualToString:@"mov"])) {
            link.directVideoURL = url;
            return link;
        }
    }
    match = [shortLink firstMatchInString:text options:0 range:all];
    if (match) link.shortURL = [NSURL URLWithString:[text substringWithRange:match.range]];
    return link;
}

+ (NSString *)embedTokenForID:(NSString *)tweetID {
    double number = strtod(tweetID.UTF8String ?: "0", NULL);
    if (!(number > 0)) return @"a";
    NSString *raw = GSBase36((number / 1e15) * M_PI);
    NSString *token = [[raw stringByReplacingOccurrencesOfString:@"0" withString:@""]
                       stringByReplacingOccurrencesOfString:@"." withString:@""];
    return token.length ? token : @"a";
}

+ (NSURL *)embedURLForID:(NSString *)tweetID {
    return [NSURL URLWithString:[NSString stringWithFormat:@"https://cdn.syndication.twimg.com/tweet-result?id=%@&token=%@&lang=en",
                                 tweetID, [self embedTokenForID:tweetID]]];
}

+ (NSURL *)pageURLForID:(NSString *)tweetID {
    return [NSURL URLWithString:[@"https://x.com/i/status/" stringByAppendingString:tweetID]];
}

+ (void)sizeOf:(GSMedia *)media fromURL:(NSString *)url {
    static NSRegularExpression *dims;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ dims = GSRegex(@"/(\\d{2,5})x(\\d{2,5})/"); });
    NSTextCheckingResult *match = [dims firstMatchInString:url options:0 range:NSMakeRange(0, url.length)];
    if (match) {
        media.width = [GSGroup(match, 1, url) integerValue];
        media.height = [GSGroup(match, 2, url) integerValue];
    }
}

/// The MP4 to take from a list of {url, bitrate}: the best one that is not needlessly large.
+ (NSString *)pickVariant:(NSArray<NSDictionary *> *)variants {
    NSString *best = nil, *smallest = nil;
    double bestRate = -1, smallestRate = DBL_MAX;
    for (NSDictionary *variant in variants) {
        NSString *url = variant[@"url"];
        double rate = [variant[@"bitrate"] doubleValue];
        GSMedia *probe = [GSMedia new];
        [self sizeOf:probe fromURL:url];
        if (rate < smallestRate) { smallestRate = rate; smallest = url; }
        if (MAX(probe.width, probe.height) > 1280) continue;
        if (rate > bestRate) { bestRate = rate; best = url; }
    }
    return best ?: smallest;
}

+ (GSMedia *)mediaFromDetail:(NSDictionary *)detail position:(NSInteger)position {
    NSString *type = GSString(detail[@"type"]);
    BOOL isGIF = [type isEqualToString:@"animated_gif"];
    if (!isGIF && ![type isEqualToString:@"video"]) return nil;
    NSMutableArray<NSDictionary *> *variants = [NSMutableArray new];
    for (id variant in GSArray(GSDig(detail, @[@"video_info", @"variants"]))) {
        NSString *url = GSString(GSDig(variant, @[@"url"]));
        if (!url || ![GSString(GSDig(variant, @[@"content_type"])) isEqualToString:@"video/mp4"]) continue;
        [variants addObject:@{@"url": url, @"bitrate": GSDig(variant, @[@"bitrate"]) ?: @0}];
    }
    NSString *chosen = [self pickVariant:variants];
    NSURL *videoURL = chosen ? [NSURL URLWithString:chosen] : nil;
    if (!videoURL) return nil;
    GSMedia *media = [GSMedia new];
    media.kind = isGIF ? @"gif" : @"video";
    media.videoURL = videoURL;
    media.position = position;
    NSString *poster = GSString(detail[@"media_url_https"]);
    if (poster) media.posterURL = [NSURL URLWithString:poster];
    media.width = [GSDig(detail, @[@"original_info", @"width"]) integerValue];
    media.height = [GSDig(detail, @[@"original_info", @"height"]) integerValue];
    [self sizeOf:media fromURL:chosen];
    media.duration = [GSDig(detail, @[@"video_info", @"duration_millis"]) doubleValue] / 1000.0;
    return media;
}

+ (NSArray<GSMedia *> *)mediaFromDetails:(NSArray *)details {
    NSMutableArray<GSMedia *> *found = [NSMutableArray new];
    NSInteger position = 0;
    for (id detail in details) {
        position++;
        if (![detail isKindOfClass:NSDictionary.class]) continue;
        GSMedia *media = [self mediaFromDetail:detail position:position];
        if (media) [found addObject:media];
    }
    return found;
}

+ (GSTweet *)tweetFromEmbedJSON:(id)json tweetID:(NSString *)tweetID error:(NSError **)error {
    if (![json isKindOfClass:NSDictionary.class] || [(NSDictionary *)json count] == 0) {
        if (error) *error = GSMakeError(GSErrorRestricted, @"X did not return this post. It may be deleted, private or age-restricted.");
        return nil;
    }
    NSDictionary *root = json;
    if ([GSString(root[@"__typename"]) isEqualToString:@"TweetTombstone"]) {
        NSString *why = GSString(GSDig(root, @[@"tombstone", @"text", @"text"]));
        if (error) *error = GSMakeError(GSErrorRestricted, why.length ? [@"X says: " stringByAppendingString:why]
                                        : @"X only shows this post to signed-in accounts (age-restricted or private).");
        return nil;
    }

    GSTweet *tweet = [GSTweet new];
    tweet.tweetID = GSString(root[@"id_str"]) ?: tweetID;
    tweet.author = GSString(GSDig(root, @[@"user", @"screen_name"]));
    NSString *text = GSString(root[@"text"]);
    if (text) {
        // X appends a t.co link for the media: not part of what was written.
        NSRegularExpression *tail = GSRegex(@"\\s*https://t\\.co/\\w+\\s*$");
        text = [tail stringByReplacingMatchesInString:text options:0 range:NSMakeRange(0, text.length) withTemplate:@""];
        text = [text stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
        tweet.text = text.length ? text : nil;
    }

    NSArray<GSMedia *> *media = [self mediaFromDetails:GSArray(root[@"mediaDetails"])];
    if (media.count == 0) {
        // A quote of a post that has the GIF.
        media = [self mediaFromDetails:GSArray(GSDig(root, @[@"quoted_tweet", @"mediaDetails"]))];
        for (GSMedia *item in media) item.position = 0;
    }
    if (media.count == 0) {
        // The feed's own "video" block, which some posts have instead.
        NSMutableArray<NSDictionary *> *variants = [NSMutableArray new];
        for (id variant in GSArray(GSDig(root, @[@"video", @"variants"]))) {
            NSString *url = GSString(GSDig(variant, @[@"src"]));
            if (!url || ![GSString(GSDig(variant, @[@"type"])) isEqualToString:@"video/mp4"]) continue;
            GSMedia *probe = [GSMedia new];
            [self sizeOf:probe fromURL:url];
            [variants addObject:@{@"url": url, @"bitrate": @(probe.width * probe.height)}];
        }
        NSString *chosen = [self pickVariant:variants];
        NSURL *videoURL = chosen ? [NSURL URLWithString:chosen] : nil;
        if (videoURL) {
            GSMedia *item = [GSMedia new];
            item.kind = [GSString(GSDig(root, @[@"video", @"contentType"])) isEqualToString:@"gif"] ? @"gif" : @"video";
            item.videoURL = videoURL;
            NSString *poster = GSString(GSDig(root, @[@"video", @"poster"]));
            if (poster) item.posterURL = [NSURL URLWithString:poster];
            [self sizeOf:item fromURL:chosen];
            item.duration = [GSDig(root, @[@"video", @"durationMs"]) doubleValue] / 1000.0;
            media = @[item];
        }
    }
    tweet.media = media;
    if (media.count == 0) {
        if (error) *error = GSMakeError(GSErrorNoMedia, @"This post has no GIF or video.");
        return nil;
    }
    return tweet;
}

@end
