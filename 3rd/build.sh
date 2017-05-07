TRD=`pwd`
echo "3rd path is : $TRD"

case $1 in
	ffi)
		tar zxvf libffi-3.2.1.tar.gz
		cd libffi-3.2.1
		./configure --enable-shared=no --enable-static=yes --prefix=$TRD/libffi-3.2.1
		make -j8
		make install
		;;
	lua)
		tar zxvf lua-5.3.4.tar.gz
		cd lua-5.3.4
		make $2 -j8
		;;
	mingw)
		./build.sh ffi
		./build.sh lua mingw
		;;
	*)
		echo "usage :"
		echo "	./build.sh mingw"
		echo "	./build.sh ffi"
		echo "	./build.sh lua mingw"
		;;
esac

