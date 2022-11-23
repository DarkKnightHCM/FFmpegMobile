#!/bin/bash
set -e
set +x

show_usage() {
    echo ""
    echo "'"$1"' builds FFmpeg library for Android platform."
    echo ""
    echo "Usage: ./"$1" [ABI]"
    echo ""
    echo "[ABI] = [arm64-v8a, armeabi-v7a, x86_64]"
}

# check number of input params
if [[ ! $# -eq 1 ]]; then
    COMMAND=$(echo $0 | sed -e 's/\.\///g')
    show_usage $COMMAND
    exit 1
fi

case $1 in
    arm64-v8a|armeabi-v7a|x86_64)
        # OK
    ;;
    *)
        COMMAND=$(echo $0 | sed -e 's/\.\///g')
        show_usage $COMMAND
        exit 1
    ;;
esac

LIBRARY_ARCH=$1
LIBRARY_NAME="ffmpeg"
BUILD_ROOT="$(pwd)"
BUILD_SRC=$BUILD_ROOT/src
BUILD_LIB=$BUILD_ROOT/libs
BUILD_TOOL=$BUILD_ROOT/tools
BUILD_API=21 # setup API Level
BUILD_STRIP="yes"

ENABLE_ZLIB=1
ENABLE_MEDIACODEC=1
# ======================
# [*] Check Android NDK 
# ======================
UNAME_S=$(uname -s)
echo "Running on $(uname -sm)"

# checking ANDROID_NDK exist or not
if [[ -z "$ANDROID_NDK" ]]; then
    echo "You must define ANDROID_NDK before starting."
    echo "They must point to your NDK directories."
    echo ""
    exit 1
fi

# ==============================
# [*] Check Android NDK Version 
# ==============================
export NDK_REL=$(grep -o '^Pkg\.Revision.*=[0-9]*.*' $ANDROID_NDK/source.properties 2>/dev/null | sed 's/[[:space:]]*//g' | cut -d "=" -f 2)
export NDK_VER=$(echo $NDK_REL | cut -d "." -f 1)
case "$NDK_REL" in
    20*|21*|22*)
        if test -d ${ANDROID_NDK}/toolchains/aarch64-linux-android-4.9
        then
            echo "NDKr$NDK_REL detected"
        else
            echo "Can not detect current NDK version !!!"
            exit 1
        fi
    ;;
    *)
        echo "You must use the NDK 20b or above !!!"
        exit 1
    ;;
esac

# ==============================
# [*] Setup MAKE_FLAG to increase building speed
# ==============================
MAKE_FLAG=
case "$UNAME_S" in
    Darwin)
        export MAKE_FLAG=-j$(sysctl -n hw.physicalcpu)
    ;;
    Linux*)
        export MAKE_FLAG=-j`nproc`
    ;;
    *)
        export MAKE_FLAG=
    ;;
esac

# ==============================
# [*] Check FFmpeg Source
# ==============================


# ==================================================
# process cleaning previous build
if [[ $LIBRARY_ARCH == "clean" ]]; then
    return
fi

# ==================================================
# prepare toolchain
# ==================================================
# setup toolchain's host, library's host
TOOLCHAIN_HOST=
HOST_OS=$(uname -s)
case ${HOST_OS} in
    Darwin) HOST_OS=darwin;;
    Linux) HOST_OS=linux;;
    FreeBsd) HOST_OS=freebsd;;
    CYGWIN*|*_NT-*) HOST_OS=cygwin;;
esac

HOST_ARCH=$(uname -m)
case ${HOST_ARCH} in
    i?86) HOST_ARCH=x86;;
    x86_64|arm64|amd64) HOST_ARCH=x86_64;;
esac

export TOOLCHAIN_HOST="${HOST_OS}-${HOST_ARCH}"
export PATH=$PATH:${ANDROID_NDK}/toolchains/llvm/prebuilt/$TOOLCHAIN_HOST/bin
HOST=
TARGET_HOST=
LIBRARY_HOST=
TARGET_BUILD=
case $LIBRARY_ARCH in
    armeabi-v7a | armeabi-v7a-neon)
        HOST="arm-linux-androideabi"
        TARGET_HOST="armv7a-linux-androideabi$BUILD_API"
        LIBRARY_HOST="arm-linux-androideabi"
        TARGET_BUILD="arm"
    ;;
    arm64-v8a)
        HOST="aarch64-linux-android"
        TARGET_HOST="aarch64-linux-android$BUILD_API"
        LIBRARY_HOST="aarch64-linux-android"
        TARGET_BUILD="arm64"
    ;;
    x86)
        HOST="i686-linux-android"
        TARGET_HOST="i686-linux-android$BUILD_API"
        LIBRARY_HOST="i686-linux-android"
        TARGET_BUILD="x86"
    ;;
    x86_64)
        HOST="x86_64-linux-android"
        TARGET_HOST="x86_64-linux-android$BUILD_API"
        LIBRARY_HOST="x86_64-linux-android"
        TARGET_BUILD="x86_64"
    ;;
    *)
        echo "This $LIBRARY_ARCH does not support!!!"
        exit 1
    ;;
esac

export AR="${HOST}-ar"
export CC="${TARGET_HOST}-clang"
export CPP="${TARGET_HOST}-clang -E"
export CXX="${TARGET_HOST}-clang++"
export CXXCPP="${TARGET_HOST}-clang++ -E"
export LD="${HOST}-ld"
export RANLIB="${HOST}-ranlib"
export AS="${HOST}-as"
if [[ $BUILD_STRIP == "yes" ]]; then
    export STRIP="${HOST}-strip"
else
    export STRIP=   #disable strip for library
fi

# ==================================================
# setup toolchain's arch
TOOLCHAIN_ARCH=
case $LIBRARY_ARCH in
    arm64-v8a)        TOOLCHAIN_ARCH="arm64"  ;;
    armeabi-v7a)      TOOLCHAIN_ARCH="arm"    ;;
    armeabi-v7a-neon) TOOLCHAIN_ARCH="arm"    ;;
    x86)              TOOLCHAIN_ARCH="x86"    ;;
    x86_64)           TOOLCHAIN_ARCH="x86_64" ;;
esac

# ==================================================
# setup feature on/off, prefix and sysroot
LIBRARY_PREFIX=$BUILD_LIB/android/$LIBRARY_NAME/$LIBRARY_ARCH
LIBRARY_TOOLCHAIN=$ANDROID_NDK/toolchains/llvm/prebuilt/$TOOLCHAIN_HOST
LIBRARY_SYSROOT=$LIBRARY_TOOLCHAIN/sysroot
LIBRARY_PKG_CONFIG=$(command -v pkg-config)
LIBRARY_PKG_CONFIG_PATH=
BUILD_CFLAGS=
BUILD_LDFLAGS=
BUILD_CXXFLAGS=
BUILD_CFLAGS="$BUILD_CFLAGS -fno-integrated-as -fstrict-aliasing -fPIC -I$LIBRARY_TOOLCHAIN/sysroot/usr/include -I$LIBRARY_TOOLCHAIN/sysroot/usr/include/$LIBRARY_HOST"
BUILD_CFLAGS="$BUILD_CFLAGS -Wno-unused-function -DBIONIC_IOCTL_NO_SIGNEDNESS_OVERLOAD"
BUILD_CFLAGS="$BUILD_CFLAGS -O2 -ffunction-sections -fdata-sections"
BUILD_LDFLAGS="$BUILD_LDFLAGS -L$LIBRARY_TOOLCHAIN/$LIBRARY_HOST/lib -L$LIBRARY_TOOLCHAIN/sysroot/usr/lib/$LIBRARY_HOST/${BUILD_API} -L$LIBRARY_TOOLCHAIN/lib"
BUILD_LDFLAGS="$BUILD_LDFLAGS -Wl,--gc-sections -O2 -ffunction-sections -fdata-sections -finline-functions"
BUILD_LDFLAGS="$BUILD_LDFLAGS -lc -lm -ldl -llog -lc++_shared -lstdc++"
BUILD_CXXFLAGS="$BUILD_CXXFLAGS -DANDROID -D__ANDROID__ -D__ANDROID_API__=$BUILD_API"
BUILD_CXXFLAGS="$BUILD_CXXFLAGS -std=c++11 -fno-exceptions -fno-rtti -O2 -ffunction-sections -fdata-sections"
case $LIBRARY_ARCH in
    armeabi-v7a | armeabi-v7a-neon)
        BUILD_CFLAGS="$BUILD_CFLAGS -march=armv7-a -mfpu=vfpv3-d16 -mfloat-abi=softfp"
        BUILD_LDFLAGS="$BUILD_LDFLAGS -march=armv7-a -mfpu=vfpv3-d16 -mfloat-abi=softfp -Wl,--fix-cortex-a8"
    ;;
    arm64-v8a)
        BUILD_CFLAGS="$BUILD_CFLAGS -march=armv8-a"
        BUILD_LDFLAGS="$BUILD_LDFLAGS -march=armv8-a"
    ;;
    x86)
        BUILD_CFLAGS="$BUILD_CFLAGS -march=i686 -mtune=intel -mssse3 -mfpmath=sse -m32"
        BUILD_LDFLAGS="$BUILD_LDFLAGS -march=i686"
    ;;
    x86_64)
        BUILD_CFLAGS="$BUILD_CFLAGS -march=x86-64 -msse4.2 -mpopcnt -m64 -mtune=intel"
        BUILD_LDFLAGS="$BUILD_LDFLAGS -march=x86-64"
    ;;
