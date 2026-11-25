#import "GSImporter.h"
#import "GSCommon.h"
#import "GSGifMaker.h"
#import "GSTweet.h"

static NSString *const kUserAgent = @"Mozilla/5.0 (iPhone; CPU iPhone OS 16_5 like Mac OS X) AppleWebKit/605.1.15 "
                                    @"(KHTML, like Gecko) Version/16.5 Mobile/15E148 Safari/604.1";
static const long long kLargeGIF = 20LL * 1000 * 1000;      // above this a smaller setting is tried

@implementation GSImporter {
    NSURLSession *_session;
    dispatch_queue_t _queue;
    BOOL _busy;
}

- (instancetype)init {
    if ((self = [super init])) {
        NSURLSessionConfiguration *configuration = NSURLSessionConfiguration.ephemeralSessionConfiguration;
        configuration.timeoutIntervalForRequest = 25;
        configuration.timeoutIntervalForResource = 180;
        configuration.HTTPAdditionalHeaders = @{@"User-Agent": kUserAgent, @"Accept-Language": @"en"};
        _session = [NSURLSession sessionWithConfiguration:configuration];
        _queue = dispatch_queue_create("com.cobradarsh.gifstash.import", DISPATCH_QUEUE_SERIAL);
    }
    return self;
}

- (BOOL)isBusy { return _busy; }

#pragma mark - Network (called on the import queue)

- (NSData *)fetch:(NSURLRequest *)request response:(NSHTTPURLResponse **)response error:(NSError **)error {
    dispatch_semaphore_t done = dispatch_semaphore_create(0);
    __block NSData *body = nil;
    __block NSURLResponse *answer = nil;
    __block NSError *problem = nil;
    [[_session dataTaskWithRequest:request completionHandler:^(NSData *data, NSURLResponse *r, NSError *e) {
        body = data;
        answer = r;
        problem = e;
        dispatch_semaphore_signal(done);
    }] resume];
    dispatch_semaphore_wait(done, DISPATCH_TIME_FOREVER);
    if (response) *response = [answer isKindOfClass:NSHTTPURLResponse.class] ? (NSHTTPURLResponse *)answer : nil;
    if (error) *error = problem;
    return problem ? nil : body;
}

- (BOOL)download:(NSURL *)url to:(NSURL *)destination progress:(void (^)(double))progress error:(NSError **)error {
    dispatch_semaphore_t done = dispatch_semaphore_create(0);
    __block NSError *problem = nil;
    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:url];
    [request setValue:@"https://x.com/" forHTTPHeaderField:@"Referer"];
    NSURLSessionDownloadTask *task = [_session downloadTaskWithRequest:request
                                                     completionHandler:^(NSURL *location, NSURLResponse *r, NSError *e) {
        NSInteger status = [r isKindOfClass:NSHTTPURLResponse.class] ? ((NSHTTPURLResponse *)r).statusCode : 200;
        if (e) {
            problem = e;
        } else if (status >= 400 || !location) {
            problem = GSMakeError(GSErrorNetwork, [NSString stringWithFormat:@"The video could not be downloaded (answer %ld).", (long)status]);
        } else {
            NSFileManager *files = NSFileManager.defaultManager;
            [files removeItemAtURL:destination error:NULL];
            NSError *moveError = nil;
            if (![files moveItemAtURL:location toURL:destination error:&moveError]) {
                problem = GSMakeError(GSErrorStorage, moveError.localizedDescription ?: @"The video could not be stored.");
            }
        }
        dispatch_semaphore_signal(done);
    }];
    [task resume];
    while (dispatch_semaphore_wait(done, dispatch_time(DISPATCH_TIME_NOW, 120 * NSEC_PER_MSEC)) != 0) {
        const int64_t expected = task.countOfBytesExpectedToReceive;
        if (progress && expected > 0) progress((double)task.countOfBytesReceived / (double)expected);
    }
    if (error) *error = problem;
    return problem == nil;
}

static NSError *GSNetworkError(NSError *underlying) {
    if ([underlying.domain isEqualToString:GSErrorDomain]) return underlying;
    return GSMakeError(GSErrorNetwork, [NSString stringWithFormat:@"No answer from X: %@",
                                         underlying.localizedDescription ?: @"the connection failed."]);
}

