-- vmake_android.lua

-- see : ndk/build/cmake/android.toolchain.cmake

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

function get_android_cflags(ndk_root, arch, api_level)
	local toolchain = _TOOLCHAINS[arch]
	if not toolchain then error('not support arch:'..tostring(arch)) end
	local sysroot = path_concat(ndk_root, 'platforms', 'android-'..api_level, 'arch-'..arch)
	local flags = 
		{ '-DANDROID'
		, '-ffunction-sections'
		, '-funwind-tables'
		, '-fstack-protector-strong'
		, '-no-canonical-prefixes'
		, '--sysroot='..sysroot
		}

	if toolchain.abi=='armeabi' then
		flags = array_pack(flags, '-march=armv5te', '-mtune=xscale', '-msoft-float')
	elseif toolchain.abi=='armeabi-v7a' then
		flags = array_pack(flags, '-march=armv7-a', '-mfloat-abi=softfp', '-mfpu=vfpv3-d16')
	elseif toolchain.abi=='mips' then
		flags = array_pack(flags, '-mips32')
	end

	-- http://b.android.com/222239
	-- http://b.android.com/220159 (internal http://b/31809417)
	-- x86 devices have stack alignment issues.
	if arch=='x86' then table.insert(flags, '-mstackrealign') end

	return flags
end

function get_android_linker_flags(arch)
	local toolchain = _TOOLCHAINS[arch]
	if not toolchain then error('not support arch:'..tostring(arch)) end
	local flags =
		{ '-Wl,--build-id'
		, '-Wl,--warn-shared-textrel'
		, '-Wl,--fatal-warnings'
		}

	if toolchain.abi=='armeabi-v7a' then table.insert(flags, '-Wl,--fix-cortex-a8') end

	return flags
end

function get_android_abi(arch)
	local toolchain = _TOOLCHAINS[arch]
	if not toolchain then error('not support arch:'..tostring(arch)) end
	return toolchain.abi
end

function get_gcc_toolchain_binprefix(ndk_root, arch, gcc_ver)
	local host_os = (vlua.OS=='windows') and 'windows' or 'linux'
	local host_arch = (vlua.OS=='windows') and 'x86_64' or shell('uname -m')
	local toolchain = _TOOLCHAINS[arch]
	if not toolchain then error('not support arch:'..tostring(arch)) end
	return path_concat(ndk_root, 'toolchains'
			, toolchain.name..'-'..gcc_ver
			, 'prebuilt'
			, host_os..'-'..host_arch
			, 'bin'
			, toolchain.prefix..'-'
			)
end

function vmake_target_with_all_archs(ndk_root, api_level)
	if not vlua.thread_pool then return end	-- skip work thread
	main = function() end	-- skip default main()

	local app, script = vlua.fetch_self()
	local cmds = { app, script }
	for _,v in ipairs(vlua.fetch_args()) do
		if not v:match('^%-arch=(.*)$') then table.insert(cmds, v) end
	end

	local fs, ds = vlua.file_list( path_concat(ndk_root, 'platforms', 'android-'..api_level) )
	for _, d in ipairs(ds) do
		local platform = d:match('^arch%-(.+)$')
		if platform then
			local cmd = args_concat(cmds, '-arch='..platform)
			print( cmd )
			vlua.thread_pool:run(platform, 'os.execute', cmd)
		end
	end
	vlua.thread_pool:wait(function(platform, ok, res, code)
		if not ok then
			print( string.format('build platform(%s) failed: %s %s!', platform, res, code) )
			os.exit(code)
		end
	end)
end