-- vmake_android.lua

-- port from android cmake, see : <ndk>/build/cmake/android.toolchain.cmake

local host_tag = (vlua.OS=='windows') and 'windows-x86_64' or 'linux-x86_64'

-- android environ settings
-- 
ANDROID_SDK_ROOT        = vlua.match_arg('^%-sdk=(.+)$') or path_concat(vlua.filename_format(vlua.path .. '/../'), 'android-sdk') -- default use <vlua-path>/../android-sdk
ANDROID_NDK_ROOT        = vlua.match_arg('^%-ndk=(.+)$') or path_concat(vlua.filename_format(vlua.path .. '/../'), 'android-ndk') -- default use <vlua-path>/../android-ndk
ANDROID_TOOLCHAIN       = vlua.match_arg('^%-toolchain=(.+)$') or 'gcc' -- 'gcc' or 'clang'
ANDROID_API_LEVEL       = vlua.match_arg('^%-api=(.+)$') or '26' -- platform api level
ANDROID_ABI             = vlua.match_arg('^%-abi=(.+)$') or '*' -- "-abi=*" means all, "-abi=armeabi-v7a -abi=x86" mean multi, ABIS: armeabi,armeabi-v7a,arm64-v8a,mips,mips64,x86,x86_64
ANDROID_PIE             = vlua.match_arg('^%-pie$') or (math.tointeger(ANDROID_API_LEVEL) < 16) -- true or false
ANDROID_ARM_MODE        = vlua.match_arg('^%-arm=(.+)$') or 'thumb' -- 'arm', 'thumb'
ANDROID_ARM_NEON        = vlua.match_arg('^%-arm%-neon$')
ANDROID_STL             = vlua.match_arg('^%-stl=(.+)$') or 'gnustl_static' -- 'system', 'stlport_static', 'stlport_shared', 'gnustl_static', 'gnustl_shared', 'c++_static', 'c++_shared', 'none'
ANDROID_DEBUG_MODE      = vlua.match_arg('^%-debug$')

local _ABIS =
	{ ['armeabi']       = { name = 'arm-linux-androideabi',  prefix = 'arm-linux-androideabi',  arch = 'arm' }
	, ['armeabi-v7a']   = { name = 'arm-linux-androideabi',  prefix = 'arm-linux-androideabi',  arch = 'arm' }
	, ['arm64-v8a']     = { name = 'aarch64-linux-android',  prefix = 'aarch64-linux-android',  arch = 'arm64' }
	, ['x86']           = { name = 'x86',                    prefix = 'i686-linux-android',     arch = 'x86' }
	, ['x86_64']        = { name = 'x86_64',                 prefix = 'x86_64-linux-android',   arch = 'x86_64' }
	, ['mips']          = { name = 'mipsel-linux-android',   prefix = 'mipsel-linux-android',   arch = 'mips' }
	, ['mips64']        = { name = 'mips64el-linux-android', prefix = 'mips64el-linux-android', arch = 'mips64'}
	}

-- fetch toolchain name, prefix, abi by settings
-- 
do
	-- android environ exports
	-- 
	local tc = _ABIS[ANDROID_ABI] or _ABIS['armeabi-v7a']

	ANDROID_TOOLCHAIN_NAME   = tc.name
	ANDROID_TOOLCHAIN_PREFIX = tc.prefix
	ANDROID_ARCH             = tc.arch
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
	ANDROID_AR  = path_concat(ANDROID_TOOLCHAIN_ROOT, 'bin', 'llvm-ar')

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

