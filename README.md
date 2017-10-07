study android ndk
===========

* for study, all samples NOT use ndk-build and AndroidStudio
* use lua as build script because of it's powerful, simple and very small
* all samples build script in samples/vmake
* android build utils in tools/vmake_android.lua
* vmake base utils in tools/vmake_base.lua
 
environ
-----------
* sdk need jdk8 support, make sure jre/bin in PATH

project file struct
-----------

```
<this-dir>
  |
  +-- <android-ndk>    # android-ndk root path
  +-- <android-sdk>    # android-sdk root path
  |
  +-- <3rd>            # some useful thrid-part-libs
  |
  +-- <samples>
  |     |
  |     +-- <hello>           # not app, run in console
  |     +-- <native_activity> # sample app copy from ndk samples, compile not use ndk-build & cmake
  |     +-- <nuklear>         # nuklear sample test on android
  |     |
  |     +-- vmake      # samples used makefile with vlua
  |     +-- vmake.cmd  # windows used vmake
  |
  +-- <keystore>
  |     |
  |     +-- study_android_ndk.keystore  # NOTICE : samples used keystore for apk sign
  |     +-- readme.txt                  # generate yourself keystore readme
  |
  +-- <tools>
  |     |
  |     +-- vlua/vlua.exe     # NOTICE : need build from vlua.c & lua53
  |     +-- vlua.c            # vlua source code
  |     +-- vmake_base.lua    # vmake used lua utils
  |     +-- vmake_android.lua # vmake used lua android utils
  |
  +-- README.txt	   # this file
```

vlua - make tool with lua script
-----------

* linux compile: gcc -s -O2 -pthread -Wall -o vlua ./vlua.c -llua -lm -ldl
* mingw compile: gcc -s -O2 -Wall -I./3rd/lua53 -o vlua ./vlua.c ./3rd/lua53/*.c -lm

* more tips: see ./tools/vlua.c

samples build
-----------

* all samples use one make script: ./samples/vmake
* usage : ./vmake [target] [-debug] [-api=26] [-abi=*] [-jN] 

```
cd ./samples
./vmake
./vmake all -debug
./vmake all -abi=armeabi-v7a -j8
./vmake all -abi=armeabi-v7a -abi=x86 -debug
./vmake native_activity -debug -abi=*
./vmake native_activity -debug -api=25 -abi=amd64
```

* more tips: see ./samples/vmake

