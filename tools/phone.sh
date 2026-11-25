#!/bin/bash
# Drives GIF Stash on a jailbroken iPhone over SSH (host alias "iphone-root", TrollStore installed).
#
#   phone.sh install <GifStash.ipa>   copy the IPA over and install it with TrollStore's helper
#   phone.sh container                print the app's data container
#   phone.sh group                    print the shared (app group) container, where the library is
#   phone.sh enable | disable         create / remove the marker file that turns the test hooks on
#   phone.sh diag <command?query>     run a test hook, e.g. `diag state` (the phone must be unlocked)
#   phone.sh log [n]                  last n lines of the hook log (default 40)
#   phone.sh snap <name>              picture of the app window, copied to ./shots/<name>.png
set -u
SSH="${GIFSTASH_SSH:-ssh -o BatchMode=yes -o ConnectTimeout=12 -o ServerAliveInterval=15 ${GIFSTASH_PHONE:-iphone-root}}"
BID=com.cobradarsh.gifstash
GROUP=group.com.cobradarsh.gifstash
ROOT="${GIFSTASH_ROOT-/rootfs}"    # the real file system, as a RootHide shell sees it; "" on other jailbreaks
OUT="${GIFSTASH_SHOTS:-./shots}"
META=.com.apple.mobile_container_manager.metadata.plist

container() {
    # The share extension's container names the app too (com.cobradarsh.gifstash.share): take the exact one.
    $SSH "for f in $ROOT/var/mobile/Containers/Data/Application/*/$META; do \
            if grep -q -a '$BID' \"\$f\" && ! grep -q -a '$BID\.share' \"\$f\"; then dirname \"\$f\"; break; fi; done"
}
group() {
    $SSH "grep -l -a '$GROUP' $ROOT/var/mobile/Containers/Shared/AppGroup/*/$META 2>/dev/null | head -1 | sed 's#/$META##'"
}

case "${1:-}" in
    install)
        [ -f "${2:-}" ] || { echo "usage: phone.sh install <GifStash.ipa>"; exit 2; }
        $SSH "cat > $ROOT/var/tmp/GifStash.ipa" < "$2" || exit 1
        # TrollStore's helper is not a jailbreak binary, so it gets the path as the real file system has it.
        $SSH "HELPER=\$(ls -d $ROOT/var/containers/Bundle/Application/*/TrollStore.app/trollstorehelper | head -1); \
              \"\$HELPER\" install /var/tmp/GifStash.ipa 2>&1 | tail -3; echo helper-exit=\$?; \
              rm -f $ROOT/var/tmp/GifStash.ipa; ls -d $ROOT/var/containers/Bundle/Application/*/GifStash.app"
        ;;
    container) container ;;
    group) group ;;
    enable)
        C="$(container)"; [ -n "$C" ] || { echo "no data container yet: open the app once first"; exit 1; }
        $SSH "mkdir -p '$C/Library/Caches' && touch '$C/Library/Caches/gs-diag' && ls '$C/Library/Caches/'"
        ;;
    disable)
        C="$(container)"; [ -n "$C" ] || exit 1
        $SSH "cd '$C/Library/Caches' && rm -f gs-diag gs-diag.log gs-diag-cmd; ls"
        ;;
    diag) $SSH "uiopen 'gifstash://_diag/$2'; echo uiopen-exit=\$?" ;;
    log) C="$(container)"; $SSH "tail -n ${2:-40} '$C/Library/Caches/gs-diag.log' 2>/dev/null" ;;
    snap)
        C="$(container)"; mkdir -p "$OUT"
        $SSH "rm -f '$C/Library/Caches/gs-snap-$2.png'; uiopen 'gifstash://_diag/snapshot?name=$2'" >/dev/null
        sleep "${3:-3}"
        $SSH "cat '$C/Library/Caches/gs-snap-$2.png'" > "$OUT/$2.png" && $SSH "rm -f '$C/Library/Caches/gs-snap-$2.png'"
        ls -la "$OUT/$2.png"
        ;;
    *) sed -n '2,10p' "$0"; exit 2 ;;
esac
