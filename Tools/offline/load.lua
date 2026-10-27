-- Loads the addon outside WoW (Lua 5.1, from the repo root): the .toc's
-- files in order, on a stand-in for the game (wow.lua), then the saved
-- settings arriving (ADDON_LOADED) and logging in, as a fresh install.
-- Returns ns, the addon's namespace, and the stand-in.
--
--   local ns, wow = dofile("Tools/offline/load.lua")("forever")

return function(client, toc)
	package.path = "Tools/offline/?.lua;" .. package.path
	local wow = dofile("Tools/offline/wow.lua")
	wow.Install(client)
	toc = toc or "Cinematic.toc"
	local addonName = toc:match("([^/]+)%.toc$")
	local ns = {}
	for line in io.lines(toc) do
		line = line:gsub("\r", "")
		if line ~= "" and not line:find("^#") then
			local path = line:gsub("\\", "/")
			local chunk, err = loadfile(path)
			-- (A file the build makes, like the dev copy's ChangelogCommits.dev.lua: skipped.)
			if not chunk and not err:find("cannot open") then error(err) end
			if chunk then
				local ok, runErr = pcall(chunk, addonName, ns)
				if not ok then wow.Warn(path .. ": " .. tostring(runErr)) end
			end
		end
	end
	wow.Fire("ADDON_LOADED", addonName)
	wow.Fire("PLAYER_LOGIN")
	return ns, wow
end
