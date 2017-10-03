-- vmake_android.lua

-- port from android cmake, see : <ndk>/build/cmake/android.toolchain.cmake

local host_tag = (vlua.OS=='windows') and 'windows-x86_64' or 'linux-x86_64'

-- android environ settings
-- 
ANDROID_SDK_ROOT        = vlua.match_arg('^%-sdk=(.+)$') or vlua.filename_format(vlua.path .. '/../android-sdk') -- default use <vlua-path>/../android-sdk
ANDROID_NDK_ROOT        = vlua.match_arg('^%-ndk=(.+)$') or vlua.filename_format(vlua.path .. '/../android-ndk') -- default use <vlua-path>/../android-ndk
ANDROID_TOOLCHAIN       = vlua.match_arg('^%-toolchain=(.+)$') or 'gcc' -- 'gcc' or 'clang'
ANDROID_API_LEVEL       = vlua.match_arg('^%-api=(.+)$') or '26' -- platform api level
ANDROID_ARCH            = vlua.match_arg('^%-arch=(.+)$') or '*' -- -arch=* means all, -arch="arm x86" mean multi, 'arm','arm64','x86','x86_64','mips','mips64'
ANDROID_PIE             = vlua.match_arg('^%-pie$') or (math.tointeger(ANDROID_API_LEVEL) < 16) -- true or false
ANDROID_ARM_MODE        = vlua.match_arg('^%-arm=(.+)$') or 'thumb' -- 'arm', 'thumb'
ANDROID_ARM_NEON        = vlua.match_arg('^%-arm%-neon$')
ANDROID_STL             = vlua.match_arg('^%-stl=(.+)$') or 'gnustl_static' -- 'system', 'stlport_static', 'stlport_shared', 'gnustl_static', 'gnustl_shared', 'c++_static', 'c++_shared', 'none'

local _ARCHS =
	{ ['arm']    = { name = 'arm-linux-androideabi',  prefix = 'arm-linux-androideabi',  abi = 'armeabi-v7a' }
	, ['arm64']  = { name = 'aarch64-linux-android',  prefix = 'aarch64-linux-android',  abi = 'arm64-v8a' }
	, ['x86']    = { name = 'x86',                    prefix = 'i686-linux-android',     abi = 'x86' }
	, ['x86_64'] = { name = 'x86_64',                 prefix = 'x86_64-linux-android',   abi = 'x86_64' }
	, ['mips']   = { name = 'mipsel-linux-android',   prefix = 'mipsel-linux-android',   abi = 'mips' }
	, ['mips64'] = { name = 'mips64el-linux-android', prefix = 'mips64el-linux-android', abi = 'mips64'}
	}

-- fetch toolchain name, prefix, abi by settings
-- 
do
	-- android environ exports
	-- 
	local tc = _ARCHS[ANDROID_ARCH] or _ARCHS['arm']

	ANDROID_TOOLCHAIN_NAME   = tc.name
	ANDROID_TOOLCHAIN_PREFIX = tc.prefix
	ANDROID_ABI              = tc.abi
end

-- android compiler tools
-- 
if ANDROID_TOOLCHAIN=='gcc' then
	ANDROID_TOOLCHAIN_ROOT = path_concat(ANDROID_NDK_ROOT, 'toolchains', ANDROID_TOOLCHAIN_NAME..'-4.9', 'prebuilt', host_tag)

	ANDROID_CC  = path_concat(ANDROID_TOOLCHAIN_ROOT, 'bin', ANDROID_TOOLCHAIN_PREFIX..'-gcc')
	ANDROID_CXX = path_concat(ANDROID_TOOLCHAIN_ROOT, 'bin', ANDROID_TOOLCHAIN_PREFIX..'-g++')
	ANDROID_AR  = path_concat(ANDROID_TOOLCHAIN_ROOT, 'bin', ANDROID_TOOLCHAIN_PREFIX..'-ar')

