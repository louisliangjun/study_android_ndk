-- vmake_android_multi_arch.lua

assert( ANDROID_ARCH, 'MUST after include vmake_android.lua')

local raw_vmake_target_add = vmake_target_add

vmake_target_add_without_arch = raw_vmake_target_add

local function vmake_target_with_all_archs()
	vlua.thread_pool = vlua.thread_pool_create(1, vlua.__script)	-- reset 1 thread

	local app, script = vlua.fetch_self()
	local cmds = { app, script }
	for _,v in ipairs(vlua.fetch_args()) do
		if not v:match('^%-arch=(.*)$') then table.insert(cmds, v) end
	end

	local fs, ds = vlua.file_list( path_concat(ANDROID_NDK_ROOT, 'platforms', 'android-'..ANDROID_API_LEVEL) )
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

if ANDROID_ARCH=='*' then
	vmake_target_add = function(target, process)
		raw_vmake_target_add(target, function(...)
			return vmake_target_with_all_archs()
		end)
	end
end

