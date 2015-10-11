local isAfkResetEnabled
local md
local lastWarnTimes = {}
local lastMoveTimes = {}
local mayEarnRemovedFromPlayByAfkKarma = {}

local function resetAfk(client)
	if isAfkResetEnabled and client then
		Shine.Plugins.afkkick:ResetAFKTime(client)
	end
end

local function getAfkThresholdInSeconds()
	local isEarlyOrPreGame = (TGNS.GetCurrentGameDurationInSeconds() or 0) < 30
	local result = isEarlyOrPreGame and 15 or 60
	return result, isEarlyOrPreGame
end

local Plugin = {}

-- function Plugin:OnProcessMove(player, input)
-- 	if bit.band(input.commands, Move.Use) ~= 0 then
-- 		resetAfk(TGNS.GetClient(player))
-- 	end
-- end

function Plugin:PlayerSay(client, networkMessage)
	resetAfk(client)
end

function Plugin:PostJoinTeam(gamerules, player, oldTeamNumber, newTeamNumber, force, shineForce)
	local client = TGNS.GetClient(player)
    if TGNS.IsPlayerReadyRoom(player) then
    	if TGNS.IsGameplayTeamNumber(oldTeamNumber) and TGNS.IsGameInProgress() and TGNS.GetCurrentGameDurationInSeconds() > 30 and TGNS.IsPlayerAFK(player) and #TGNS.GetPlayingClients(TGNS.GetPlayerList()) >= 7 and (not (force or shineForce)) then
    		if mayEarnRemovedFromPlayByAfkKarma[client] then
	    		TGNS.Karma(client, "RemovedFromPlayByAFK")
	    		mayEarnRemovedFromPlayByAfkKarma[client] = false
    		end
    	end
    	TGNS.MarkPlayerAFK(player)
    elseif not (force or shineForce) then
    	TGNS.ClearPlayerAFK(player)
    end
end

function Plugin:Initialise()
    self.Enabled = true
    md = TGNSMessageDisplayer.Create("AFK")

	TGNS.RegisterEventHook("AfkChanged", function(player, playerIsAfk)
		local client = TGNS.GetClient(player)
		if not playerIsAfk then
			mayEarnRemovedFromPlayByAfkKarma[client] = true
		end
	end)

    TGNS.ScheduleAction(5, function()
    	isAfkResetEnabled = Shine.Plugins.afkkick and Shine.Plugins.afkkick.Enabled and Shine.Plugins.afkkick.ResetAFKTime
    end)
	local originalGetCanPlayerHearPlayer
	originalGetCanPlayerHearPlayer = TGNS.ReplaceClassMethod("NS2Gamerules", "GetCanPlayerHearPlayer", function(self, listenerPlayer, speakerPlayer)
		resetAfk(TGNS.GetClient(speakerPlayer))
		return originalGetCanPlayerHearPlayer(self, listenerPlayer, speakerPlayer)
	end)

	local processAfkPlayers
	processAfkPlayers = function()
		local afkThresholdInSeconds, isEarlyOrPreGame = getAfkThresholdInSeconds();
		local afkScenarioDescriptor = isEarlyOrPreGame and " (pre/early game)" or ""
		TGNS.ScheduleAction(isEarlyOrPreGame and 1 or 15, processAfkPlayers)
		TGNS.DoFor(TGNS.GetHumanClientList(), function(c)
			local p = TGNS.GetPlayer(c)
			if TGNS.IsPlayerAFK(p) then
				local lastMoveTime = Shine.Plugins.afkkick:GetLastMoveTime(c)
				if (lastMoveTime ~= nil) and (TGNS.GetSecondsSinceMapLoaded() - lastMoveTime >= afkThresholdInSeconds) and TGNS.ClientIsOnPlayingTeam(c) then
					local lastWarnTime = lastWarnTimes[c] or 0
					if Shared.GetTime() - lastWarnTime > 10 then
						md:ToPlayerNotifyInfo(p, string.format("AFK %s%s. Move to avoid being sent to Ready Room.", Pluralize(afkThresholdInSeconds, "second"), afkScenarioDescriptor))
						lastWarnTimes[c] = Shared.GetTime()
					end
					TGNS.ScheduleAction(6, function()
						if Shine:IsValidClient(c) then
							p = TGNS.GetPlayer(c)
							if TGNS.IsPlayerAFK(p) then
								local lastMoveTime = lastMoveTimes[c] or 0
								if Shared.GetTime() - lastMoveTime > 10 then
									md:ToPlayerNotifyInfo(p, string.format("AFK %s%s. Moved to Ready Room.", Pluralize(afkThresholdInSeconds, "second"), afkScenarioDescriptor))
									TGNS.SendToTeam(p, kTeamReadyRoom, true)
									lastMoveTimes[c] = Shared.GetTime()
								end
							end
						end
					end)
				end
			end
		end)
	end
	TGNS.ScheduleAction(15, processAfkPlayers)
    return true
end

function Plugin:Cleanup()
    --Cleanup your extra stuff like timers, data etc.
    self.BaseClass.Cleanup( self )
end

Shine:RegisterExtension("afkkickhelper", Plugin )