ANDROID_LINKER_FLAGS_EXE =
	{ '-Wl,--gc-sections'
	, '-Wl,-z,nocopyreloc'
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
	array_push(ANDROID_LINKER_FLAGS_EXE, '-pie', '-fPIE')
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
if ANDROID_DEBUG_MODE then
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

	for _, pth in ipairs(stl_incs) do
		array_push(ANDROID_CXX_CFLAGS, '-I'..pth)
	end

	if ANDROID_ABI=='armeabi' and (ANDROID_STL~='system' and ANDROID_STL~='none') then
		array_push(ANDROID_CXX_LIBS, '-latomic')
	end
end


-- TODO : how to find right aapt ?? which file or iter dir ?? or sdk/tools/source.properties(Revision=26.0.2)
-- 
ANDROID_SDK_BUILD_TOOL_ROOT = path_concat(ANDROID_SDK_ROOT, 'build-tools', '26.0.2')
do
	local aapt = (vlua.OS=='windows' and 'aapt.exe' or 'aapt')
	if not vlua.file_stat(path_concat(ANDROID_SDK_BUILD_TOOL_ROOT, aapt)) then
		local pth = path_concat(ANDROID_SDK_ROOT, 'build-tools')
		local fs, ds = vlua.file_list(pth)
		for _, d in ipairs(ds) do
			if vlua.file_stat(path_concat(pth, d, aapt)) then
				ANDROID_SDK_BUILD_TOOL_ROOT = path_concat(pth, d)
				break
			end
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
		, ANDROID_DEBUG_MODE and '--debug-mode' or ''
		, '-I', path_concat(ANDROID_SDK_ROOT, 'platforms', 'android-'..ANDROID_API_LEVEL, 'android.jar')
		)

	-- add libs
	local libs = scan_files(path_concat(dst, 'lib'), function(v) return v end, true)
	for _, f in ipairs(libs) do
		shell_execute( 'cd '..dst.. ' &&'	-- use <dst> path
			, aapt, 'a', '-v', ap_
			, string.format('lib/%s', f)	-- NOTICE: can not use path_concat() in windows.
			)
	end

	-- signer
	-- 
	shell_execute( 'cd '..dst.. ' &&'	-- use <dst> path
		, path_concat(ANDROID_SDK_BUILD_TOOL_ROOT, 'apksigner'), 'sign'
		, '--ks', path_concat('..', '..', '..', 'keystore', 'study_android_ndk.keystore')
		, '--ks-key-alias', 'StudyAndroidNDK'
		, '--ks-pass', 'pass:study_android_ndk'
		, '--key-pass', 'pass:study_android_ndk'
		, '--out', apk
		, ap_
		)
end

-- help
-- 
local function show_help()
	print('usage: ./vmake <target> [-options ...]')
	print()
	print('targets:')
	local targets = {}
	for k in pairs(vmake_target_all()) do table.insert(targets, k) end
	table.sort(targets)
	for _, target in ipairs(targets) do print('  ' .. target) end
	print()
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
	print('  -abi='..ANDROID_ABI)
	print('  -stl='..ANDROID_STL)
	print_exist('-pie', ANDROID_PIE)
	print_exist('-debug', ANDROID_DEBUG_MODE)
	print('  -arm='..ANDROID_ARM_MODE)
	print_exist('-arm-neon', ANDROID_ARM_NEON)
	print()
end

-- multi arch compile supports
-- 
local function vmake_multi_abis(depth, targets)
	local abis = {}
	local args = vlua.fetch_args()

	if ANDROID_ABI=='*' then
		for k,v in pairs(_ABIS) do
			local jni_h = path_concat(ANDROID_NDK_ROOT, 'platforms', 'android-'..ANDROID_API_LEVEL, 'arch-'..v.arch, 'usr', 'include', 'jni.h')
			if vlua.file_stat(jni_h) then table.insert(abis, k) end
		end
	else
		for _,v in ipairs(args) do
			local abi = v:match('^%-abi=(.*)$')
			if abi then table.insert(abis, abi) end
		end
		if #abis==1 then return vmake(table.unpack(targets)) end
	end

	local cmds = { vlua.self, vlua.script }
	for _,v in ipairs(args) do
		if v:match('^%-abi=(.*)$') then
			-- ignore all -abi
		elseif v:match('^%-vmake%-depth=.*$') then
			-- ignore -vlua-depth=XX
		else
			table.insert(cmds, v)
		end
	end

	local vmake_depth = string.format('-vmake-depth=%d', depth+1)
	for _, abi in ipairs(abis) do
		local vmake_abi = string.format('-abi=%s', abi)
		local cmd = args_concat(cmds, vmake_depth, vmake_abi)
		print( '$ ' .. cmd )
		if not os.execute(cmd) then os.exit(1) end
	end
end

function main()
	local targets = {}
	for _,v in ipairs(vlua.fetch_args()) do
		local t = v:match('^[_%w]+$')
		if t then table.insert(targets, t) end
	end

	if #targets==0 then return show_help() end

	local depth = vlua.match_arg('^%-vmake%-depth=(%d+)$')
	depth = (math.tointeger(depth) or 0)

	if depth > 0 then
		vmake(table.unpack(targets))
	else
		vmake_multi_abis(depth, targets)
	end

	if depth==0 and android_after_vmake_target then
		for _, t in ipairs(targets) do
			android_after_vmake_target(t)
		end
	end
end