esac
# ==================================================
# setup compiler flags
CFLAGS=$BUILD_CFLAGS
CXXFLAGS=$BUILD_CXXFLAGS
LDFLAGS=$BUILD_LDFLAGS

LIBRARY_FLAGS=
LIBRARY_FLAGS="$LIBRARY_FLAGS --prefix=$LIBRARY_PREFIX"
LIBRARY_FLAGS="$LIBRARY_FLAGS --sysroot=$LIBRARY_SYSROOT"
LIBRARY_FLAGS="$LIBRARY_FLAGS --target-os=android"
LIBRARY_FLAGS="$LIBRARY_FLAGS --cross-prefix=$LIBRARY_HOST-"
LIBRARY_FLAGS="$LIBRARY_FLAGS --pkg-config=$LIBRARY_PKG_CONFIG"

# ==================================================
# setup common config

# Licensing options:
LIBRARY_FLAGS="$LIBRARY_FLAGS --enable-gpl"
LIBRARY_FLAGS="$LIBRARY_FLAGS --enable-version3"
LIBRARY_FLAGS="$LIBRARY_FLAGS --enable-nonfree"

# Configuration options:
LIBRARY_FLAGS="$LIBRARY_FLAGS --disable-static"
LIBRARY_FLAGS="$LIBRARY_FLAGS --enable-shared"
LIBRARY_FLAGS="$LIBRARY_FLAGS --disable-small"
LIBRARY_FLAGS="$LIBRARY_FLAGS --enable-runtime-cpudetect"
LIBRARY_FLAGS="$LIBRARY_FLAGS --enable-gray"
LIBRARY_FLAGS="$LIBRARY_FLAGS --enable-swscale-alpha"
LIBRARY_FLAGS="$LIBRARY_FLAGS --disable-autodetect"

# Program options:
LIBRARY_FLAGS="$LIBRARY_FLAGS --disable-programs"
LIBRARY_FLAGS="$LIBRARY_FLAGS --disable-ffmpeg"
LIBRARY_FLAGS="$LIBRARY_FLAGS --disable-ffplay"
LIBRARY_FLAGS="$LIBRARY_FLAGS --disable-ffprobe"

# Documentation options:
LIBRARY_FLAGS="$LIBRARY_FLAGS --disable-doc"
LIBRARY_FLAGS="$LIBRARY_FLAGS --disable-htmlpages"
LIBRARY_FLAGS="$LIBRARY_FLAGS --disable-manpages"
LIBRARY_FLAGS="$LIBRARY_FLAGS --disable-podpages"
LIBRARY_FLAGS="$LIBRARY_FLAGS --disable-txtpages"

# Component options:
LIBRARY_FLAGS="$LIBRARY_FLAGS --enable-avcodec"
LIBRARY_FLAGS="$LIBRARY_FLAGS --enable-avformat"
LIBRARY_FLAGS="$LIBRARY_FLAGS --enable-swresample"
LIBRARY_FLAGS="$LIBRARY_FLAGS --enable-swscale"
LIBRARY_FLAGS="$LIBRARY_FLAGS --enable-avfilter"
LIBRARY_FLAGS="$LIBRARY_FLAGS --disable-postproc"
LIBRARY_FLAGS="$LIBRARY_FLAGS --disable-avdevice"
LIBRARY_FLAGS="$LIBRARY_FLAGS --enable-pthreads"
LIBRARY_FLAGS="$LIBRARY_FLAGS --disable-w32threads"
LIBRARY_FLAGS="$LIBRARY_FLAGS --disable-os2threads"
LIBRARY_FLAGS="$LIBRARY_FLAGS --enable-network"
LIBRARY_FLAGS="$LIBRARY_FLAGS --enable-dct"
LIBRARY_FLAGS="$LIBRARY_FLAGS --enable-dwt"
LIBRARY_FLAGS="$LIBRARY_FLAGS --enable-error-resilience"
LIBRARY_FLAGS="$LIBRARY_FLAGS --enable-lsp"
LIBRARY_FLAGS="$LIBRARY_FLAGS --enable-lzo"
LIBRARY_FLAGS="$LIBRARY_FLAGS --enable-mdct" # for aac
LIBRARY_FLAGS="$LIBRARY_FLAGS --enable-rdft"
LIBRARY_FLAGS="$LIBRARY_FLAGS --enable-fft"  # for aac
LIBRARY_FLAGS="$LIBRARY_FLAGS --enable-faan"
LIBRARY_FLAGS="$LIBRARY_FLAGS --enable-pixelutils"

# Individual component options:
LIBRARY_FLAGS="$LIBRARY_FLAGS --disable-everything"
LIBRARY_FLAGS="$LIBRARY_FLAGS --disable-devices"

# Hardware accelerators:
# ./configure --list-hwaccels
LIBRARY_FLAGS="$LIBRARY_FLAGS --enable-hwaccels"

# ./configure --list-encoders
LIBRARY_FLAGS="$LIBRARY_FLAGS --disable-encoders"
LIBRARY_FLAGS="$LIBRARY_FLAGS --enable-encoder=aac"
# LIBRARY_FLAGS="$LIBRARY_FLAGS --enable-encoder=aac_at" # AudioToolbox
# LIBRARY_FLAGS="$LIBRARY_FLAGS --enable-encoder=aac_mf" # MediaFoundation
LIBRARY_FLAGS="$LIBRARY_FLAGS --enable-encoder=ass"
LIBRARY_FLAGS="$LIBRARY_FLAGS --enable-encoder=apng"
LIBRARY_FLAGS="$LIBRARY_FLAGS --enable-encoder=bmp"
LIBRARY_FLAGS="$LIBRARY_FLAGS --enable-encoder=gif"
LIBRARY_FLAGS="$LIBRARY_FLAGS --enable-encoder=h261"
LIBRARY_FLAGS="$LIBRARY_FLAGS --enable-encoder=h263"
LIBRARY_FLAGS="$LIBRARY_FLAGS --enable-encoder=h263p"
LIBRARY_FLAGS="$LIBRARY_FLAGS --enable-encoder=opus"
LIBRARY_FLAGS="$LIBRARY_FLAGS --enable-encoder=png"

