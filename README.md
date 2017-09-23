study android ndk
===========

project file struct
-----------

```
<this-dir>
  |
  +-- <android-ndk>        # android-ndk root path
  |
  +-- <3rd>                # some useful thrid-part-libs
  |
  +-- <samples>
  |     |
  |     +-- <demoXXX>
  |     |
  |     +-- vmake          # samples used makefile with vlua
  |     +-- vmake.cmd      # windows used vmake
  |
  +-- <tools>
  |     |
  |     +-- vlua/vlua.exe  # NOTICE : need build from vlua.c & lua53
  |     +-- vlua.c         # vlua source code
  |     +-- vmake_base.lua # vmake used lua utils
  |
  +-- readme.txt	# this file
```

vlua - make tool with lua script
-----------

* linux compile: gcc -s -O2 -pthread -Wall -o vlua ./vlua.c -llua -lm -ldl
* mingw compile: gcc -s -O2 -Wall -I./3rd/lua53 -o vlua ./vlua.c ./3rd/lua53/*.c -lm

* more tips: see ./tools/vlua.c

samples build
-----------

* all samples use one make script: ./samples/vmake
* usage : ./vmake [target] [-debug] [-api=21] [-arch=arm] [-jN] 

```
cd ./samples
./vmake
./vmake all -debug
./vmake all -arch=arm -j8
./vmake all -arch=arm -debug
./vmake demo1 -debug -arch=arm
./vmake demo1 -debug -api=25 -arch=amd64
```

* more tips: see ./samples/vmake

