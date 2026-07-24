#!/bin/sh
# Encode a single recording track to a real file, used by cook.sh to encode
# zip-family downloads in parallel (one invocation per track, fanned out with
# `xargs -P`). The surrounding context is passed via environment variables
# exported by cook.sh: SCRIPTBASE, ext, OUTDIR, DEF_TIMEOUT, NICE, FILTER,
# ENCODE, CODECS, STREAM_NOS.
#
# Usage: encode-track.sh <ID> <track-number>

trap '' HUP
trap '' INT

timeout() {
    /usr/bin/timeout -k 5 "$@"
}

ID="$1"
c="$2"

[ "$ID" ] || exit 1
[ "$c" ] || exit 1

cd "$SCRIPTBASE/rec" || exit 1

O_USER="`$SCRIPTBASE/cook/userinfo.js $ID $c`"
[ "$O_USER" ] || unset O_USER
O_FN="$c${O_USER+-}$O_USER.$ext"
O_FFN="$OUTDIR/$O_FN"

T_DURATION=`timeout $DEF_TIMEOUT $NICE "$SCRIPTBASE/cook/oggduration" $c < $ID.ogg.data`
sno=`echo "$STREAM_NOS" | sed -n "$c"p`
CODEC=`echo "$CODECS" | sed -n "$c"p`
[ "$CODEC" = "opus" ] && CODEC=libopus

timeout $DEF_TIMEOUT cat $ID.ogg.header1 $ID.ogg.header2 $ID.ogg.data \
    $ID.ogg.header1 $ID.ogg.header2 $ID.ogg.data |
    timeout $DEF_TIMEOUT $NICE "$SCRIPTBASE/cook/oggcorrect" $sno |
    timeout $DEF_TIMEOUT $NICE ffmpeg -codec $CODEC -copyts -i - \
    -af "$FILTER" \
    -flags bitexact -f wav - |
    timeout $DEF_TIMEOUT $NICE "$SCRIPTBASE/cook/wavduration" "$T_DURATION" |
    (
        timeout $DEF_TIMEOUT $NICE $ENCODE > "$O_FFN";
        cat > /dev/null
    )