static NSString *GSHash(NSString *text) {
    uint64_t hash = 1469598103934665603ULL;
    const char *bytes = text.UTF8String ?: "";
    for (const char *p = bytes; *p; p++) {
        hash ^= (uint8_t)*p;
        hash *= 1099511628211ULL;
    }
    return [NSString stringWithFormat:@"%016llx", (unsigned long long)hash];
}

#pragma mark - The work

- (NSArray<GSItem *> *)run:(NSString *)text progress:(GSImportProgress)progress error:(NSError **)error {
    GSStore *store = GSStore.shared;
    GSLink *link = [GSTweet linkInText:text];

    if (!link.tweetID && !link.directVideoURL && link.shortURL) {
        // A t.co link: see where it leads.
        progress(@"Following the link…", -1);
        NSHTTPURLResponse *response = nil;
        NSError *problem = nil;
        NSData *body = [self fetch:[NSURLRequest requestWithURL:link.shortURL] response:&response error:&problem];
        if (problem) { *error = GSNetworkError(problem); return nil; }
        GSLink *landed = [GSTweet linkInText:response.URL.absoluteString];
        if (!landed.tweetID && !landed.directVideoURL && body.length) {
            NSString *page = [[NSString alloc] initWithData:body encoding:NSUTF8StringEncoding];
            GSLink *inPage = [GSTweet linkInText:page];
            if (inPage.tweetID) landed = inPage;
        }
        link = landed;
    }
    if (!link.tweetID && !link.directVideoURL) {
        *error = GSMakeError(GSErrorNoLink, @"That is not a link to a post on X (Twitter).");
        return nil;
    }

    NSMutableArray<GSMedia *> *wanted = [NSMutableArray new];
    GSTweet *tweet = nil;
    if (link.tweetID) {
        progress(@"Reading the post…", -1);
        NSHTTPURLResponse *response = nil;
        NSError *problem = nil;
        NSData *body = [self fetch:[NSURLRequest requestWithURL:[GSTweet embedURLForID:link.tweetID]] response:&response error:&problem];
        if (problem) { *error = GSNetworkError(problem); return nil; }
        if (response.statusCode == 404) {
            *error = GSMakeError(GSErrorRestricted, @"X does not show this post without an account. It may be deleted, private or age-restricted.");
            return nil;
        }
        if (response.statusCode >= 400) {
            *error = GSMakeError(GSErrorNetwork, [NSString stringWithFormat:@"X answered with error %ld. Try again in a moment.", (long)response.statusCode]);
            return nil;
        }
        id json = body.length ? [NSJSONSerialization JSONObjectWithData:body options:0 error:NULL] : nil;
        tweet = [GSTweet tweetFromEmbedJSON:json tweetID:link.tweetID error:error];
        if (!tweet) return nil;
        // ".../video/2" names one clip of the post; otherwise all of them.
        for (GSMedia *media in tweet.media) {
            if (link.mediaPosition > 0 && media.position == link.mediaPosition) [wanted addObject:media];
        }
        if (wanted.count == 0) [wanted addObjectsFromArray:tweet.media];
    } else {
        GSMedia *media = [GSMedia new];
        media.videoURL = link.directVideoURL;
        media.kind = [link.directVideoURL.path containsString:@"tweet_video"] ? @"gif" : @"video";
        [wanted addObject:media];
    }

    NSMutableArray<GSItem *> *saved = [NSMutableArray new];
    NSError *lastProblem = nil;
    NSUInteger number = 0;
    for (GSMedia *media in wanted) {
        number++;
        NSString *suffix = wanted.count > 1 ? [NSString stringWithFormat:@" %lu of %lu", (unsigned long)number, (unsigned long)wanted.count] : @"";
        NSString *itemID = link.tweetID
            ? [NSString stringWithFormat:@"%@-%ld", link.tweetID, (long)MAX(1, media.position ?: (NSInteger)number)]
            : [@"d-" stringByAppendingString:GSHash(media.videoURL.absoluteString)];
        NSURL *videoURL = [store videoURLForID:itemID];
        NSURL *gifURL = [store gifURLForID:itemID];
        // The working copies keep their endings: the system tells a video by its file name.
        NSURL *partVideo = [store.rootURL URLByAppendingPathComponent:[itemID stringByAppendingString:@".part.mp4"]];
        NSURL *partGIF = [store.rootURL URLByAppendingPathComponent:[itemID stringByAppendingString:@".part.gif"]];
        NSFileManager *files = NSFileManager.defaultManager;

        NSString *downloading = [NSString stringWithFormat:@"Downloading%@…", suffix];
        progress(downloading, 0);
        NSError *problem = nil;
        if (![self download:media.videoURL to:partVideo progress:^(double fraction) { progress(downloading, fraction * 0.35); } error:&problem]) {
            lastProblem = GSNetworkError(problem);
            continue;
        }

        NSString *making = [NSString stringWithFormat:@"Making the GIF%@…", suffix];
        progress(making, 0.35);
        NSInteger preset = store.preset;
        GSGifResult *result = nil;
        while (YES) {
            result = [GSGifMaker makeGIFAtURL:partGIF fromVideo:partVideo preset:(GSGifPreset)preset
                                    posterURL:[store posterURLForID:itemID]
                                     progress:^(double fraction) { progress(making, 0.35 + fraction * 0.65); }
                                        error:&problem];
            // A very large GIF is slow to send anywhere: step down once or twice.
            if (result && result.bytes > kLargeGIF && preset > GSGifPresetSmall) { preset--; continue; }
            break;
        }
        if (!result) {
            [files removeItemAtURL:partVideo error:NULL];
            [files removeItemAtURL:partGIF error:NULL];
            lastProblem = problem;
            continue;
        }
        [files removeItemAtURL:videoURL error:NULL];
        [files removeItemAtURL:gifURL error:NULL];
        if (![files moveItemAtURL:partVideo toURL:videoURL error:&problem] || ![files moveItemAtURL:partGIF toURL:gifURL error:&problem]) {
            lastProblem = GSMakeError(GSErrorStorage, problem.localizedDescription ?: @"The clip could not be stored.");
            continue;
        }

        GSItem *old = [store itemWithID:itemID];
        GSItem *item = [GSItem new];
        item.itemID = itemID;
        item.kind = media.kind ?: @"video";
        item.tweetID = link.tweetID;
        item.author = tweet.author;
        item.text = tweet.text;
        item.sourceURL = link.tweetID ? [GSTweet pageURLForID:link.tweetID].absoluteString : media.videoURL.absoluteString;
        item.label = old.label;
        item.favorite = old.favorite;
        item.width = result.width;
        item.height = result.height;
        item.frames = result.frames;
        item.gifDuration = result.duration;
        item.videoDuration = result.videoDuration;
        item.gifBytes = result.bytes;
        NSNumber *videoSize = nil;
        [videoURL getResourceValue:&videoSize forKey:NSURLFileSizeKey error:NULL];
        item.videoBytes = videoSize.longLongValue;
        item.preset = preset;
        item.trimmed = result.trimmed;
        item.savedAt = NSDate.date;
        if (![store saveItem:item]) {
            lastProblem = GSMakeError(GSErrorStorage, @"The clip could not be added to the library.");
            continue;
        }
        [saved addObject:item];
    }
    if (saved.count == 0) {
        *error = lastProblem ?: GSMakeError(GSErrorNoMedia, @"Nothing could be saved from this post.");
        return nil;
    }
    return saved;
}

- (void)importText:(NSString *)text progress:(GSImportProgress)progress
        completion:(void (^)(NSArray<GSItem *> *, NSError *))completion {
    _busy = YES;
    GSImportProgress report = ^(NSString *stage, double fraction) {
        if (!progress) return;
        dispatch_async(dispatch_get_main_queue(), ^{ progress(stage, fraction); });
    };
    dispatch_async(_queue, ^{
        NSError *error = nil;
        NSArray<GSItem *> *items = [self run:text ?: @"" progress:report error:&error];
        dispatch_async(dispatch_get_main_queue(), ^{
            self->_busy = NO;
            completion(items ?: @[], items.count ? nil : (error ?: GSMakeError(GSErrorNoMedia, @"Nothing could be saved.")));
        });
    });
}

@end
