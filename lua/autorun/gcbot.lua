
if SERVER then

	include("gcbot/sv_plymeta.lua")
	include("gcbot/sv_gcbot.lua")

	include("gcbot/sh_gcbot.lua")

	/*
	if file.Exists("gcbot/modes/" .. engine.ActiveGamemode() .. ".lua", "GAME" ) then
		print("GCBot is loading gamemode specific code for " .. engine.ActiveGamemode())
		include("gcbot/modes/" .. engine.ActiveGamemode() .. ".lua")
	end
	*/
	include("gcbot/modes/groundcontrol.lua")

else

	include("gcbot/sh_gcbot.lua")
	AddCSLuaFile("gcbot/sh_gcbot.lua")

	AddCSLuaFile("gcbot/cl_gcbot.lua")

end