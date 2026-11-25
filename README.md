# GIF Stash for iPhone

Saves GIFs and short videos from X (Twitter) as real `.gif` files and keeps them in one place, ready to send in
any chat. Built for an iPhone 14 Pro Max on iOS 16.5 and installed with TrollStore.

- **Save without leaving X**: hold a GIF or video, "Share via…", pick **GIF Stash**. A card shows the progress,
  then the saved clip playing, with a "Copy GIF" button; it closes by itself.
- **Or from a link**: copy a post's link, open the app and tap **+** (the app offers it when it sees a link on
  the clipboard). `gifstash://add?url=<link>` does the same from Shortcuts.
- **Library**: a two-column wall of the clips, all playing (hardware-decoded MP4, 120 Hz scrolling, true black).
  Search by account, the post's words, or a name you gave the clip. Star favourites.
- **Send**: tap a clip for Share GIF / Copy GIF / Share as Video, or hold it for the same menu. A clip can also be
  dragged out of the app.
- Each clip is kept twice: the GIF (what chats want) and the original MP4 (smaller and sharper, for apps that
  take video). "Remake GIF" in a clip's More menu makes the GIF again at another quality.

## How a post is read

The public feed that X's own embed widget uses (`cdn.syndication.twimg.com/tweet-result`): no account, no keys.
Posts that X only shows to signed-in accounts (age-restricted, private) cannot be read this way; the app says so.
`…/video/2` in a link picks that one clip of a post; otherwise every GIF and video of the post is saved.

## The GIF

`Shared/GSGifWriter.c` is the app's own encoder (ImageIO keeps every frame in memory until the end, which a share
extension cannot afford). A palette per frame (median cut), and from the second frame on only the pixels that
moved more than a few levels are drawn again; the rest is written as see-through. Settings:

| Quality  | Long side | Frames a second | Notes |
|----------|-----------|-----------------|-------|
| Small    | 320 px    | up to 12        | |
| Balanced | 480 px    | up to 16        | the default; every second frame of a 24 to 30 fps video |
| High     | 640 px    | up to 30        | every frame, smoothed gradients (error diffusion) |

A GIF covers at most the first 20 seconds of a video, and one that comes out above 20 MB is made again one
quality lower.

## Layout

- `Shared/` is compiled into both the app and the share extension: `GSTweet` (links, the feed), `GSImporter`
  (link to saved clip), `GSGifMaker` + `GSGifWriter` (video to GIF), `GSStore` (the library), `GSLoopView`.
- `App/` the app, `Share/` the share extension (`PlugIns/Share.appex`).
- The library lives in the app group container `group.com.cobradarsh.gifstash`, folder `Stash`: per clip
  `<id>.json`, `<id>.gif`, `<id>.mp4`, `<id>.jpg`. No index file, so the app and the extension cannot trip over
  each other.

## Build

No Xcode project. `build.sh` compiles with `xcrun clang`, signs ad hoc with the TrollStore entitlements and zips
`build/GifStash.ipa`; `.github/workflows/build.yml` runs it on every push to `main`, after `tests/run.sh`
(links, the feed's format, the encoder read back with ImageIO, a generated video turned into a GIF at each
quality). A further step saves a real post end to end; it needs the network and does not fail the build.

`tools/phone.sh install <ipa>` installs over SSH.

## Test hooks

Off unless `Library/Caches/gs-diag` exists in the app's data container when the app starts
(`tools/phone.sh enable`). Then `gifstash://_diag/<command>` writes its answer to `Library/Caches/gs-diag.log`:
`state`, `import?url=`, `gifcheck?id=`, `open?id=`, `dismiss`, `copy?id=`, `delete?id=`, `snapshot?name=`.
