#import "GSStore.h"
#import "GSCommon.h"
#include <unistd.h>

NSString *const GSStoreChangedNotification = @"GSStoreChangedNotification";

static NSURL *gRootOverride;

@implementation GSItem

- (instancetype)init {
    if ((self = [super init])) {
        _itemID = @"";
        _kind = @"gif";
        _savedAt = NSDate.date;
        _preset = 1;
    }
    return self;
}

- (NSDictionary *)dictionary {
    NSMutableDictionary *d = [NSMutableDictionary new];
    d[@"id"] = self.itemID;
    d[@"kind"] = self.kind;
    d[@"tweetID"] = self.tweetID;
    d[@"author"] = self.author;
    d[@"text"] = self.text;
    d[@"sourceURL"] = self.sourceURL;
    d[@"label"] = self.label;
    d[@"width"] = @(self.width);
    d[@"height"] = @(self.height);
    d[@"frames"] = @(self.frames);
    d[@"gifDuration"] = @(self.gifDuration);
    d[@"videoDuration"] = @(self.videoDuration);
    d[@"gifBytes"] = @(self.gifBytes);
    d[@"videoBytes"] = @(self.videoBytes);
    d[@"preset"] = @(self.preset);
    d[@"trimmed"] = @(self.trimmed);
    d[@"favorite"] = @(self.favorite);
    d[@"savedAt"] = @(self.savedAt.timeIntervalSince1970);
    return d;
}

static NSString *GSText(id value) {
    return [value isKindOfClass:NSString.class] && [value length] ? value : nil;
}

+ (instancetype)itemWithDictionary:(NSDictionary *)d {
    if (![d isKindOfClass:NSDictionary.class]) return nil;
    NSString *itemID = GSText(d[@"id"]);
    if (!itemID) return nil;
    GSItem *item = [GSItem new];
    item.itemID = itemID;
    item.kind = GSText(d[@"kind"]) ?: @"gif";
    item.tweetID = GSText(d[@"tweetID"]);
    item.author = GSText(d[@"author"]);
    item.text = GSText(d[@"text"]);
    item.sourceURL = GSText(d[@"sourceURL"]);
    item.label = GSText(d[@"label"]);
    item.width = [d[@"width"] integerValue];
    item.height = [d[@"height"] integerValue];
    item.frames = [d[@"frames"] integerValue];
    item.gifDuration = [d[@"gifDuration"] doubleValue];
    item.videoDuration = [d[@"videoDuration"] doubleValue];
    item.gifBytes = [d[@"gifBytes"] longLongValue];
    item.videoBytes = [d[@"videoBytes"] longLongValue];
    item.preset = [d[@"preset"] integerValue];
    item.trimmed = [d[@"trimmed"] boolValue];
    item.favorite = [d[@"favorite"] boolValue];
    item.savedAt = [NSDate dateWithTimeIntervalSince1970:[d[@"savedAt"] doubleValue]];
    return item;
}

- (double)aspect {
    if (self.width <= 0 || self.height <= 0) return 1.0;
    return (double)self.height / (double)self.width;
}

- (NSString *)searchText {
    return [[NSString stringWithFormat:@"%@ %@ %@ %@", self.label ?: @"", self.author ?: @"", self.text ?: @"", self.kind]
            lowercaseString];
}

@end

@implementation GSStore {
    NSURL *_rootURL;
    BOOL _usesGroup;
    NSUserDefaults *_defaults;
}

+ (instancetype)shared {
    static GSStore *store;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ store = [GSStore new]; });
    return store;
}

+ (void)useRoot:(NSURL *)root {
    gRootOverride = root;
    [GSStore.shared locate];
}

- (instancetype)init {
    if ((self = [super init])) [self locate];
    return self;
}

static BOOL GSCanWrite(NSURL *folder) {
    NSFileManager *files = NSFileManager.defaultManager;
    if (![files createDirectoryAtURL:folder withIntermediateDirectories:YES attributes:nil error:NULL]) return NO;
    NSURL *probe = [folder URLByAppendingPathComponent:[NSString stringWithFormat:@".probe-%d", (int)getpid()]];
    BOOL ok = [NSData.data writeToURL:probe atomically:NO];
    [files removeItemAtURL:probe error:NULL];
    return ok;
}

- (void)locate {
    NSFileManager *files = NSFileManager.defaultManager;
    _usesGroup = NO;
    _defaults = nil;
    if (gRootOverride) {
        _rootURL = gRootOverride;
        [files createDirectoryAtURL:_rootURL withIntermediateDirectories:YES attributes:nil error:NULL];
        _defaults = NSUserDefaults.standardUserDefaults;
        return;
    }
    NSURL *group = [files containerURLForSecurityApplicationGroupIdentifier:GSAppGroup];
    NSURL *shared = [group URLByAppendingPathComponent:@"Stash" isDirectory:YES];
    if (shared && GSCanWrite(shared)) {
        _rootURL = shared;
        _usesGroup = YES;
        _defaults = [[NSUserDefaults alloc] initWithSuiteName:GSAppGroup];
        return;
    }
    // Without the shared container the app still works on its own; the share extension then cannot hand over.
    NSURL *documents = [files URLsForDirectory:NSDocumentDirectory inDomains:NSUserDomainMask].firstObject;
    _rootURL = [documents URLByAppendingPathComponent:@"Stash" isDirectory:YES];
    [files createDirectoryAtURL:_rootURL withIntermediateDirectories:YES attributes:nil error:NULL];
    _defaults = NSUserDefaults.standardUserDefaults;
}

