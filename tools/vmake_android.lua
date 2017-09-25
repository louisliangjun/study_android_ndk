-- vmake_android.lua

-- see : ndk/build/cmake/android.toolchain.cmake

-- consts
-- 
local _TOOLCHAINS =
	{ ['arm'] =
		{ name = 'arm-linux-androideabi'
		, prefix = 'arm-linux-androideabi'
		, abi = 'armeabi-v7a'
		}
	, ['arm64'] =
		{ name = 'aarch64-linux-android'
		, prefix = 'aarch64-linux-android'
		, abi = 'arm64-v8a'
		}
	, ['x86'] =
		{ name = 'x86'
		, prefix = 'i686-linux-android'
		, abi = 'x86'
		}
	, ['x86_64'] =
		{ name = 'x86_64'
		, prefix = 'x86_64-linux-android'
		, abi = 'x86_64'
		}
	, ['mips'] =
		{ name = 'mipsel-linux-android'
		, prefix = 'mipsel-linux-android'
		, abi = 'mips'
		}
	, ['mips64'] =
		{ name = 'mips64el-linux-android'
		, prefix='mips64el-linux-android'
		, abi='mips64'
		}
	}

local _ABI_FLAGS =
	{ ['armeabi'] =
		{ cflags = {'-march=armv5te', '-mtune=xscale', '-msoft-float'}
		}
	, ['armeabi-v7a'] =
		{ cflags = {}
		, linker_flags = {}
		}
	, ['mips'] =
		{ cflags = {}
		}
	}

-- android environ exports
-- 
ANDROID_NDK_ROOT         = '../android-ndk'
ANDROID_ARCH             = vlua.match_arg('^%-arch=(.*)$') or '*'
ANDROID_API_LEVEL        = vlua.match_arg('^%-api=(.*)$') or '21'
ANDROID_GCC_VERSION      = vlua.match_arg('^%-gcc%-ver=(.*)$') or '4.9'

local _TOOLCHAIN = _TOOLCHAINS[ANDROID_ARCH] or _TOOLCHAINS['x86_64']

ANDROID_TOOLCHAIN_NAME   = _TOOLCHAIN.name
ANDROID_TOOLCHAIN_PREFIX = _TOOLCHAIN.prefix
ANDROID_TOOLCHAIN_ABI    = _TOOLCHAIN.abi

ANDROID_TOOLCHAIN_BIN_PREFIX = (function()
	local host_os = (vlua.OS=='windows') and 'windows' or 'linux'
	local host_arch = (vlua.OS=='windows') and 'x86_64' or shell('uname -m')
	return path_concat(ANDROID_NDK_ROOT
			, 'toolchains'
			, ANDROID_TOOLCHAIN_NAME..'-'..ANDROID_GCC_VERSION
			, 'prebuilt'
			, host_os..'-'..host_arch
			, 'bin'
			, ANDROID_TOOLCHAIN_PREFIX..'-'
			)
end)()

ANDROID_CFLAGS = 
	{ '-DANDROID'
	, '-ffunction-sections'
	, '-funwind-tables'
	, '-fstack-protector-strong'
	, '-no-canonical-prefixes'
	, '--sysroot='..path_concat(ANDROID_NDK_ROOT, 'platforms', 'android-'..ANDROID_API_LEVEL, 'arch-'..ANDROID_ARCH)
	}

ANDROID_LINKER_FLAGS =
	{ '-Wl,--build-id'
	, '-Wl,--warn-shared-textrel'
	, '-Wl,--fatal-warnings'
	}

if ANDROID_TOOLCHAIN_ABI=='armeabi' then
	ANDROID_CFLAGS = array_pack(ANDROID_CFLAGS, '-march=armv5te', '-mtune=xscale', '-msoft-float')
elseif ANDROID_TOOLCHAIN_ABI=='armeabi-v7a' then
	ANDROID_CFLAGS = array_pack(ANDROID_CFLAGS, '-march=armv7-a', '-mfloat-abi=softfp', '-mfpu=vfpv3-d16')
	ANDROID_LINKER_FLAGS = array_pack(ANDROID_LINKER_FLAGS, '-Wl,--fix-cortex-a8')
elseif ANDROID_TOOLCHAIN_ABI=='mips' then
	ANDROID_CFLAGS = array_pack(ANDROID_CFLAGS, '-mips32')
end

-- http://b.android.com/222239
-- http://b.android.com/220159 (internal http://b/31809417)
-- x86 devices have stack alignment issues.
-- 
if ANDROID_ARCH=='x86' then
	ANDROID_CFLAGS = array_pack(ANDROID_CFLAGS, '-mstackrealign')
end

