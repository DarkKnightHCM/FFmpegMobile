# FFmpeg for Mobile

Simple build script for FFmpeg library for Mobile Platform
FFmpeg Version 5+

 Platform | Build Status
 -------- | ------------
 Android | OK
 iOS | N/A
 tvOS | N/A

### Build Environment
- Android - Minimum version required
 - [NDK r20b](http://developer.android.com/tools/sdk/ndk/index.html)
- iOS
 - XCode 13.4

### Before Build
##### Android
```
# add these lines to your ~/.bash_profile or ~/.profile
# export ANDROID_SDK=<your sdk path>
# export ANDROID_NDK=<your ndk path>
# Run ./init-source.sh to pull FFmpeg source from original repository
```
##### iOS
```
# set up XCode path
# sudo xcode-select -r
# sudo xcode-select -switch /Applications/Xcode.app/Contents/Developer
# XCODE_DIR=$(xcode-select -print-path)
# Run ./init-source.sh to pull FFmpeg source from original repository
```

### Build
```
Android
./android-ffmpeg.sh [arm64-v8a | armeabi-v7a | x86_64]
iOS
./ios-ffmpeg.sk [arm64 | armv7 | x86_64]
```

### License
```
Copyright (c) 2018
Licensed under LGPLv2.1 or later or later, so itself is free for commercial use under LGPLv2.1 or later
```