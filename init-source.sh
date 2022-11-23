#!/bin/bash
set -e
set +x

FFMPEG_GIT="https://github.com/FFmpeg/FFmpeg.git"
FFMPEG_COMMIT="b655beb025cb54ba19cad89e731990910643f208"
FFMPEG_NAME="ffmpeg"
FFMPEG_BRANCH="release/5.0"
FFMPEG_VERSION="5.0.1"

BUILD_SRC=$(pwd)/src

if [[ ! -d $BUILD_SRC ]]; then
    mkdir -p $BUILD_SRC
    git clone $FFMPEG_GIT $BUILD_SRC/$FFMPEG_NAME --depth 1
    cd $BUILD_SRC/$FFMPEG_NAME
    git fetch --depth 1 origin $FFMPEG_COMMIT
    git checkout $FFMPEG_COMMIT
fi