# ./configure --list-decoders
LIBRARY_FLAGS="$LIBRARY_FLAGS --disable-decoders"
LIBRARY_FLAGS="$LIBRARY_FLAGS --enable-decoder=aac"
# LIBRARY_FLAGS="$LIBRARY_FLAGS --enable-decoder=aac_at"  # AudioToolbox
LIBRARY_FLAGS="$LIBRARY_FLAGS --enable-decoder=aac_fixed"
LIBRARY_FLAGS="$LIBRARY_FLAGS --enable-decoder=aac_latm"
# LIBRARY_FLAGS="$LIBRARY_FLAGS --enable-decoder=amr_nb_at" # AudioToolbox
LIBRARY_FLAGS="$LIBRARY_FLAGS --enable-decoder=amrnb"
LIBRARY_FLAGS="$LIBRARY_FLAGS --enable-decoder=amrwb"
LIBRARY_FLAGS="$LIBRARY_FLAGS --enable-decoder=apng"
LIBRARY_FLAGS="$LIBRARY_FLAGS --enable-decoder=ass"
LIBRARY_FLAGS="$LIBRARY_FLAGS --enable-decoder=av1"
LIBRARY_FLAGS="$LIBRARY_FLAGS --enable-decoder=bmp"
LIBRARY_FLAGS="$LIBRARY_FLAGS --enable-decoder=flac"
LIBRARY_FLAGS="$LIBRARY_FLAGS --enable-decoder=flv"
LIBRARY_FLAGS="$LIBRARY_FLAGS --enable-decoder=gif"
LIBRARY_FLAGS="$LIBRARY_FLAGS --enable-decoder=h261"
LIBRARY_FLAGS="$LIBRARY_FLAGS --enable-decoder=h263"
LIBRARY_FLAGS="$LIBRARY_FLAGS --enable-decoder=h263i"
LIBRARY_FLAGS="$LIBRARY_FLAGS --enable-decoder=h263p"
LIBRARY_FLAGS="$LIBRARY_FLAGS --enable-decoder=h264"
LIBRARY_FLAGS="$LIBRARY_FLAGS --enable-decoder=h264_mediacodec"
LIBRARY_FLAGS="$LIBRARY_FLAGS --enable-decoder=hevc"
LIBRARY_FLAGS="$LIBRARY_FLAGS --enable-decoder=hevc_mediacodec"
LIBRARY_FLAGS="$LIBRARY_FLAGS --enable-decoder=jpeg2000"
LIBRARY_FLAGS="$LIBRARY_FLAGS --enable-decoder=jpegls"
LIBRARY_FLAGS="$LIBRARY_FLAGS --enable-decoder=movtext"
LIBRARY_FLAGS="$LIBRARY_FLAGS --enable-decoder=mp3"
# LIBRARY_FLAGS="$LIBRARY_FLAGS --enable-decoder=mp3_at" # AudioToolbox
LIBRARY_FLAGS="$LIBRARY_FLAGS --enable-decoder=mp3adu"
LIBRARY_FLAGS="$LIBRARY_FLAGS --enable-decoder=mp3adufloat"
LIBRARY_FLAGS="$LIBRARY_FLAGS --enable-decoder=mp3float"
LIBRARY_FLAGS="$LIBRARY_FLAGS --enable-decoder=mp3on4"
LIBRARY_FLAGS="$LIBRARY_FLAGS --enable-decoder=mp3on4float"
LIBRARY_FLAGS="$LIBRARY_FLAGS --enable-decoder=mpeg1video"
LIBRARY_FLAGS="$LIBRARY_FLAGS --enable-decoder=mpeg2_mediacodec"
LIBRARY_FLAGS="$LIBRARY_FLAGS --enable-decoder=mpeg2video"
LIBRARY_FLAGS="$LIBRARY_FLAGS --enable-decoder=mpeg4"
LIBRARY_FLAGS="$LIBRARY_FLAGS --enable-decoder=mpeg4_mediacodec"
LIBRARY_FLAGS="$LIBRARY_FLAGS --enable-decoder=mpegvideo"
LIBRARY_FLAGS="$LIBRARY_FLAGS --enable-decoder=opus"
LIBRARY_FLAGS="$LIBRARY_FLAGS --enable-decoder=pcm_alaw"
# LIBRARY_FLAGS="$LIBRARY_FLAGS --enable-decoder=pcm_alaw_at"   # AudioToolbox
LIBRARY_FLAGS="$LIBRARY_FLAGS --enable-decoder=pcm_bluray"
LIBRARY_FLAGS="$LIBRARY_FLAGS --enable-decoder=pcm_dvd"
LIBRARY_FLAGS="$LIBRARY_FLAGS --enable-decoder=pcm_f16le"
LIBRARY_FLAGS="$LIBRARY_FLAGS --enable-decoder=pcm_f24le"
LIBRARY_FLAGS="$LIBRARY_FLAGS --enable-decoder=pcm_f32be"
LIBRARY_FLAGS="$LIBRARY_FLAGS --enable-decoder=pcm_f32le"
LIBRARY_FLAGS="$LIBRARY_FLAGS --enable-decoder=pcm_f64be"
LIBRARY_FLAGS="$LIBRARY_FLAGS --enable-decoder=pcm_f64le"
LIBRARY_FLAGS="$LIBRARY_FLAGS --enable-decoder=pcm_lxf"
LIBRARY_FLAGS="$LIBRARY_FLAGS --enable-decoder=pcm_mulaw"
# LIBRARY_FLAGS="$LIBRARY_FLAGS --enable-decoder=pcm_mulaw_at"   # AudioToolbox
LIBRARY_FLAGS="$LIBRARY_FLAGS --enable-decoder=pcm_s16be"
LIBRARY_FLAGS="$LIBRARY_FLAGS --enable-decoder=pcm_s16be_planar"
LIBRARY_FLAGS="$LIBRARY_FLAGS --enable-decoder=pcm_s16le"
LIBRARY_FLAGS="$LIBRARY_FLAGS --enable-decoder=pcm_s16le_planar"
LIBRARY_FLAGS="$LIBRARY_FLAGS --enable-decoder=pcm_s24be"
LIBRARY_FLAGS="$LIBRARY_FLAGS --enable-decoder=pcm_s24daud"
LIBRARY_FLAGS="$LIBRARY_FLAGS --enable-decoder=pcm_s24le"
LIBRARY_FLAGS="$LIBRARY_FLAGS --enable-decoder=pcm_s24le_planar"
LIBRARY_FLAGS="$LIBRARY_FLAGS --enable-decoder=pcm_s32be"
LIBRARY_FLAGS="$LIBRARY_FLAGS --enable-decoder=pcm_s32le"
LIBRARY_FLAGS="$LIBRARY_FLAGS --enable-decoder=pcm_s32le_planar"
LIBRARY_FLAGS="$LIBRARY_FLAGS --enable-decoder=pcm_s64be"
LIBRARY_FLAGS="$LIBRARY_FLAGS --enable-decoder=pcm_s64le"
LIBRARY_FLAGS="$LIBRARY_FLAGS --enable-decoder=pcm_s8"
LIBRARY_FLAGS="$LIBRARY_FLAGS --enable-decoder=pcm_s8_planar"
LIBRARY_FLAGS="$LIBRARY_FLAGS --enable-decoder=pcm_sga"
LIBRARY_FLAGS="$LIBRARY_FLAGS --enable-decoder=pcm_u16be"
LIBRARY_FLAGS="$LIBRARY_FLAGS --enable-decoder=pcm_u16le"
LIBRARY_FLAGS="$LIBRARY_FLAGS --enable-decoder=pcm_u24be"
LIBRARY_FLAGS="$LIBRARY_FLAGS --enable-decoder=pcm_u24le"
LIBRARY_FLAGS="$LIBRARY_FLAGS --enable-decoder=pcm_u32be"
LIBRARY_FLAGS="$LIBRARY_FLAGS --enable-decoder=pcm_u32le"
LIBRARY_FLAGS="$LIBRARY_FLAGS --enable-decoder=pcm_u8"
LIBRARY_FLAGS="$LIBRARY_FLAGS --enable-decoder=pcm_vidc"
LIBRARY_FLAGS="$LIBRARY_FLAGS --enable-decoder=png"
LIBRARY_FLAGS="$LIBRARY_FLAGS --enable-decoder=prores"
LIBRARY_FLAGS="$LIBRARY_FLAGS --enable-decoder=rawvideo"
LIBRARY_FLAGS="$LIBRARY_FLAGS --enable-decoder=srt"
LIBRARY_FLAGS="$LIBRARY_FLAGS --enable-decoder=text"
LIBRARY_FLAGS="$LIBRARY_FLAGS --enable-decoder=theora"
LIBRARY_FLAGS="$LIBRARY_FLAGS --enable-decoder=tiff"
# LIBRARY_FLAGS="$LIBRARY_FLAGS --enable-decoder=vc1"
LIBRARY_FLAGS="$LIBRARY_FLAGS --enable-decoder=vorbis"
LIBRARY_FLAGS="$LIBRARY_FLAGS --enable-decoder=vp3"
LIBRARY_FLAGS="$LIBRARY_FLAGS --enable-decoder=vp5"
LIBRARY_FLAGS="$LIBRARY_FLAGS --enable-decoder=vp6"
LIBRARY_FLAGS="$LIBRARY_FLAGS --enable-decoder=vp6a"
LIBRARY_FLAGS="$LIBRARY_FLAGS --enable-decoder=vp6f"
LIBRARY_FLAGS="$LIBRARY_FLAGS --enable-decoder=vp7"
LIBRARY_FLAGS="$LIBRARY_FLAGS --enable-decoder=vp8"
LIBRARY_FLAGS="$LIBRARY_FLAGS --enable-decoder=vp8_mediacodec"
LIBRARY_FLAGS="$LIBRARY_FLAGS --enable-decoder=vp9"
LIBRARY_FLAGS="$LIBRARY_FLAGS --enable-decoder=vp9_mediacodec"
LIBRARY_FLAGS="$LIBRARY_FLAGS --enable-decoder=wavpack"
LIBRARY_FLAGS="$LIBRARY_FLAGS --enable-decoder=webp"
LIBRARY_FLAGS="$LIBRARY_FLAGS --enable-decoder=webvtt"
LIBRARY_FLAGS="$LIBRARY_FLAGS --enable-decoder=zlib"

