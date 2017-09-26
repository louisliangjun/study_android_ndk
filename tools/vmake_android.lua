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
local _ABS_PATH = shell((vlua.OS=='windows') and 'cd .. && cd' or 'cd .. && pwd')

ANDROID_SDK_ROOT         = path_concat(_ABS_PATH, 'android-sdk')
ANDROID_NDK_ROOT         = path_concat(_ABS_PATH, 'android-ndk')
ANDROID_ARCH             = vlua.match_arg('^%-arch=(.*)$') or '*'
ANDROID_API_LEVEL        = vlua.match_arg('^%-api=(.*)$') or '21'
ANDROID_GCC_VERSION      = vlua.match_arg('^%-gcc%-ver=(.*)$') or '4.9'

local _TOOLCHAIN = _TOOLCHAINS[ANDROID_ARCH] or _TOOLCHAINS['x86_64']

ANDROID_TOOLCHAIN_NAME   = _TOOLCHAIN.name
ANDROID_TOOLCHAIN_PREFIX = _TOOLCHAIN.prefix
ANDROID_TOOLCHAIN_ABI    = _TOOLCHAIN.abi

ANDROID_TOOLCHAIN_BIN_PREFIX = (function()
	local HOST_OS = (vlua.OS=='windows') and 'windows' or 'linux'
	local HOST_ARCH = (vlua.OS=='windows') and 'x86_64' or shell('uname -m')

	return path_concat(ANDROID_NDK_ROOT
			, 'toolchains'
			, ANDROID_TOOLCHAIN_NAME..'-'..ANDROID_GCC_VERSION
			, 'prebuilt'
			, HOST_OS..'-'..HOST_ARCH
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

-- TODO : how to find right aapt ?? which file or iter dir ?? or sdk/tools/source.properties(Revision=26.0.1)
-- 
ANDROID_SDK_BUILD_TOOL_ROOT = path_concat(ANDROID_SDK_ROOT, 'build-tools', '26.0.1')
do
	local aapt = (vlua.OS=='windows' and 'aapt.exe' or 'aapt')
	local pth = path_concat(ANDROID_SDK_ROOT, 'build-tools')
	local fs, ds = vlua.file_list(pth)
	for _, d in ipairs(ds) do
		if vlua.file_stat(path_concat(pth, d, aapt)) then
			ANDROID_SDK_BUILD_TOOL_ROOT = path_concat(pth, d)
			break
		end
	end
end

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

-- multi arch compile supports
-- 
function main()
	local targets = {}
	for _,v in ipairs(vlua.fetch_args()) do
		local t = v:match('^[_%w]+$')
		if t then table.insert(targets, t) end
	end

	if #targets==0 then
		print('usage : ./vmake <target> [-arch=*|x86_64|arm|arm64|...] [-api=21] [-debug]')
		return
	end

	local depth = vlua.match_arg('^%-vmake%-depth=(%d+)$')
	depth = (math.tointeger(depth) or 0)

	if ANDROID_ARCH=='*' then
		local platforms = {}
		do
			local fs, ds = vlua.file_list( path_concat(ANDROID_NDK_ROOT, 'platforms', 'android-'..ANDROID_API_LEVEL) )
			for _, d in ipairs(ds) do
				local platform = d:match('^arch%-(.+)$')
				if platform then table.insert(platforms, platform) end
			end
		end

		local app, script = vlua.fetch_self()
		local cmds = { app, script }
		for _,v in ipairs(vlua.fetch_args()) do
			if v:match('^%-arch=(.*)$') then
				-- ignore -arch=XX
			elseif v:match('^%-vmake%-depth=.*$') then
				-- ignore -vlua-depth=XX
			else
				table.insert(cmds, v)
			end
		end

		local vmake_depth = string.format('-vmake-depth=%d', depth+1)

		for _, platform in ipairs(platforms) do
			local vmake_arch = string.format('-arch=%s', platform)
			local cmd = args_concat(cmds, vmake_depth, vmake_arch)
			print( '$ ' .. cmd )
			if not os.execute(cmd) then os.exit(1) end
		end
	else
		vmake(table.unpack(targets))
	end

	if depth==0 and android_after_vmake_target then
		for _, t in ipairs(targets) do
			android_after_vmake_target(t)
		end
	end
end