- (NSURL *)rootURL { return _rootURL; }
- (BOOL)usesGroup { return _usesGroup; }

- (NSURL *)fileForID:(NSString *)itemID extension:(NSString *)extension {
    return [_rootURL URLByAppendingPathComponent:[NSString stringWithFormat:@"%@.%@", itemID, extension]];
}

- (NSURL *)gifURLForID:(NSString *)itemID { return [self fileForID:itemID extension:@"gif"]; }
- (NSURL *)videoURLForID:(NSString *)itemID { return [self fileForID:itemID extension:@"mp4"]; }
- (NSURL *)posterURLForID:(NSString *)itemID { return [self fileForID:itemID extension:@"jpg"]; }

- (NSArray<GSItem *> *)allItems {
    NSMutableArray<GSItem *> *items = [NSMutableArray new];
    NSArray<NSURL *> *found = [NSFileManager.defaultManager contentsOfDirectoryAtURL:_rootURL includingPropertiesForKeys:nil
                                                                             options:NSDirectoryEnumerationSkipsHiddenFiles error:NULL];
    for (NSURL *url in found) {
        if (![url.pathExtension isEqualToString:@"json"]) continue;
        NSData *data = [NSData dataWithContentsOfURL:url];
        if (!data) continue;
        GSItem *item = [GSItem itemWithDictionary:[NSJSONSerialization JSONObjectWithData:data options:0 error:NULL]];
        // A clip counts once its GIF is there (the extension writes the note last, but be safe).
        if (item && [NSFileManager.defaultManager fileExistsAtPath:[self gifURLForID:item.itemID].path]) [items addObject:item];
    }
    [items sortUsingComparator:^NSComparisonResult(GSItem *a, GSItem *b) {
        NSComparisonResult order = [b.savedAt compare:a.savedAt];
        return order != NSOrderedSame ? order : [b.itemID compare:a.itemID];
    }];
    return items;
}

- (GSItem *)itemWithID:(NSString *)itemID {
    NSData *data = [NSData dataWithContentsOfURL:[self fileForID:itemID extension:@"json"]];
    if (!data) return nil;
    return [GSItem itemWithDictionary:[NSJSONSerialization JSONObjectWithData:data options:0 error:NULL]];
}

- (BOOL)saveItem:(GSItem *)item {
    NSData *data = [NSJSONSerialization dataWithJSONObject:item.dictionary options:NSJSONWritingPrettyPrinted error:NULL];
    BOOL ok = data && [data writeToURL:[self fileForID:item.itemID extension:@"json"] atomically:YES];
    if (ok) [self announceChange];
    return ok;
}

- (void)deleteItem:(GSItem *)item {
    NSFileManager *files = NSFileManager.defaultManager;
    for (NSString *extension in @[@"json", @"gif", @"mp4", @"jpg"]) {
        [files removeItemAtURL:[self fileForID:item.itemID extension:extension] error:NULL];
    }
    [self announceChange];
}

- (long long)totalBytes {
    long long total = 0;
    NSArray<NSURL *> *found = [NSFileManager.defaultManager contentsOfDirectoryAtURL:_rootURL
                                                         includingPropertiesForKeys:@[NSURLFileSizeKey] options:0 error:NULL];
    for (NSURL *url in found) {
        NSNumber *size = nil;
        if ([url getResourceValue:&size forKey:NSURLFileSizeKey error:NULL]) total += size.longLongValue;
    }
    return total;
}

- (NSInteger)preset {
    id stored = [_defaults objectForKey:@"preset"];
    NSInteger value = stored ? [stored integerValue] : 1;
    return MAX(0, MIN(2, value));
}

- (void)setPreset:(NSInteger)preset {
    [_defaults setInteger:MAX(0, MIN(2, preset)) forKey:@"preset"];
}

- (BOOL)keyboardAnimates {
    id stored = [_defaults objectForKey:@"keyboardAnimates"];
    return stored ? [stored boolValue] : YES;
}

- (void)setKeyboardAnimates:(BOOL)animates {
    [_defaults setBool:animates forKey:@"keyboardAnimates"];
}

- (void)announceChange {
    CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(),
                                         (__bridge CFStringRef)GSChangedDarwinName, NULL, NULL, YES);
    dispatch_async(dispatch_get_main_queue(), ^{
        [NSNotificationCenter.defaultCenter postNotificationName:GSStoreChangedNotification object:self];
    });
}

@end