# ./configure --list-muxers
LIBRARY_FLAGS="$LIBRARY_FLAGS --disable-muxers"
LIBRARY_FLAGS="$LIBRARY_FLAGS --enable-muxer=ass"
LIBRARY_FLAGS="$LIBRARY_FLAGS --enable-muxer=dash"
LIBRARY_FLAGS="$LIBRARY_FLAGS --enable-muxer=data"
LIBRARY_FLAGS="$LIBRARY_FLAGS --enable-muxer=ffmetadata"
LIBRARY_FLAGS="$LIBRARY_FLAGS --enable-muxer=gif"
LIBRARY_FLAGS="$LIBRARY_FLAGS --enable-muxer=h261"
LIBRARY_FLAGS="$LIBRARY_FLAGS --enable-muxer=h263"
LIBRARY_FLAGS="$LIBRARY_FLAGS --enable-muxer=h264"
LIBRARY_FLAGS="$LIBRARY_FLAGS --enable-muxer=hash"
LIBRARY_FLAGS="$LIBRARY_FLAGS --enable-muxer=hevc"
LIBRARY_FLAGS="$LIBRARY_FLAGS --enable-muxer=hls"
LIBRARY_FLAGS="$LIBRARY_FLAGS --enable-muxer=image2"
LIBRARY_FLAGS="$LIBRARY_FLAGS --enable-muxer=image2pipe"
LIBRARY_FLAGS="$LIBRARY_FLAGS --enable-muxer=md5"
LIBRARY_FLAGS="$LIBRARY_FLAGS --enable-muxer=mov"
LIBRARY_FLAGS="$LIBRARY_FLAGS --enable-muxer=mp2"
LIBRARY_FLAGS="$LIBRARY_FLAGS --enable-muxer=mp3"
LIBRARY_FLAGS="$LIBRARY_FLAGS --enable-muxer=mp4"
LIBRARY_FLAGS="$LIBRARY_FLAGS --enable-muxer=mpegts"
LIBRARY_FLAGS="$LIBRARY_FLAGS --enable-muxer=segment"
LIBRARY_FLAGS="$LIBRARY_FLAGS --enable-muxer=webm"
LIBRARY_FLAGS="$LIBRARY_FLAGS --enable-muxer=webm_chunk"
LIBRARY_FLAGS="$LIBRARY_FLAGS --enable-muxer=webm_dash_manifest"
LIBRARY_FLAGS="$LIBRARY_FLAGS --enable-muxer=webp"

# ./configure --list-demuxers
LIBRARY_FLAGS="$LIBRARY_FLAGS --disable-demuxers"
LIBRARY_FLAGS="$LIBRARY_FLAGS --enable-demuxer=aac"
LIBRARY_FLAGS="$LIBRARY_FLAGS --enable-demuxer=ac3"
LIBRARY_FLAGS="$LIBRARY_FLAGS --enable-demuxer=amr"
LIBRARY_FLAGS="$LIBRARY_FLAGS --enable-demuxer=apng"
LIBRARY_FLAGS="$LIBRARY_FLAGS --enable-demuxer=asf"
LIBRARY_FLAGS="$LIBRARY_FLAGS --enable-demuxer=asf_o"
LIBRARY_FLAGS="$LIBRARY_FLAGS --enable-demuxer=ass"
LIBRARY_FLAGS="$LIBRARY_FLAGS --enable-demuxer=ast"
LIBRARY_FLAGS="$LIBRARY_FLAGS --enable-demuxer=avi"
# LIBRARY_FLAGS="$LIBRARY_FLAGS --enable-demuxer=dash"   # need libxml2
LIBRARY_FLAGS="$LIBRARY_FLAGS --enable-demuxer=data"
LIBRARY_FLAGS="$LIBRARY_FLAGS --enable-demuxer=ffmetadata"
LIBRARY_FLAGS="$LIBRARY_FLAGS --enable-demuxer=flac"
LIBRARY_FLAGS="$LIBRARY_FLAGS --enable-demuxer=flv"
LIBRARY_FLAGS="$LIBRARY_FLAGS --enable-demuxer=gif"
LIBRARY_FLAGS="$LIBRARY_FLAGS --enable-demuxer=h261"
LIBRARY_FLAGS="$LIBRARY_FLAGS --enable-demuxer=h263"
LIBRARY_FLAGS="$LIBRARY_FLAGS --enable-demuxer=h264"
LIBRARY_FLAGS="$LIBRARY_FLAGS --enable-demuxer=hevc"
LIBRARY_FLAGS="$LIBRARY_FLAGS --enable-demuxer=hls"
LIBRARY_FLAGS="$LIBRARY_FLAGS --enable-demuxer=image2"
LIBRARY_FLAGS="$LIBRARY_FLAGS --enable-demuxer=image2pipe"
LIBRARY_FLAGS="$LIBRARY_FLAGS --enable-demuxer=image_bmp_pipe"
LIBRARY_FLAGS="$LIBRARY_FLAGS --enable-demuxer=image_j2k_pipe"
LIBRARY_FLAGS="$LIBRARY_FLAGS --enable-demuxer=image_jpeg_pipe"
LIBRARY_FLAGS="$LIBRARY_FLAGS --enable-demuxer=image_jpegls_pipe"
LIBRARY_FLAGS="$LIBRARY_FLAGS --enable-demuxer=image_png_pipe"
LIBRARY_FLAGS="$LIBRARY_FLAGS --enable-demuxer=image_webp_pipe"
# LIBRARY_FLAGS="$LIBRARY_FLAGS --enable-demuxer=libopenmpt"
LIBRARY_FLAGS="$LIBRARY_FLAGS --enable-demuxer=live_flv"
LIBRARY_FLAGS="$LIBRARY_FLAGS --enable-demuxer=m4v"
LIBRARY_FLAGS="$LIBRARY_FLAGS --enable-demuxer=matroska"
LIBRARY_FLAGS="$LIBRARY_FLAGS --enable-demuxer=mov"
LIBRARY_FLAGS="$LIBRARY_FLAGS --enable-demuxer=mp3"
LIBRARY_FLAGS="$LIBRARY_FLAGS --enable-demuxer=mpegps"
LIBRARY_FLAGS="$LIBRARY_FLAGS --enable-demuxer=mpegts"
LIBRARY_FLAGS="$LIBRARY_FLAGS --enable-demuxer=mpegtsraw"
LIBRARY_FLAGS="$LIBRARY_FLAGS --enable-demuxer=mpegvideo"
LIBRARY_FLAGS="$LIBRARY_FLAGS --enable-demuxer=mpjpeg"
LIBRARY_FLAGS="$LIBRARY_FLAGS --enable-demuxer=ogg"
LIBRARY_FLAGS="$LIBRARY_FLAGS --enable-demuxer=pcm_alaw"
LIBRARY_FLAGS="$LIBRARY_FLAGS --enable-demuxer=pcm_f32be"
LIBRARY_FLAGS="$LIBRARY_FLAGS --enable-demuxer=pcm_f32le"
LIBRARY_FLAGS="$LIBRARY_FLAGS --enable-demuxer=pcm_f64be"
LIBRARY_FLAGS="$LIBRARY_FLAGS --enable-demuxer=pcm_f64le"
LIBRARY_FLAGS="$LIBRARY_FLAGS --enable-demuxer=pcm_mulaw"
LIBRARY_FLAGS="$LIBRARY_FLAGS --enable-demuxer=pcm_s16be"
LIBRARY_FLAGS="$LIBRARY_FLAGS --enable-demuxer=pcm_s16le"
LIBRARY_FLAGS="$LIBRARY_FLAGS --enable-demuxer=pcm_s24be"
LIBRARY_FLAGS="$LIBRARY_FLAGS --enable-demuxer=pcm_s24le"
LIBRARY_FLAGS="$LIBRARY_FLAGS --enable-demuxer=pcm_s32be"
LIBRARY_FLAGS="$LIBRARY_FLAGS --enable-demuxer=pcm_s32le"
LIBRARY_FLAGS="$LIBRARY_FLAGS --enable-demuxer=pcm_s8"
LIBRARY_FLAGS="$LIBRARY_FLAGS --enable-demuxer=pcm_u16be"
LIBRARY_FLAGS="$LIBRARY_FLAGS --enable-demuxer=pcm_u16le"
LIBRARY_FLAGS="$LIBRARY_FLAGS --enable-demuxer=pcm_u24be"
LIBRARY_FLAGS="$LIBRARY_FLAGS --enable-demuxer=pcm_u24le"
LIBRARY_FLAGS="$LIBRARY_FLAGS --enable-demuxer=pcm_u32be"
LIBRARY_FLAGS="$LIBRARY_FLAGS --enable-demuxer=pcm_u32le"
LIBRARY_FLAGS="$LIBRARY_FLAGS --enable-demuxer=pcm_u8"
LIBRARY_FLAGS="$LIBRARY_FLAGS --enable-demuxer=pcm_vidc"
LIBRARY_FLAGS="$LIBRARY_FLAGS --enable-demuxer=rawvideo"
LIBRARY_FLAGS="$LIBRARY_FLAGS --enable-demuxer=rtp"
LIBRARY_FLAGS="$LIBRARY_FLAGS --enable-demuxer=rtsp"
LIBRARY_FLAGS="$LIBRARY_FLAGS --enable-demuxer=srt"
LIBRARY_FLAGS="$LIBRARY_FLAGS --enable-demuxer=swf"
LIBRARY_FLAGS="$LIBRARY_FLAGS --enable-demuxer=vobsub"
LIBRARY_FLAGS="$LIBRARY_FLAGS --enable-demuxer=wav"
LIBRARY_FLAGS="$LIBRARY_FLAGS --enable-demuxer=webm_dash_manifest"
LIBRARY_FLAGS="$LIBRARY_FLAGS --enable-demuxer=webvtt"