elseif ANDROID_TOOLCHAIN=='clang' then
	ANDROID_TOOLCHAIN_ROOT = path_concat(ANDROID_NDK_ROOT, 'toolchains', 'llvm', 'prebuilt', host_tag)

	ANDROID_CC  = path_concat(ANDROID_TOOLCHAIN_ROOT, 'bin', 'clang')
	ANDROID_CXX = path_concat(ANDROID_TOOLCHAIN_ROOT, 'bin', 'clang++')
	ANDROID_AR  = path_concat(ANDROID_TOOLCHAIN_ROOT, 'bin', '-llvm-ar')

else
	error('unknown toolchain:'..tostring(ANDROID_TOOLCHAIN))
end

-- Android NDK revision
-- 
function android_ndk_revision()
	for line in io.lines(path_concat(ANDROID_NDK_ROOT, 'source.properties')) do
		-- Pkg.Revision = 15.2.4203891
		local r1 = line:match('Pkg%.Revision%s*=%s*(%d+)%.')
		if r1 then return r1 end
	end
end

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

ANDROID_CXX_CFLAGS = {}
ANDROID_CXX_LIBS = {}

-- abi spec
-- 
if ANDROID_ABI=='armeabi' then
	array_push(ANDROID_CFLAGS, '-march=armv5te', '-mtune=xscale', '-msoft-float')

elseif ANDROID_ABI=='armeabi-v7a' then
	array_push(ANDROID_CFLAGS, '-march=armv7-a', '-mfloat-abi=softfp', '-mfpu=vfpv3-d16')
	array_push(ANDROID_LINKER_FLAGS, '-Wl,--fix-cortex-a8')

elseif ANDROID_ABI=='mips' then
	array_push(ANDROID_CFLAGS, '-mips32')
	if ANDROID_TOOLCHAIN=='clang' then
		-- Help clang use mips64el multilib GCC
		array_push(ANDROID_LINKER_FLAGS, '-L'..path_concat(ANDROID_TOOLCHAIN_ROOT, 'lib', 'gcc', ANDROID_TOOLCHAIN_NAME, '4.9.x', '32', 'mips-r1'))
	end
	
elseif ANDROID_ABI=='mips64' then
	if ANDROID_TOOLCHAIN=='clang' then
		array_push(ANDROID_CFLAGS, '-fintegrated-as')
	end

elseif ANDROID_ABI:match('^armeabi') then
	if ANDROID_TOOLCHAIN=='clang' then
		-- Disable integrated-as for better compatibility.
		array_push(ANDROID_CFLAGS, '-fno-integrated-as')
	end

elseif ANDROID_ABI=='x86' then
	-- http://b.android.com/222239
	-- http://b.android.com/220159 (internal http://b/31809417)
	-- x86 devices have stack alignment issues.
	-- 
	array_push(ANDROID_CFLAGS, '-mstackrealign')
end

-- pie
-- 
if ANDROID_PIE then
	array_push(ANDROID_LINKER_FLAGS, '-pie', '-fPIE')
end

-- cpp features, default not use this
-- 
-- array_push(ANDROID_CXX_CFLAGS, '-frtti', '-fexceptions')

-- arm mode / neon
-- 
if ANDROID_ABI:match('armeabi') then
	if ANDROID_ARM_MODE=='thumb' then
		array_push(ANDROID_CFLAGS, '-mthumb')
	elseif ANDROID_ARM_MODE=='arm' then
		array_push(ANDROID_CFLAGS, '-marm')
	else
		error('invalid android ARM mode:'..tostring(ANDROID_ARM_MODE))
	end

	if ANDROID_ABI=='armeabi-v7a' and ANDROID_ARM_NEON then
		array_push(ANDROID_CFLAGS, '-mfpu=neon')
	end
end

-- debug & release
-- 
if vlua.match_arg('^%-debug$') then
	array_push(ANDROID_CFLAGS, '-D_DEBUG', '-O0')
	if ANDROID_TOOLCHAIN=='clang' then
		array_push(ANDROID_CFLAGS, '-fno-limit-debug-info')
	end
elseif ANDROID_ABI:match('^armeabi') then
	array_push(ANDROID_CFLAGS, '-DNDEBUG', '-Os')
