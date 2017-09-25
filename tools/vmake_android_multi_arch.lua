-- vmake_android_multi_arch.lua

assert( ANDROID_ARCH, 'MUST after include vmake_android.lua')

function main()
	local target = vlua.match_arg('^[_%w]+$')
	if target then
		vmake(target)
	else
		print('usage : ./vmake <target> [-arch=*|x86_64|arm|arm64|...] [-api=21] [-debug]')
	end
end

if ANDROID_ARCH=='*' then
	local platforms = {}
	do
		local fs, ds = vlua.file_list( path_concat(ANDROID_NDK_ROOT, 'platforms', 'android-'..ANDROID_API_LEVEL) )
		for _, d in ipairs(ds) do
			local platform = d:match('^arch%-(.+)$')
			if platform then table.insert(platforms, platform) end
		end
	end

	local function fetch_command_with_out_target_and_arch()
		local app, script = vlua.fetch_self()
		local cmds = { app, script }
		for _,v in ipairs(vlua.fetch_args()) do
			if v:match('^%-arch=(.*)$') then
				-- ignore -arch
			elseif v:match('^[_%w]+$') then
				-- ignore target
			elseif v:match('^%-vmake%-depth=.*$') then
				-- ignore -vlua-depth
			else
				table.insert(cmds, v)
			end
		end
		return cmds
	end

	local raw_vmake = vmake

	vmake = function(...)
		local cmds = fetch_command_with_out_target_and_arch()
		local targets = table.pack(...)

		local depth = vlua.match_arg('^%-vmake%-depth=(%d+)$')
		depth = (math.tointeger(depth) or 0)
		local vmake_depth = string.format('-vmake-depth=%d', depth+1)

		for _, target in ipairs(targets) do
			for _, platform in ipairs(platforms) do
				local vmake_arch = string.format('-arch=%-6s', platform)
				local cmd = args_concat(cmds, vmake_depth, vmake_arch, target)
				print( '$ ' .. cmd )
				if not os.execute(cmd) then os.exit(1) end
			end
		end

		if depth==0 then
			-- TODO : after target build, may apk
			-- for _, target in ipairs(targets) do end
		end
	end
end