# ./configure --list-parsers
LIBRARY_FLAGS="$LIBRARY_FLAGS --disable-parsers"
LIBRARY_FLAGS="$LIBRARY_FLAGS --enable-parser=aac"
LIBRARY_FLAGS="$LIBRARY_FLAGS --enable-parser=aac_latm"
# LIBRARY_FLAGS="$LIBRARY_FLAGS --enable-parser=av1"
LIBRARY_FLAGS="$LIBRARY_FLAGS --enable-parser=bmp"
LIBRARY_FLAGS="$LIBRARY_FLAGS --enable-parser=flac"
LIBRARY_FLAGS="$LIBRARY_FLAGS --enable-parser=gif"
LIBRARY_FLAGS="$LIBRARY_FLAGS --enable-parser=h261"
LIBRARY_FLAGS="$LIBRARY_FLAGS --enable-parser=h263"
LIBRARY_FLAGS="$LIBRARY_FLAGS --enable-parser=h264"
LIBRARY_FLAGS="$LIBRARY_FLAGS --enable-parser=hevc"
LIBRARY_FLAGS="$LIBRARY_FLAGS --enable-parser=jpeg2000"
LIBRARY_FLAGS="$LIBRARY_FLAGS --enable-parser=mpeg4video"
LIBRARY_FLAGS="$LIBRARY_FLAGS --enable-parser=mpegaudio"
LIBRARY_FLAGS="$LIBRARY_FLAGS --enable-parser=mpegvideo"
LIBRARY_FLAGS="$LIBRARY_FLAGS --enable-parser=opus"
LIBRARY_FLAGS="$LIBRARY_FLAGS --enable-parser=png"
LIBRARY_FLAGS="$LIBRARY_FLAGS --enable-parser=vp8"
LIBRARY_FLAGS="$LIBRARY_FLAGS --enable-parser=vp9"
LIBRARY_FLAGS="$LIBRARY_FLAGS --enable-parser=webp"

# ./configure --list-bsfs
LIBRARY_FLAGS="$LIBRARY_FLAGS --enable-bsfs"
# LIBRARY_FLAGS="$LIBRARY_FLAGS --enable-bsf=aac_adtstoasc"
# LIBRARY_FLAGS="$LIBRARY_FLAGS --enable-bsf=av1_frame_merge"
# LIBRARY_FLAGS="$LIBRARY_FLAGS --enable-bsf=av1_frame_split"
# LIBRARY_FLAGS="$LIBRARY_FLAGS --enable-bsf=av1_metadata"
# LIBRARY_FLAGS="$LIBRARY_FLAGS --enable-bsf=dump_extradata"
# LIBRARY_FLAGS="$LIBRARY_FLAGS --enable-bsf=extract_extradata"
# LIBRARY_FLAGS="$LIBRARY_FLAGS --enable-bsf=h264_metadata"
# LIBRARY_FLAGS="$LIBRARY_FLAGS --enable-bsf=h264_mp4toannexb"
# LIBRARY_FLAGS="$LIBRARY_FLAGS --enable-bsf=h264_redundant_pps"
# LIBRARY_FLAGS="$LIBRARY_FLAGS --enable-bsf=hevc_metadata"
# LIBRARY_FLAGS="$LIBRARY_FLAGS --enable-bsf=hevc_mp4toannexb"
# LIBRARY_FLAGS="$LIBRARY_FLAGS --enable-bsf=mov2textsub"
# LIBRARY_FLAGS="$LIBRARY_FLAGS --enable-bsf=mp3_header_decompress"
# LIBRARY_FLAGS="$LIBRARY_FLAGS --enable-bsf=mpeg4_unpack_bframes"
# LIBRARY_FLAGS="$LIBRARY_FLAGS --enable-bsf=opus_metadata"
# LIBRARY_FLAGS="$LIBRARY_FLAGS --enable-bsf=prores_metadata"
# LIBRARY_FLAGS="$LIBRARY_FLAGS --enable-bsf=remove_extradata"
# LIBRARY_FLAGS="$LIBRARY_FLAGS --enable-bsf=setts"
# LIBRARY_FLAGS="$LIBRARY_FLAGS --enable-bsf=truehd_core"
# LIBRARY_FLAGS="$LIBRARY_FLAGS --enable-bsf=vp9_metadata"
# LIBRARY_FLAGS="$LIBRARY_FLAGS --enable-bsf=vp9_raw_reorder"
# LIBRARY_FLAGS="$LIBRARY_FLAGS --enable-bsf=vp9_superframe"
# LIBRARY_FLAGS="$LIBRARY_FLAGS --enable-bsf=vp9_superframe_split"