else
	array_push(ANDROID_CFLAGS, '-DNDEBUG', '-O2')
end

-- STL specific flags.
-- 
do
	local stl_prefix
	local stl_incs = {}

	local function cxx_libs_add_static_lib(stl)
		array_push(ANDROID_CXX_LIBS, path_concat(ANDROID_NDK_ROOT, 'sources', 'cxx-stl', stl_prefix, 'libs', ANDROID_ABI, 'lib'..stl..'.a'))
	end

	local function cxx_libs_add_shared_lib(stl)
		array_push(ANDROID_CXX_LIBS, path_concat(ANDROID_NDK_ROOT, 'sources', 'cxx-stl', stl_prefix, 'libs', ANDROID_ABI, 'lib'..stl..'.so'))
	end

	if ANDROID_STL=='system' then
		stl_prefix = {'gnu-libstdc++', '4.9'}
		array_push(stl_incs, path_concat(ANDROID_NDK_ROOT, 'sources', 'cxx-stl', 'system', 'include'))
		cxx_libs_add_static_lib('supc++')

	elseif ANDROID_STL:match('^stlport_') then
		stl_prefix = 'stlport'
		array_push(stl_incs, path_concat(ANDROID_NDK_ROOT, 'sources', 'cxx-stl', stl_prefix, 'stlport'))
		array_push(stl_incs, path_concat(ANDROID_NDK_ROOT, 'sources', 'cxx-stl', 'gabi++', 'include'))
		if ANDROID_STL=='stlport_static' then
			cxx_libs_add_static_lib(ANDROID_STL)
		elseif ANDROID_STL=='stlport_shared' then
			cxx_libs_add_shared_lib(ANDROID_STL)
		else
			error('unknown stl:'..tostring(ANDROID_STL))
		end

	elseif ANDROID_STL:match('^gnustl_') then
		stl_prefix = { 'gnu-libstdc++', '4.9' }
		array_push(stl_incs, path_concat(ANDROID_NDK_ROOT, 'sources', 'cxx-stl', stl_prefix, 'include'))
		array_push(stl_incs, path_concat(ANDROID_NDK_ROOT, 'sources', 'cxx-stl', stl_prefix, 'libs', ANDROID_ABI, 'include'))
		array_push(stl_incs, path_concat(ANDROID_NDK_ROOT, 'sources', 'cxx-stl', stl_prefix, 'include', 'backward'))
		if ANDROID_STL=='gnustl_static' then
			cxx_libs_add_static_lib(ANDROID_STL)
		elseif ANDROID_STL=='gnustl_shared' then
			cxx_libs_add_static_lib('supc++')
			cxx_libs_add_shared_lib(ANDROID_STL)
		else
			error('unknown stl:'..tostring(ANDROID_STL))
		end

	elseif ANDROID_STL:match('^c%+%+_') then
		stl_prefix = { 'llvm-libc++' }
		if ANDROID_ABI:match('^armeabi') then
			array_push(ANDROID_LINKER_FLAGS, '-Wl,--exclude-libs,libunwind.a')
		end
		array_push(ANDROID_CXX_CFLAGS, '-std=c++11')
		if ANDROID_TOOLCHAIN=='gcc' then
			array_push(ANDROID_CXX_CFLAGS, '-fno-strict-aliasing')
		end

		-- Add the libc++ lib directory to the path so the linker scripts can pick up the extra libraries.
		array_push(ANDROID_LINKER_FLAGS, '-L'..path_concat(ANDROID_NDK_ROOT, 'sources', 'cxx-stl', stl_prefix, 'libs', ANDROID_ABI))

		array_push(stl_incs, path_concat(ANDROID_NDK_ROOT, 'sources', 'cxx-stl', stl_prefix, 'include'))
		array_push(stl_incs, path_concat(ANDROID_NDK_ROOT, 'sources', 'android', 'support', 'include'))
		array_push(stl_incs, path_concat(ANDROID_NDK_ROOT, 'sources', 'cxx-stl', stl_prefix..'abi', 'include'))

		if ANDROID_STL=='c++_static' then
			cxx_libs_add_static_lib('c++')
		elseif ANDROID_STL=='c++_shared' then
			cxx_libs_add_shared_lib('c++')
		else
			error('unknown stl:'..tostring(ANDROID_STL))
		end

	elseif ANDROID_STL=='none' then
		-- no stl

	else
		error('unknown stl:'..tostring(ANDROID_STL))
	end

	if ANDROID_ABI=='armeabi' and (ANDROID_STL~='system' and ANDROID_STL~='none') then
		array_push(ANDROID_CXX_LIBS, '-latomic')
	end
