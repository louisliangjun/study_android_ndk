-- vmake_android.lua

local _TOOLCHAINS =
	{ ['arm']    = { name='arm-linux-androideabi', prefix='arm-linux-androideabi' }
	, ['arm64']  = { name='aarch64-linux-android', prefix='aarch64-linux-android' }
	, ['x86']    = { name='x86', prefix='i686-linux-android' }
	, ['x86_64'] = { name='x86_64', prefix='x86_64-linux-android' }
	, ['mips']   = { name='mipsel-linux-android', prefix='mipsel-linux-android' }
	, ['mips64'] = { name='mips64el-linux-android', prefix='mips64el-linux-android' }
	}

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

function get_android_sysroot(ndk_root, arch, api_level)
	return path_concat(ndk_root, 'platforms', 'android-'..api_level, 'arch-'..arch)
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