# ./configure --list-protocols
LIBRARY_FLAGS="$LIBRARY_FLAGS --disable-protocols"
LIBRARY_FLAGS="$LIBRARY_FLAGS --enable-protocol=async"
LIBRARY_FLAGS="$LIBRARY_FLAGS --enable-protocol=cache"
LIBRARY_FLAGS="$LIBRARY_FLAGS --enable-protocol=data"
LIBRARY_FLAGS="$LIBRARY_FLAGS --enable-protocol=file"
LIBRARY_FLAGS="$LIBRARY_FLAGS --enable-protocol=hls"
LIBRARY_FLAGS="$LIBRARY_FLAGS --enable-protocol=http"
LIBRARY_FLAGS="$LIBRARY_FLAGS --enable-protocol=httpproxy"
# LIBRARY_FLAGS="$LIBRARY_FLAGS --enable-protocol=https" # need OpenSSL
LIBRARY_FLAGS="$LIBRARY_FLAGS --enable-protocol=md5"
LIBRARY_FLAGS="$LIBRARY_FLAGS --enable-protocol=pipe"
LIBRARY_FLAGS="$LIBRARY_FLAGS --enable-protocol=rtmp"
# LIBRARY_FLAGS="$LIBRARY_FLAGS --enable-protocol=rtmp*"
LIBRARY_FLAGS="$LIBRARY_FLAGS --enable-protocol=tcp"
LIBRARY_FLAGS="$LIBRARY_FLAGS --enable-protocol=tee"
LIBRARY_FLAGS="$LIBRARY_FLAGS --enable-protocol=udp"
LIBRARY_FLAGS="$LIBRARY_FLAGS --enable-protocol=udplite"
LIBRARY_FLAGS="$LIBRARY_FLAGS --enable-protocol=unix"

# ./configure --list-filters
LIBRARY_FLAGS="$LIBRARY_FLAGS --enable-filters"

# ./configure --list-indevs
LIBRARY_FLAGS="$LIBRARY_FLAGS --disable-indevs"

# ./configure --list-outdevs
LIBRARY_FLAGS="$LIBRARY_FLAGS --disable-outdevs"

# External library support:
LIBRARY_FLAGS="$LIBRARY_FLAGS --disable-alsa"
LIBRARY_FLAGS="$LIBRARY_FLAGS --disable-appkit"
LIBRARY_FLAGS="$LIBRARY_FLAGS --disable-avfoundation"
LIBRARY_FLAGS="$LIBRARY_FLAGS --disable-avisynth"
LIBRARY_FLAGS="$LIBRARY_FLAGS --disable-bzlib"
LIBRARY_FLAGS="$LIBRARY_FLAGS --disable-coreimage"
LIBRARY_FLAGS="$LIBRARY_FLAGS --disable-chromaprint"
# LIBRARY_FLAGS="$LIBRARY_FLAGS --enable-frei0r"       # turn on for libass
LIBRARY_FLAGS="$LIBRARY_FLAGS --disable-gcrypt"
LIBRARY_FLAGS="$LIBRARY_FLAGS --disable-gmp"
LIBRARY_FLAGS="$LIBRARY_FLAGS --disable-gnutls"
LIBRARY_FLAGS="$LIBRARY_FLAGS --disable-iconv"
# LIBRARY_FLAGS="$LIBRARY_FLAGS --enable-jni"          # turn on for MediaCodec
LIBRARY_FLAGS="$LIBRARY_FLAGS --disable-ladspa"
# LIBRARY_FLAGS="$LIBRARY_FLAGS --enable-libaom"       # turn on for AV1 Encode/Decode
LIBRARY_FLAGS="$LIBRARY_FLAGS --disable-libaribb24"
# LIBRARY_FLAGS="$LIBRARY_FLAGS --enable-libass"       # turn on for Subtitle Rendering
LIBRARY_FLAGS="$LIBRARY_FLAGS --disable-libbluray"
LIBRARY_FLAGS="$LIBRARY_FLAGS --disable-libbs2b"
LIBRARY_FLAGS="$LIBRARY_FLAGS --disable-libcaca"
LIBRARY_FLAGS="$LIBRARY_FLAGS --disable-libcelt"
LIBRARY_FLAGS="$LIBRARY_FLAGS --disable-libcdio"
LIBRARY_FLAGS="$LIBRARY_FLAGS --disable-libcodec2"
LIBRARY_FLAGS="$LIBRARY_FLAGS --disable-libdav1d"
LIBRARY_FLAGS="$LIBRARY_FLAGS --disable-libdavs2"
LIBRARY_FLAGS="$LIBRARY_FLAGS --disable-libdc1394"
# LIBRARY_FLAGS="$LIBRARY_FLAGS --enable-libfdk-aac"    # turn on for AAC Encode
LIBRARY_FLAGS="$LIBRARY_FLAGS --disable-libflite"
# LIBRARY_FLAGS="$LIBRARY_FLAGS --enable-libfontconfig" # turn on for Subtitle Rendering
# LIBRARY_FLAGS="$LIBRARY_FLAGS --enable-libfreetype"   # turn on for Subtitle Rendering
# LIBRARY_FLAGS="$LIBRARY_FLAGS --enable-libfribidi"    # turn on for Subtitle Rendering
LIBRARY_FLAGS="$LIBRARY_FLAGS --disable-libglslang"
LIBRARY_FLAGS="$LIBRARY_FLAGS --disable-libgme"
LIBRARY_FLAGS="$LIBRARY_FLAGS --disable-libgsm"
LIBRARY_FLAGS="$LIBRARY_FLAGS --disable-libiec61883"
LIBRARY_FLAGS="$LIBRARY_FLAGS --disable-libilbc"
LIBRARY_FLAGS="$LIBRARY_FLAGS --disable-libklvanc"
LIBRARY_FLAGS="$LIBRARY_FLAGS --disable-libkvazaar"
LIBRARY_FLAGS="$LIBRARY_FLAGS --disable-liblensfun"
LIBRARY_FLAGS="$LIBRARY_FLAGS --disable-libmodplug"
# LIBRARY_FLAGS="$LIBRARY_FLAGS --enable-libmp3lame"    # turn on for MP3 Encode/Decode
LIBRARY_FLAGS="$LIBRARY_FLAGS --disable-libopencore-amrnb"
LIBRARY_FLAGS="$LIBRARY_FLAGS --disable-libopencore-amrwb"
# LIBRARY_FLAGS="$LIBRARY_FLAGS --enable-libopencv"     # OpenCV
# LIBRARY_FLAGS="$LIBRARY_FLAGS --enable-libopenh264"   # OpenH264
LIBRARY_FLAGS="$LIBRARY_FLAGS --disable-libopenjpeg"
LIBRARY_FLAGS="$LIBRARY_FLAGS --disable-libopenmpt"
LIBRARY_FLAGS="$LIBRARY_FLAGS --disable-libopenvino"
# LIBRARY_FLAGS="$LIBRARY_FLAGS --enable-libopus"       # Opus
LIBRARY_FLAGS="$LIBRARY_FLAGS --disable-libpulse"
LIBRARY_FLAGS="$LIBRARY_FLAGS --disable-librabbitmq"
LIBRARY_FLAGS="$LIBRARY_FLAGS --disable-librav1e"
LIBRARY_FLAGS="$LIBRARY_FLAGS --disable-librist"
LIBRARY_FLAGS="$LIBRARY_FLAGS --disable-librsvg"
LIBRARY_FLAGS="$LIBRARY_FLAGS --disable-librubberband"
LIBRARY_FLAGS="$LIBRARY_FLAGS --disable-librtmp"
LIBRARY_FLAGS="$LIBRARY_FLAGS --disable-libshaderc"
LIBRARY_FLAGS="$LIBRARY_FLAGS --disable-libshine"
LIBRARY_FLAGS="$LIBRARY_FLAGS --disable-libsmbclient"
LIBRARY_FLAGS="$LIBRARY_FLAGS --disable-libsnappy"
# LIBRARY_FLAGS="$LIBRARY_FLAGS --enable-libsoxr"       # SOXR Audio
LIBRARY_FLAGS="$LIBRARY_FLAGS --disable-libsrt"
LIBRARY_FLAGS="$LIBRARY_FLAGS --disable-libssh"
LIBRARY_FLAGS="$LIBRARY_FLAGS --disable-libsvtav1"
LIBRARY_FLAGS="$LIBRARY_FLAGS --disable-libtensorflow"
LIBRARY_FLAGS="$LIBRARY_FLAGS --disable-libtesseract"
LIBRARY_FLAGS="$LIBRARY_FLAGS --disable-libtheora"
LIBRARY_FLAGS="$LIBRARY_FLAGS --disable-libtls"
LIBRARY_FLAGS="$LIBRARY_FLAGS --disable-libtwolame"
LIBRARY_FLAGS="$LIBRARY_FLAGS --disable-libuavs3d"
LIBRARY_FLAGS="$LIBRARY_FLAGS --disable-libv4l2"
LIBRARY_FLAGS="$LIBRARY_FLAGS --disable-libvidstab"
LIBRARY_FLAGS="$LIBRARY_FLAGS --disable-libvmaf"
LIBRARY_FLAGS="$LIBRARY_FLAGS --disable-libvo-amrwbenc"
LIBRARY_FLAGS="$LIBRARY_FLAGS --disable-libvorbis"
LIBRARY_FLAGS="$LIBRARY_FLAGS --disable-libvpx"
# LIBRARY_FLAGS="$LIBRARY_FLAGS --enable-libwebp"       # WEBP
# LIBRARY_FLAGS="$LIBRARY_FLAGS --enable-libx264"       # X264
# LIBRARY_FLAGS="$LIBRARY_FLAGS --enable-libx265"       # X265
LIBRARY_FLAGS="$LIBRARY_FLAGS --disable-libxavs"
LIBRARY_FLAGS="$LIBRARY_FLAGS --disable-libxavs2"
LIBRARY_FLAGS="$LIBRARY_FLAGS --disable-libxcb"
LIBRARY_FLAGS="$LIBRARY_FLAGS --disable-libxcb-shm"
LIBRARY_FLAGS="$LIBRARY_FLAGS --disable-libxcb-xfixes"
LIBRARY_FLAGS="$LIBRARY_FLAGS --disable-libxcb-shape"
LIBRARY_FLAGS="$LIBRARY_FLAGS --disable-libxvid"
# LIBRARY_FLAGS="$LIBRARY_FLAGS --enable-libxml2"       # XML2
LIBRARY_FLAGS="$LIBRARY_FLAGS --disable-libzimg"
LIBRARY_FLAGS="$LIBRARY_FLAGS --disable-libzmq"
LIBRARY_FLAGS="$LIBRARY_FLAGS --disable-libzvbi"
LIBRARY_FLAGS="$LIBRARY_FLAGS --disable-lv2"
LIBRARY_FLAGS="$LIBRARY_FLAGS --disable-lzma"
LIBRARY_FLAGS="$LIBRARY_FLAGS --disable-decklink"
# LIBRARY_FLAGS="$LIBRARY_FLAGS --enable-mediacodec"    # MediaCodec
LIBRARY_FLAGS="$LIBRARY_FLAGS --disable-mediafoundation"
LIBRARY_FLAGS="$LIBRARY_FLAGS --disable-metal"          # iOS
LIBRARY_FLAGS="$LIBRARY_FLAGS --disable-libmysofa"
LIBRARY_FLAGS="$LIBRARY_FLAGS --disable-openal"
LIBRARY_FLAGS="$LIBRARY_FLAGS --disable-opencl"
LIBRARY_FLAGS="$LIBRARY_FLAGS --disable-opengl"
LIBRARY_FLAGS="$LIBRARY_FLAGS --disable-openssl"
LIBRARY_FLAGS="$LIBRARY_FLAGS --disable-pocketsphinx"
LIBRARY_FLAGS="$LIBRARY_FLAGS --disable-sndio"
LIBRARY_FLAGS="$LIBRARY_FLAGS --disable-schannel"
LIBRARY_FLAGS="$LIBRARY_FLAGS --disable-sdl2"
LIBRARY_FLAGS="$LIBRARY_FLAGS --disable-securetransport"
LIBRARY_FLAGS="$LIBRARY_FLAGS --disable-vapoursynth"
LIBRARY_FLAGS="$LIBRARY_FLAGS --disable-vulkan"
LIBRARY_FLAGS="$LIBRARY_FLAGS --disable-xlib"
LIBRARY_FLAGS="$LIBRARY_FLAGS --enable-zlib"