end


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

-- apk utils
-- 
function android_apk_build(target, outpath)
	local aapt = path_concat(ANDROID_SDK_BUILD_TOOL_ROOT, 'aapt')
	local dst = path_concat(outpath, target)
	local src = path_concat('..', '..', target)
	local ap_ = target..'.ap_'
	local apk = target..'.apk'

	-- compile res
	shell_execute( 'cd '..dst.. ' &&'	-- use <dst> path
		, aapt, 'package', '-f'
		, '-F', ap_
		, '-S', path_concat(src, 'res')
		, '-M', path_concat(src, 'AndroidManifest.xml')
		, '-I', path_concat(ANDROID_SDK_ROOT, 'platforms', 'android-'..ANDROID_API_LEVEL, 'android.jar')
		)

	-- add libs
	local libs = scan_files(path_concat(dst, 'lib'), function(v) return v end, true)
	for _, f in ipairs(libs) do
		shell_execute( 'cd '..dst.. ' &&'	-- use <dst> path
			, aapt, 'a', '-v', ap_
			, path_concat('lib', f)
			)
	end

	-- signer
	shell_execute( 'cd '..dst.. ' &&'	-- use <dst> path
		, 'jarsigner'
		-- , '-digestalg SHA1', '-sigalg MD5withRSA'
		-- , '-tsa', 'http://tsa.starfieldtech.com'
		, '-keystore', path_concat('..', '..', 'keystore', 'study_android_ndk.keystore')
		, '-storepass', 'study_android_ndk'
		, '-keypass', 'study_android_ndk'
		, '-signedjar', apk
		, ap_
		, 'StudyAndroidNDK'
		)
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
		print('usage: ./vmake <target> [-options ...]')
		print('options:')
		local function print_exist(option, exist)
			if exist then
				print('  ' .. option)
			else
				print('  [' .. option .. ']')
			end
		end
		print('  -sdk='..ANDROID_SDK_ROOT)
		print('  -ndk='..ANDROID_NDK_ROOT)
		print('  -toolchain='..ANDROID_TOOLCHAIN)
		print('  -api='..ANDROID_API_LEVEL)
		print('  -arch='..ANDROID_ARCH)
		print('  -stl='..ANDROID_STL)
		print_exist('-pie', ANDROID_PIE)
		print_exist('-debug', vlua.match_arg('^%-debug$'))
		print('  -arm='..ANDROID_ARM_MODE)
		print_exist('-arm-neon', ANDROID_ARM_NEON)
		return
	end

	local depth = vlua.match_arg('^%-vmake%-depth=(%d+)$')
	depth = (math.tointeger(depth) or 0)

	if _ARCHS[ANDROID_ARCH] then
		vmake(table.unpack(targets))
	else
		local platforms = {}
		if ANDROID_ARCH=='*' then
			local fs, ds = vlua.file_list( path_concat(ANDROID_NDK_ROOT, 'platforms', 'android-'..ANDROID_API_LEVEL) )
			for _, d in ipairs(ds) do
				local platform = d:match('^arch%-(.+)$')
				if platform then table.insert(platforms, platform) end
			end
		else
			for platform in ANDROID_ARCH:gmatch('[_%w]+') do
				if not _ARCHS[platform] then error('bad -arch: '..platform) end
				table.insert(platforms, platform)
			end
		end

		local cmds = { vlua.self, vlua.script }
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
	end

	if depth==0 and android_after_vmake_target then
		for _, t in ipairs(targets) do
			android_after_vmake_target(t)
		end
	end
end