# The following libraries provide various hardware acceleration features:
LIBRARY_FLAGS="$LIBRARY_FLAGS --disable-audiotoolbox"   # disable for Android
LIBRARY_FLAGS="$LIBRARY_FLAGS --disable-amf"
LIBRARY_FLAGS="$LIBRARY_FLAGS --disable-cuda-nvcc"
LIBRARY_FLAGS="$LIBRARY_FLAGS --disable-cuda-llvm"
LIBRARY_FLAGS="$LIBRARY_FLAGS --disable-cuvid"
LIBRARY_FLAGS="$LIBRARY_FLAGS --disable-d3d11va"
LIBRARY_FLAGS="$LIBRARY_FLAGS --disable-dxva2"
LIBRARY_FLAGS="$LIBRARY_FLAGS --disable-ffnvcodec"
LIBRARY_FLAGS="$LIBRARY_FLAGS --disable-libdrm"
LIBRARY_FLAGS="$LIBRARY_FLAGS --disable-libmfx"
LIBRARY_FLAGS="$LIBRARY_FLAGS --disable-libnpp"
LIBRARY_FLAGS="$LIBRARY_FLAGS --disable-mmal"
LIBRARY_FLAGS="$LIBRARY_FLAGS --disable-nvdec"
LIBRARY_FLAGS="$LIBRARY_FLAGS --disable-nvenc"
LIBRARY_FLAGS="$LIBRARY_FLAGS --disable-omx"
LIBRARY_FLAGS="$LIBRARY_FLAGS --disable-omx-rpi"
LIBRARY_FLAGS="$LIBRARY_FLAGS --disable-rkmpp"
LIBRARY_FLAGS="$LIBRARY_FLAGS --disable-v4l2-m2m"
LIBRARY_FLAGS="$LIBRARY_FLAGS --disable-vaapi"
LIBRARY_FLAGS="$LIBRARY_FLAGS --disable-vdpau"
LIBRARY_FLAGS="$LIBRARY_FLAGS --disable-videotoolbox"   # disable for Android

# Toolchain options:
case $LIBRARY_ARCH in
    armeabi-v7a)
        LIBRARY_FLAGS="$LIBRARY_FLAGS --cpu=armv7-a"
        LIBRARY_FLAGS="$LIBRARY_FLAGS --arch=armv7-a"
        LIBRARY_FLAGS="$LIBRARY_FLAGS --disable-neon --enable-asm --enable-inline-asm"
    ;;
    armeabi-v7a-neon)
        LIBRARY_FLAGS="$LIBRARY_FLAGS --cpu=armv7-a"
        LIBRARY_FLAGS="$LIBRARY_FLAGS --arch=armv7-a"
        LIBRARY_FLAGS="$LIBRARY_FLAGS --enable-neon --enable-asm --enable-inline-asm --build-suffix=_neon"
    ;;
    arm64-v8a)
        LIBRARY_FLAGS="$LIBRARY_FLAGS --cpu=armv8-a"
        LIBRARY_FLAGS="$LIBRARY_FLAGS --arch=aarch64"
        LIBRARY_FLAGS="$LIBRARY_FLAGS --enable-neon --enable-asm --enable-inline-asm"
    ;;
    x86)
        LIBRARY_FLAGS="$LIBRARY_FLAGS --cpu=i686"
        LIBRARY_FLAGS="$LIBRARY_FLAGS --arch=i686"
        LIBRARY_FLAGS="$LIBRARY_FLAGS --disable-neon --disable-asm --disable-inline-asm --disable-x86asm" # asm disabled due to this ticker https://trac.ffmpeg.org/ticket/4928
    ;;
    x86_64)
        LIBRARY_FLAGS="$LIBRARY_FLAGS --cpu=x86_64"
        LIBRARY_FLAGS="$LIBRARY_FLAGS --arch=x86_64"
        LIBRARY_FLAGS="$LIBRARY_FLAGS --disable-neon --enable-asm --enable-inline-asm --enable-x86asm"
    ;;
esac
LIBRARY_FLAGS="$LIBRARY_FLAGS --enable-cross-compile"
LIBRARY_FLAGS="$LIBRARY_FLAGS --enable-pic"
LIBRARY_FLAGS="$LIBRARY_FLAGS --disable-symver"
LIBRARY_FLAGS="$LIBRARY_FLAGS --enable-hardcoded-tables"

# Developer options (useful when working on FFmpeg itself):
case $BUILD_DEBUG in
    yes)
        LIBRARY_FLAGS="$LIBRARY_FLAGS --enable-debug"
    ;;
    *)
        LIBRARY_FLAGS="$LIBRARY_FLAGS --disable-debug --disable-lto"
    ;;
esac
LIBRARY_FLAGS="$LIBRARY_FLAGS --enable-optimizations"
LIBRARY_FLAGS="$LIBRARY_FLAGS --enable-random"
LIBRARY_FLAGS="$LIBRARY_FLAGS --disable-fast-unaligned"
if [[ ! $BUILD_STRIP == "yes" ]]; then
    LIBRARY_FLAGS="$LIBRARY_FLAGS --disable-stripping" # DO NOT STRIP, let AS strip
fi

# ==================================================
# setup customize injected library
if [[ $ENABLE_ZLIB=="1" ]]; then
    CFLAGS="$CFLAGS $(pkg-config --cflags zlib)"
    LDFLAGS="$LDFLAGS $(pkg-config --libs --static zlib)"
    LIBRARY_FLAGS="$LIBRARY_FLAGS --enable-zlib"
fi

if [[ $ENABLE_MEDIACODEC=="1" ]]; then
    CFLAGS="$CFLAGS -I$ANDROID_NDK/toolchains/llvm/prebuilt/darwin-x86_64/sysroot/usr/include"
    LDFLAGS="$LDFLAGS -L$ANDROID_NDK/platforms/android-$BUILD_API/arch-$TARGET_BUILD/usr/lib"
    LIBRARY_FLAGS="$LIBRARY_FLAGS --enable-jni --enable-mediacodec" # for Android OS only
fi

# if [[ $BUILD_ROOT/libs/android/x264/$LIBRARY_ARCH ]]; then
#     LIB_DIR="$BUILD_ROOT/libs/android/x264/$LIBRARY_ARCH"
#     CFLAGS="$CFLAGS -I$LIB_DIR/include"
#     LDFLAGS="$LDFLAGS -L$LIB_DIR/lib"
#     LIBRARY_FLAGS="$LIBRARY_FLAGS --enable-libx264 --enable-encoder=libx264 --enable-encoder=libx264rgb"
# fi

# if [[ $BUILD_ROOT/libs/android/lame/$LIBRARY_ARCH ]]; then
#     LIB_DIR="$BUILD_ROOT/libs/android/lame/$LIBRARY_ARCH"
#     CFLAGS="$CFLAGS -I$LIB_DIR/include"
#     LDFLAGS="$LDFLAGS -L$LIB_DIR/lib"
#     LIBRARY_FLAGS="$LIBRARY_FLAGS --enable-libmp3lame --enable-encoder=libmp3lame"
# fi

CFLAGS+=" -I$ANDROID_NDK/sysroot"
LDFLAGS+=" -L$ANDROID_NDK/platforms/android-$BUILD_API/arch-$TOOLCHAIN_ARCH/usr/lib"


ulimit -n 2048
export CFLAGS="$CFLAGS"
export CXXFLAGS="$CXXFLAGS"
export LDFLAGS="$LDFLAGS"

# clone original source for each ARCH
if [[ ! -d $LIBRARY_PREFIX ]]; then
    mkdir -p $LIBRARY_PREFIX
fi
cp -rf $BUILD_SRC/$LIBRARY_NAME $LIBRARY_PREFIX/

pushd $LIBRARY_PREFIX/$LIBRARY_NAME &> /dev/null
./configure $LIBRARY_FLAGS --cc="${CC}" --cxx="${CXX}" | tee $LIBRARY_PREFIX/configuration-${LIBRARY_ARCH}.txt
make $MAKE_FLAG | tee ${LIBRARY_PREFIX}/make-${LIBRARY_ARCH}.txt
make install

# copy headers
mkdir -p $LIBRARY_PREFIX/include/libffmpeg
mkdir -p $LIBRARY_PREFIX/include/libavformat
mkdir -p $LIBRARY_PREFIX/include/libavfilter
mkdir -p $LIBRARY_PREFIX/include/libavutil/x86
mkdir -p $LIBRARY_PREFIX/include/libavutil/arm
mkdir -p $LIBRARY_PREFIX/include/libavutil/aarch64
mkdir -p $LIBRARY_PREFIX/include/libavcodec/x86
mkdir -p $LIBRARY_PREFIX/include/libavcodec/arm
mkdir -p $LIBRARY_PREFIX/include/libavcodec/aarch64

cp -rf $LIBRARY_PREFIX/$LIBRARY_NAME/config.h $LIBRARY_PREFIX/include/
cp -rf $LIBRARY_PREFIX/$LIBRARY_NAME/config.h $LIBRARY_PREFIX/include/libffmpeg/

cp -rf $LIBRARY_PREFIX/$LIBRARY_NAME/libavcodec/mathops.h $LIBRARY_PREFIX/include/libavcodec
cp -rf $LIBRARY_PREFIX/$LIBRARY_NAME/libavcodec/x86/*.h $LIBRARY_PREFIX/include/libavcodec/x86
cp -rf $LIBRARY_PREFIX/$LIBRARY_NAME/libavcodec/arm/*.h $LIBRARY_PREFIX/include/libavcodec/arm
cp -rf $LIBRARY_PREFIX/$LIBRARY_NAME/libavcodec/aarch64/*.h $LIBRARY_PREFIX/include/libavcodec/aarch64
cp -rf $LIBRARY_PREFIX/$LIBRARY_NAME/libavformat/network.h $LIBRARY_PREFIX/include/libavformat
cp -rf $LIBRARY_PREFIX/$LIBRARY_NAME/libavformat/os_support.h $LIBRARY_PREFIX/include/libavformat
cp -rf $LIBRARY_PREFIX/$LIBRARY_NAME/libavformat/url.h $LIBRARY_PREFIX/include/libavformat
cp -rf $LIBRARY_PREFIX/$LIBRARY_NAME/libavutil/aarch64/cpu.h $LIBRARY_PREFIX/include/libavutil/aarch64/cpu.h
cp -rf $LIBRARY_PREFIX/$LIBRARY_NAME/libavutil/internal.h $LIBRARY_PREFIX/include/libavutil
cp -rf $LIBRARY_PREFIX/$LIBRARY_NAME/libavutil/libm.h $LIBRARY_PREFIX/include/libavutil
cp -rf $LIBRARY_PREFIX/$LIBRARY_NAME/libavutil/reverse.h $LIBRARY_PREFIX/include/libavutil
cp -rf $LIBRARY_PREFIX/$LIBRARY_NAME/libavutil/thread.h $LIBRARY_PREFIX/include/libavutil
cp -rf $LIBRARY_PREFIX/$LIBRARY_NAME/libavutil/timer.h $LIBRARY_PREFIX/include/libavutil
cp -rf $LIBRARY_PREFIX/$LIBRARY_NAME/libavutil/x86/asm.h $LIBRARY_PREFIX/include/libavutil/x86
cp -rf $LIBRARY_PREFIX/$LIBRARY_NAME/libavutil/x86/timer.h $LIBRARY_PREFIX/include/libavutil/x86
cp -rf $LIBRARY_PREFIX/$LIBRARY_NAME/libavutil/arm/timer.h $LIBRARY_PREFIX/include/libavutil/arm
cp -rf $LIBRARY_PREFIX/$LIBRARY_NAME/libavutil/aarch64/timer.h $LIBRARY_PREFIX/include/libavutil/aarch64
cp -rf $LIBRARY_PREFIX/$LIBRARY_NAME/libavutil/x86/emms.h $LIBRARY_PREFIX/include/libavutil/x86

popd &> /dev/null

# clean
rm -rf $LIBRARY_PREFIX/$LIBRARY_NAME
