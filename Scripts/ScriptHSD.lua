------------------------------------------------------------------------------
--	FILE:	 ScriptHSD.lua
--  Gedemon (2017)
--	changelog (Gathering Storm):
--	(*)	added ExposedMembers context for UI and Gameplay scripts
--	(*) City States will spawn based on their start date
--	(*) Units of other players in a starting plot will be killed before spawn (might prevent civs from failing to spawn)
--  (*) Civs start receiving free settlers during spawn in the medieval era, rather than classical era (helps preserve space for late starting civs)
------------------------------------------------------------------------------

local HSD_Version = GameInfo.GlobalParameters["HSD_VERSION"].Value
print ("Historical Spawn Dates version " .. tostring(HSD_Version) .." (2017) by Gedemon")
print ("loading ScriptHSD.lua")

-- totalslacker: added these to ExposedMembers for UI and Gameplay scripts to communicate after Gathering Storm update
ExposedMembers.LuaEvents = LuaEvents
ExposedMembers.GameEvents = GameEvents
ExposedMembers.CheckCity =	{}
ExposedMembers.CheckCityOriginalCapital = {}
ExposedMembers.GetPlayerCityUIDatas = {}

local bHistoricalSpawnDates		= MapConfiguration.GetValue("HistoricalSpawnDates")
local bApplyBalance				= MapConfiguration.GetValue("BalanceHSD")
local bSpawnDateTables			= MapConfiguration.GetValue("OldWorldStart")
local bEraBuilding				= MapConfiguration.GetValue("EraBuildingForAll")
print("bEraBuilding is "..tostring(bEraBuilding))

----------------------------------------------------------------------------------------
-- Historical Spawn Dates <<<<<
----------------------------------------------------------------------------------------
if bHistoricalSpawnDates then
----------------------------------------------------------------------------------------

print("Activating Historical Spawn Dates...")
local minimalStartYear 		= -4000000 -- Should cover every prehistoric start mod...
local previousTurnYear 		= GameConfiguration.GetValue("PreviousTurnYear") or minimalStartYear
local currentTurnYear 		= GameConfiguration.GetValue("CurrentTurnYear")
local nextTurnYear 		= GameConfiguration.GetValue("NextTurnYear")

local knownTechs		= {} 	-- Table to track each known tech (with number of civs) 
local knownCivics		= {}	-- Table to track each known civic (with number of civs) 
local researchedCivics	= {}	-- Table to track each researched civic 
local playersWithCity	= 0		-- Total number of major players with at least one city
local scienceBonus		= 0
local goldBonus			= 0
local settlersBonus		= 0
local tokenBonus		= 0
local faithBonus		= 0
local minCivForTech		= 1
local minCivForCivic	= 1
local currentEra		= 0

function Round(num)
    under = math.floor(num)
    upper = math.floor(num) + 1
    underV = -(under - num)
    upperV = upper - num
    if (upperV > underV) then
        return under
    else
        return upper
    end
end

-- Create list of Civilizations and leaders in game
local isInGame = {}
for iPlayer = 0, PlayerManager.GetWasEverAliveCount() - 1 do
	local CivilizationTypeName = PlayerConfigurations[iPlayer]:GetCivilizationTypeName()
	local LeaderTypeName = PlayerConfigurations[iPlayer]:GetLeaderTypeName()
	if CivilizationTypeName then isInGame[CivilizationTypeName] = true end
	if LeaderTypeName 		then isInGame[LeaderTypeName] 		= true end
end

-- Create list of spawn dates
print("Building spawn year table...")
local spawnDates = {}
if (bSpawnDateTables == 0) then
	print("Using Historical Spawn Dates for all Civs...")
	for row in GameInfo.HistoricalSpawnDates() do
		if isInGame[row.Civilization]  then
			spawnDates[row.Civilization] = row.StartYear
			print(tostring(row.Civilization), " spawn year = ", tostring(row.StartYear))
		end
	end
else
	print("Using Historical Spawn Dates for New World and Isolated Civs only...")
	for row in GameInfo.HistoricalSpawnDates_NewWorld() do
		if isInGame[row.Civilization]  then
			spawnDates[row.Civilization] = row.StartYear
			print(tostring(row.Civilization), " spawn year = ", tostring(row.StartYear))
		end
	end
end


-- Create list of Civilizations that don't receive starting bonuses
print("Building isolated civilizations table...")
local isolatedCivs = {}
for row in GameInfo.IsolatedCivs() do
	if isInGame[row.Civilization] then
		isolatedCivs[row.Civilization] = true
	end
end

-- Create list of Civilizations that receive an EraBuilding in every city
print("Building era bonuses civilizations table...")
local eraBuildingCivs = {}
for row in GameInfo.EraBuildingCivs() do
	if isInGame[row.Civilization] then
		eraBuildingCivs[row.Civilization] = true
	end
end

-- Create list of captured capitals
print("Building occupied capitals table...")

local occupiedCapitals = {}
function CheckOriginalCapital(iPlayer)
	local pPlayer = Players[iPlayer]
	local pPlayerCities:table = pPlayer:GetCities()
	for i, pCity in pPlayerCities:Members() do
		local pPlayerID = pPlayer:GetID()
		local pCityID = pCity:GetID()
		local bOriginalCapital = ExposedMembers.CheckCityOriginalCapital(pPlayerID, pCityID)
		if pCity and bOriginalCapital then	
			occupiedCapitals[bOriginalCapital] = true	
			print("Found an occupied capital")
		end
	end
end
-- GameEvents.PlayerTurnStarted.Add(CheckOriginalCapital)
-- Events.LoadScreenClose.Add(CheckOriginalCapital)

--[[
-- Set Starting Plots
for iPlayer, position in pairs(ExposedMembers.HistoricalStartingPlots) do
	local player = Players[iPlayer]
	if player then
		local startingPlot = Map.GetPlot(position.X, position.Y)
		player:SetStartingPlot(startingPlot)
	else
		print("WARNING: player #"..tostring(iPlayer) .." is nil for Set Starting Plots at ", position.X, position.Y)
	end
end
ExposedMembers.HistoricalStartingPlots = nil
--]]

function SetPreviousTurnYear(year)
	previousTurnYear = year
end
LuaEvents.SetPreviousTurnYear.Add( SetPreviousTurnYear )

function SetCurrentTurnYear(year)
	currentTurnYear = year
end
LuaEvents.SetCurrentTurnYear.Add( SetCurrentTurnYear )

function SetNextTurnYear(year)
	nextTurnYear = year
end
LuaEvents.SetNextTurnYear.Add( SetNextTurnYear )

local StartingEra = {}
function GetStartingEra(iPlayer)
	print("------------")
	local key = "StartingEra"..tostring(iPlayer)
	local value = GameConfiguration.GetValue(key)
	print("StartingEra[iPlayer] = "..tostring(StartingEra[iPlayer]))
	print("GameConfiguration.GetValue("..tostring(key)..") = "..tostring(value))
	return StartingEra[iPlayer] or value or 0
end

function SetStartingEra(iPlayer, era)
	LuaEvents.SetStartingEra(iPlayer, era)	-- saved/reloaded
	StartingEra[iPlayer] = era 				-- to keep the value in the current session, GameConfiguration.GetValue in this context will only work after a save/load
end

-- Remove Civilizations that can't be spawned on start date
function InitializeHSD()
	for iPlayer = 0, PlayerManager.GetWasEverAliveCount() - 1 do
		local CivilizationTypeName = PlayerConfigurations[iPlayer]:GetCivilizationTypeName()
		local spawnYear = spawnDates[CivilizationTypeName]
		print("---------")
		print("Check "..tostring(CivilizationTypeName)..", spawn year  = ".. tostring(spawnYear))
		local player = Players[iPlayer]
		if spawnYear and spawnYear > currentTurnYear then		
			-- if player:IsMajor() then
				-- local playerUnits = player:GetUnits()
				-- local toKill = {}
				-- for i, unit in playerUnits:Members() do
					-- table.insert(toKill, unit)
				-- end
				-- for i, unit in ipairs(toKill) do
					-- playerUnits:Destroy(unit)
				-- end
				-- if player:IsHuman() then
					-- LuaEvents.SetAutoValues()
				-- end
			-- end
			if player:IsMajor() then
				UnitManager.InitUnit(player, "UNIT_SETTLER", -1, -1)
				local playerUnits = player:GetUnits()
				local toKill = {}
				for i, unit in playerUnits:Members() do
					if(unit:GetX() >= 0 or  unit:GetY() >= 0) then
						table.insert(toKill, unit)
					end				
				end
				for i, unit in ipairs(toKill) do
					playerUnits:Destroy(unit)
				end	
				if player:IsHuman() then
					LuaEvents.SetAutoValues()
				end
			end			
			-- totalslacker: spawn city states according to historical spawn dates
			if not player:IsMajor() then
				UnitManager.InitUnit(player, "UNIT_SETTLER", -1, -1)
				local playerUnits = player:GetUnits()
				local toKill = {}
				for i, unit in playerUnits:Members() do
					if(unit:GetX() >= 0 or  unit:GetY() >= 0) then
						table.insert(toKill, unit)
					end				
				end
				for i, unit in ipairs(toKill) do
					playerUnits:Destroy(unit)
				end				
			end	
		end		
	end
end
LuaEvents.InitializeHSD.Add(InitializeHSD)

-- ===========================================================================
-- ===========================================================================
-- totalslacker: all credit for the following code goes to Tiramisu,
-- adapted from the Free City States mod with changes for this mod

function DeleteUnitsOffMap ( iPlayerID )
-- deletes all offmap units of the player	
	local pUnits = Players[iPlayerID]:GetUnits();
	local pUnit;
	for ii, pUnit in pUnits:Members() do
		if(pUnit:GetX() < 0 or  pUnit:GetY() < 0) then
			UnitManager.Kill(pUnit, false)
		end
	end	
end

local CityDataList = {}
function GetCityDatas ( pCity )
	local kCityDatas :table = {
		iTurn = Game.GetCurrentGameTurn(),
		iPosX = pCity:GetX(),
		iPosY = pCity:GetY(),
		iPop = pCity:GetPopulation()
	};	
	table.insert(CityDataList, kCityDatas)
end

function SetCityPopulation( pCity, iPopulation )
	if ( pCity ) then
		while pCity:GetPopulation() < iPopulation do
			pCity:ChangePopulation(1); --increase pop by +1
		end
	end
end

function SetCityDatas(iPlayer)	 	
	local pCities = Players[iPlayer]:GetCities()
	local pCity
	for ii, pCity in pCities:Members() do			
		for i, kCityDatas in pairs(CityDataList) do						
			if ( pCity:GetX() == kCityDatas.iPosX and pCity:GetY() == kCityDatas.iPosY ) then
				SetCityPopulation( pCity, kCityDatas.iPop )
			end	
			--table.remove(CityDataList, i) --dont remove items during loop!
		end
	end	
end

local CityUIDataList = {} 
function SetPlayerCityUIDatas( iPlayer )	
	for _,kCityUIDatas in pairs(CityUIDataList) do
		local pCities = Players[iPlayer]:GetCities();
		for _, pCity in pCities:Members() do
			if( pCity:GetX() == kCityUIDatas.iPosX and pCity:GetY() == kCityUIDatas.iPosY ) then 
				--Set City Name:
				if (bInheritCityName == true) then pCity:SetName(kCityUIDatas.sCityName); end		
				--Set City Tiles:
				if (bInheritCityPlots == true) then
					for _,kCoordinates in pairs(kCityUIDatas.CityPlotCoordinates) do
						Map.GetPlot(kCoordinates.iX,kCoordinates.iY):SetOwner(iPlayer, pCity:GetID(), true)
					end
				end
				--Set City Districts:								
				local pCityBuildQueue = pCity:GetBuildQueue();
				for _,kDistrictDatas in pairs(kCityUIDatas.CityDistricts) do 
					local plot = Map.GetPlot(kDistrictDatas.iPosX, kDistrictDatas.iPosY)
					local iDistrictType = kDistrictDatas.iType
					local iConstructionLevel = 100 --complete district					
					pCityBuildQueue:CreateIncompleteDistrict(iDistrictType, plot:GetIndex(), iConstructionLevel)
					--unfortunately we do not have any Lua function that can set a district to pillaged
				end		
				--Set City Buildings:
				for _,kBuildingData in pairs(kCityUIDatas.CityBuildings) do
					local iConstructionLevel = 100 --complete building
					local iBuildingID = kBuildingData.iBuildingID
					local bIsPillaged = kBuildingData.bIsPillaged
					pCityBuildQueue:CreateIncompleteBuilding(iBuildingID, iConstructionLevel)
					pCity:GetBuildings():SetPillaged(iBuildingID, bIsPillaged)
				end
				--Set Religious Pressures:
				for _,kReligionData in pairs(kCityUIDatas.CityReligions) do
					local iPressure = kReligionData.iPressure
					local iReligionType = kReligionData.iReligionType
					-- print("Setting " .. iPressure .. " pressure for Religion " .. iReligionType)
					local iSomeNumber = 0 --I dont know which value to use and probably it does not matter
					pCity:GetReligion():AddReligiousPressure(iSomeNumber, iReligionType , iPressure)
				end
			else
				print("Warning: City not found")
			end			
		end		
	end
end

function ConvertCapital(iPlayer, startingPlot, pCityOwnerID, pCity)
	local pPlayer = Players[pCityOwnerID]
	local pPlayerID = pPlayer:GetID()
	if pCity then
		local pCityID = pCity:GetID()
		local iX, iY = pCity:GetX(), pCity:GetY()
		local plotUnits = Units.GetUnitsInPlot(startingPlot)
		if plotUnits ~= nil then
			local toKill = {}
			for i, unit in ipairs(plotUnits) do
				table.insert(toKill, unit)
			end
			for i, unit in ipairs(toKill) do
				plotUnits:Destroy(unit)
			end					
		end		
		GetCityDatas(pCity)
		CityUIDataList = ExposedMembers.GetPlayerCityUIDatas(pPlayerID, pCityID)		
		Cities.DestroyCity(pCity) --destroy city before spawning city state units to prevent overlaps			
		Players[iPlayer]:GetCities():Create(iX, iY)
		SetCityDatas(iPlayer)
		SetPlayerCityUIDatas(iPlayer)
	end
end

-- ===========================================================================
-- ===========================================================================

function FindClosestCity(playerID, iStartX, iStartY)
    local pCity = nullptr
    local iShortestDistance = ((4 * (currentEra + 1)) / 2)
	local pPlayer = Players[playerID]
	local pFreeCities = Players[62]
	local revoltingCities = {}
	if pPlayer:GetCities() and (pPlayer:GetCities():GetCount() > 1) and (pPlayer ~= pFreeCities) then
		local pPlayerCities:table = pPlayer:GetCities()
		for i, pLoopCity in pPlayerCities:Members() do
			local iDistance = Map.GetPlotDistance(iStartX, iStartY, pLoopCity:GetX(), pLoopCity:GetY())
			if (iDistance < iShortestDistance) then
				pCity = pLoopCity
				iShortestDistance = iDistance
				table.insert(revoltingCities, pCity)
			end
		end
	end
	if (pCity == nullptr) then
		-- print ("No closest city found of player " .. tostring(playerID) .. " from " .. tostring(iStartX) .. ", " .. tostring(iStartX) .. ", distance of: " .. tostring(iShortestDistance))
	end	
    return pCity
end

function FindClosestCityDistance(iStartX, iStartY)
	local pCity = nullptr;
	local iShortestDistance = 10000;
	-- print("Finding closest city distance...")
	local aPlayers = PlayerManager.GetAlive();
	for loop, pPlayer in ipairs(aPlayers) do
		local pPlayerCities:table = pPlayer:GetCities();
		for i, pLoopCity in pPlayerCities:Members() do
			local iDistance = Map.GetPlotDistance(iStartX, iStartY, pLoopCity:GetX(), pLoopCity:GetY());
			if iDistance and (iDistance < iShortestDistance) then
				pCity = pLoopCity;
				iShortestDistance = iDistance;
			end
		end
	end
	if (pCity == nullptr) then
		print ("No target city found");
	end

    return iShortestDistance;
end

function FindClosestTargetCity(iAttackingPlayer, iStartX, iStartY)

	local pCity = nullptr;
	local iShortestDistance = 10000;

	local aPlayers = PlayerManager.GetAlive();
	for loop, pPlayer in ipairs(aPlayers) do
		local iPlayer = pPlayer:GetID();
		if (iPlayer ~= iAttackingPlayer and pPlayer:GetDiplomacy():IsAtWarWith(iAttackingPlayer)) then
			local pPlayerCities:table = pPlayer:GetCities();
			for i, pLoopCity in pPlayerCities:Members() do
				local iDistance = Map.GetPlotDistance(iStartX, iStartY, pLoopCity:GetX(), pLoopCity:GetY());
				if (iDistance < iShortestDistance) then
					pCity = pLoopCity;
					iShortestDistance = iDistance;
				end
			end
		end
	end
	if (pCity == nullptr) then
		print ("No target city found for player " .. tostring(iAttackingPlayer) .. " from " .. tostring(iStartX) .. ", " .. tostring(iStartY));
	end

    return pCity;
end

function UnitSpawns(iPlayer, startingPlot, isolatedSpawn, CivilizationTypeName)
	if isolatedSpawn and CivilizationTypeName == "CIVILIZATION_AZTEC" then
		UnitManager.InitUnit(iPlayer, "UNIT_AZTEC_EAGLE_WARRIOR", startingPlot:GetX(), startingPlot:GetY())
		print("Spawning units for " ..tostring(CivilizationTypeName) .. " at " ..tostring(startingPlot:GetX()) ..", " ..tostring(startingPlot:GetY()))
	end
	if isolatedSpawn and CivilizationTypeName == "CIVILIZATION_CREE" then
		UnitManager.InitUnit(iPlayer, "UNIT_CREE_OKIHTCITAW", startingPlot:GetX(), startingPlot:GetY())
		print("Spawning units for " ..tostring(CivilizationTypeName) .. " at " ..tostring(startingPlot:GetX()) ..", " ..tostring(startingPlot:GetY()))
	end
	if isolatedSpawn and CivilizationTypeName == "CIVILIZATION_MAORI" then
		UnitManager.InitUnit(iPlayer, "UNIT_MAORI_TOA", startingPlot:GetX(), startingPlot:GetY())
		print("Spawning units for " ..tostring(CivilizationTypeName) .. " at " ..tostring(startingPlot:GetX()) ..", " ..tostring(startingPlot:GetY()))
	end
	if isolatedSpawn and CivilizationTypeName == "CIVILIZATION_MAYA" then
		UnitManager.InitUnit(iPlayer, "UNIT_MAYAN_HULCHE", startingPlot:GetX(), startingPlot:GetY())
		print("Spawning units for " ..tostring(CivilizationTypeName) .. " at " ..tostring(startingPlot:GetX()) ..", " ..tostring(startingPlot:GetY()))
	end
	if isolatedSpawn and CivilizationTypeName == "CIVILIZATION_INCA" then
		UnitManager.InitUnit(iPlayer, "UNIT_INCA_WARAKAQ", startingPlot:GetX(), startingPlot:GetY())
		print("Spawning units for " ..tostring(CivilizationTypeName) .. " at " ..tostring(startingPlot:GetX()) ..", " ..tostring(startingPlot:GetY()))
	end
	return true
end

function EraSiegeUnits(iPlayer, pCity, currentEra)
	local pPlayer = Players[iPlayer]
	local playerResources = pPlayer:GetResources()	
	if currentEra == 0 then
		--Ancient Era
		UnitManager.InitUnitValidAdjacentHex(iPlayer, "UNIT_ARCHER", pCity:GetX(), pCity:GetY())
		UnitManager.InitUnitValidAdjacentHex(iPlayer, "UNIT_SPEARMAN", pCity:GetX(), pCity:GetY())
		UnitManager.InitUnitValidAdjacentHex(iPlayer, "UNIT_SPEARMAN", pCity:GetX(), pCity:GetY())
		UnitManager.InitUnitValidAdjacentHex(iPlayer, "UNIT_SWORDSMAN", pCity:GetX(), pCity:GetY())
		return true 
	end
	if currentEra == 1 then
		--Classical Era
		playerResources:ChangeResourceAmount(GameInfo.Resources['RESOURCE_IRON'].Index, 20)
		playerResources:ChangeResourceAmount(GameInfo.Resources['RESOURCE_HORSES'].Index, 20)
		UnitManager.InitUnitValidAdjacentHex(iPlayer, "UNIT_BATTERING_RAM", pCity:GetX(), pCity:GetY())
		UnitManager.InitUnitValidAdjacentHex(iPlayer, "UNIT_CATAPULT", pCity:GetX(), pCity:GetY())
		UnitManager.InitUnitValidAdjacentHex(iPlayer, "UNIT_SWORDSMAN", pCity:GetX(), pCity:GetY())
		UnitManager.InitUnitValidAdjacentHex(iPlayer, "UNIT_SWORDSMAN", pCity:GetX(), pCity:GetY())
		UnitManager.InitUnitValidAdjacentHex(iPlayer, "UNIT_HORSEMAN", pCity:GetX(), pCity:GetY())
		UnitManager.InitUnitValidAdjacentHex(iPlayer, "UNIT_HORSEMAN", pCity:GetX(), pCity:GetY())
		return true 
	end		
	if currentEra == 2 then
		--Medieval Era
		playerResources:ChangeResourceAmount(GameInfo.Resources['RESOURCE_IRON'].Index, 20)
		playerResources:ChangeResourceAmount(GameInfo.Resources['RESOURCE_HORSES'].Index, 20)
		UnitManager.InitUnitValidAdjacentHex(iPlayer, "UNIT_BOMBARD", pCity:GetX(), pCity:GetY())
		UnitManager.InitUnitValidAdjacentHex(iPlayer, "UNIT_CATAPULT", pCity:GetX(), pCity:GetY())
		UnitManager.InitUnitValidAdjacentHex(iPlayer, "UNIT_SWORDSMAN", pCity:GetX(), pCity:GetY())
		UnitManager.InitUnitValidAdjacentHex(iPlayer, "UNIT_PIKEMAN", pCity:GetX(), pCity:GetY())
		UnitManager.InitUnitValidAdjacentHex(iPlayer, "UNIT_KNIGHT", pCity:GetX(), pCity:GetY())
		UnitManager.InitUnitValidAdjacentHex(iPlayer, "UNIT_KNIGHT", pCity:GetX(), pCity:GetY())
		UnitManager.InitUnitValidAdjacentHex(iPlayer, "UNIT_CROSSBOWMAN", pCity:GetX(), pCity:GetY())	
		return true 
	end		
	if currentEra == 3 then
		--Renaissance
		playerResources:ChangeResourceAmount(GameInfo.Resources['RESOURCE_NITER'].Index, 20)
		playerResources:ChangeResourceAmount(GameInfo.Resources['RESOURCE_HORSES'].Index, 20)
		UnitManager.InitUnitValidAdjacentHex(iPlayer, "UNIT_BOMBARD", pCity:GetX(), pCity:GetY())
		UnitManager.InitUnitValidAdjacentHex(iPlayer, "UNIT_MUSKETMAN", pCity:GetX(), pCity:GetY())
		UnitManager.InitUnitValidAdjacentHex(iPlayer, "UNIT_KNIGHT", pCity:GetX(), pCity:GetY())
		UnitManager.InitUnitValidAdjacentHex(iPlayer, "UNIT_KNIGHT", pCity:GetX(), pCity:GetY())
		UnitManager.InitUnitValidAdjacentHex(iPlayer, "UNIT_MUSKETMAN", pCity:GetX(), pCity:GetY())
		UnitManager.InitUnitValidAdjacentHex(iPlayer, "UNIT_CROSSBOWMAN", pCity:GetX(), pCity:GetY())
		UnitManager.InitUnitValidAdjacentHex(iPlayer, "UNIT_CROSSBOWMAN", pCity:GetX(), pCity:GetY())
		return true 
	end
	if currentEra == 4 then
		--Industrial
		playerResources:ChangeResourceAmount(GameInfo.Resources['RESOURCE_NITER'].Index, 20)
		playerResources:ChangeResourceAmount(GameInfo.Resources['RESOURCE_HORSES'].Index, 20)
		UnitManager.InitUnitValidAdjacentHex(iPlayer, "UNIT_FIELD_CANNON", pCity:GetX(), pCity:GetY())
		UnitManager.InitUnitValidAdjacentHex(iPlayer, "UNIT_FIELD_CANNON", pCity:GetX(), pCity:GetY())
		UnitManager.InitUnitValidAdjacentHex(iPlayer, "UNIT_MUSKETMAN", pCity:GetX(), pCity:GetY())
		UnitManager.InitUnitValidAdjacentHex(iPlayer, "UNIT_MUSKETMAN", pCity:GetX(), pCity:GetY())
		UnitManager.InitUnitValidAdjacentHex(iPlayer, "UNIT_MUSKETMAN", pCity:GetX(), pCity:GetY())
		UnitManager.InitUnitValidAdjacentHex(iPlayer, "UNIT_CAVALRY", pCity:GetX(), pCity:GetY())
		UnitManager.InitUnitValidAdjacentHex(iPlayer, "UNIT_CAVALRY", pCity:GetX(), pCity:GetY())
		return true 
	end
	if currentEra == 5 then
		--Modern
		playerResources:ChangeResourceAmount(GameInfo.Resources['RESOURCE_HORSES'].Index, 20)
		playerResources:ChangeResourceAmount(GameInfo.Resources['RESOURCE_OIL'].Index, 20)
		UnitManager.InitUnitValidAdjacentHex(iPlayer, "UNIT_ARTILLERY", pCity:GetX(), pCity:GetY())
		UnitManager.InitUnitValidAdjacentHex(iPlayer, "UNIT_ARTILLERY", pCity:GetX(), pCity:GetY())
		UnitManager.InitUnitValidAdjacentHex(iPlayer, "UNIT_INFANTRY", pCity:GetX(), pCity:GetY())
		UnitManager.InitUnitValidAdjacentHex(iPlayer, "UNIT_INFANTRY", pCity:GetX(), pCity:GetY())
		UnitManager.InitUnitValidAdjacentHex(iPlayer, "UNIT_INFANTRY", pCity:GetX(), pCity:GetY())	
		UnitManager.InitUnitValidAdjacentHex(iPlayer, "UNIT_CAVALRY", pCity:GetX(), pCity:GetY())
		UnitManager.InitUnitValidAdjacentHex(iPlayer, "UNIT_CAVALRY", pCity:GetX(), pCity:GetY())
		return true 
	end
	if currentEra == 6 then
		--Atomic
		playerResources:ChangeResourceAmount(GameInfo.Resources['RESOURCE_OIL'].Index, 20)
		playerResources:ChangeResourceAmount(GameInfo.Resources['RESOURCE_URANIUM'].Index, 10)
		UnitManager.InitUnitValidAdjacentHex(iPlayer, "UNIT_ARTILLERY", pCity:GetX(), pCity:GetY())
		UnitManager.InitUnitValidAdjacentHex(iPlayer, "UNIT_ARTILLERY", pCity:GetX(), pCity:GetY())
		UnitManager.InitUnitValidAdjacentHex(iPlayer, "UNIT_INFANTRY", pCity:GetX(), pCity:GetY())
		UnitManager.InitUnitValidAdjacentHex(iPlayer, "UNIT_INFANTRY", pCity:GetX(), pCity:GetY())
		UnitManager.InitUnitValidAdjacentHex(iPlayer, "UNIT_INFANTRY", pCity:GetX(), pCity:GetY())
		UnitManager.InitUnitValidAdjacentHex(iPlayer, "UNIT_MACHINE_GUN", pCity:GetX(), pCity:GetY())
		UnitManager.InitUnitValidAdjacentHex(iPlayer, "UNIT_TANK", pCity:GetX(), pCity:GetY())	
		return true 
	end		
	if currentEra == 7 then
		--Digital
		playerResources:ChangeResourceAmount(GameInfo.Resources['RESOURCE_OIL'].Index, 30)
		playerResources:ChangeResourceAmount(GameInfo.Resources['RESOURCE_ALUMINUM'].Index, 10)
		playerResources:ChangeResourceAmount(GameInfo.Resources['RESOURCE_URANIUM'].Index, 10)
		UnitManager.InitUnitValidAdjacentHex(iPlayer, "UNIT_ARTILLERY", pCity:GetX(), pCity:GetY())
		UnitManager.InitUnitValidAdjacentHex(iPlayer, "UNIT_ARTILLERY", pCity:GetX(), pCity:GetY())
		UnitManager.InitUnitValidAdjacentHex(iPlayer, "UNIT_INFANTRY", pCity:GetX(), pCity:GetY())
		UnitManager.InitUnitValidAdjacentHex(iPlayer, "UNIT_INFANTRY", pCity:GetX(), pCity:GetY())
		UnitManager.InitUnitValidAdjacentHex(iPlayer, "UNIT_MECHANIZED_INFANTRY", pCity:GetX(), pCity:GetY())
		UnitManager.InitUnitValidAdjacentHex(iPlayer, "UNIT_MACHINE_GUN", pCity:GetX(), pCity:GetY())
		UnitManager.InitUnitValidAdjacentHex(iPlayer, "UNIT_ANTIAIR_GUN", pCity:GetX(), pCity:GetY())	
		UnitManager.InitUnitValidAdjacentHex(iPlayer, "UNIT_TANK", pCity:GetX(), pCity:GetY())			
		return true 
	end
	if currentEra == 8 then
		--Information
		playerResources:ChangeResourceAmount(GameInfo.Resources['RESOURCE_OIL'].Index, 40)
		playerResources:ChangeResourceAmount(GameInfo.Resources['RESOURCE_ALUMINUM'].Index, 10)
		playerResources:ChangeResourceAmount(GameInfo.Resources['RESOURCE_URANIUM'].Index, 10)
		UnitManager.InitUnitValidAdjacentHex(iPlayer, "UNIT_ARTILLERY", pCity:GetX(), pCity:GetY())
		UnitManager.InitUnitValidAdjacentHex(iPlayer, "UNIT_ARTILLERY", pCity:GetX(), pCity:GetY())
		UnitManager.InitUnitValidAdjacentHex(iPlayer, "UNIT_MECHANIZED_INFANTRY", pCity:GetX(), pCity:GetY())
		UnitManager.InitUnitValidAdjacentHex(iPlayer, "UNIT_MECHANIZED_INFANTRY", pCity:GetX(), pCity:GetY())
		UnitManager.InitUnitValidAdjacentHex(iPlayer, "UNIT_MACHINE_GUN", pCity:GetX(), pCity:GetY())
		UnitManager.InitUnitValidAdjacentHex(iPlayer, "UNIT_MOBILE_SAM", pCity:GetX(), pCity:GetY())
		UnitManager.InitUnitValidAdjacentHex(iPlayer, "UNIT_MODERN_ARMOR", pCity:GetX(), pCity:GetY())
		return true 
	end
	return false
end

local function InitiateInvasions( player )
	local pAttacker = Players[player]
	local g_iInvaderX = pAttacker:GetStartingPlot():GetX()
	local g_iInvaderY = pAttacker:GetStartingPlot():GetY()
	local pNearestCity = FindClosestTargetCity(player, g_iInvaderX, g_iInvaderY);
	if (pNearestCity ~= nullptr) then
		local pMilitaryAI = pAttacker:GetAi_Military()
		if (pMilitaryAI ~= nullptr) then
			local iOperationID = pMilitaryAI:StartScriptedOperationWithTargetAndRally("Attack Enemy City", pNearestCity:GetOwner(), Map.GetPlot(pNearestCity:GetX(), pNearestCity:GetY()):GetIndex(), Map.GetPlot(g_iInvaderX, g_iInvaderY):GetIndex())
			local pUnits :table = pAttacker:GetUnits()	
			for i, pUnit in pUnits:Members() do
				pMilitaryAI:AddUnitToScriptedOperation(iOperationID, pUnit:GetID())
			end
			print("Target city found, starting invasion")
		end
	end
end

function PlayerBuffer(startingPlot)	
	local newStartingPlots = {}
	local selectedPlot = startingPlot
	local range = 3
	local plotX = startingPlot:GetX()
	local plotY = startingPlot:GetY()
	local tableEmpty = true
	while (tableEmpty)
	do
		for dx = -range, range do
			for dy = -range, range do
				-- print("Searching for new starting plots...")
				local otherPlot = Map.GetPlotXY(plotX, plotY, dx, dy, range)
				if otherPlot then
					local impassable = otherPlot:IsImpassable()
					local isWater = otherPlot:IsWater()
					local isOwned = otherPlot:IsOwned()
					local isUnit  = otherPlot:IsUnit()
					if not impassable and not isWater and not isOwned and not isUnit then
						local iDistance = FindClosestCityDistance(otherPlot:GetX(), otherPlot:GetY())
						-- print("Plot: "..tostring(otherPlot:GetX())..", "..tostring(otherPlot:GetY()))
						-- print("iDistance: "..tostring(iDistance))
						if iDistance > 3 then
							table.insert(newStartingPlots, otherPlot)
							tableEmpty = false
							print("New starting plot found")
							print("Plot: "..tostring(otherPlot:GetX())..", "..tostring(otherPlot:GetY()))
							print("iDistance: "..tostring(iDistance))								
						end
					end
				end
			end
		end
		if tableEmpty then 
			range = range + 1 
		end
		if range == 10 then
			tableEmpty = false
		end
	end
	for j, plot in ipairs(newStartingPlots) do
		if plot and plot:IsFreshWater() then
			selectedPlot = plot
			break		
		end
		if plot then
			selectedPlot = plot
			break		
		end
	end
	return selectedPlot
end

function GetStartingCivics (iPlayer, isolatedSpawn)
	local player = Players[iPlayer]
	local pCulture = player:GetCulture()
	if player and isolatedSpawn then
		-- player:GetCulture():SetCivic(GameInfo.Civics["CIVIC_CODE_OF_LAWS"].Index, true)
		local CultureCost  = pCulture:GetCultureCost(GameInfo.Civics["CIVIC_CODE_OF_LAWS"].Index)
		pCulture:SetCulturalProgress(GameInfo.Civics["CIVIC_CODE_OF_LAWS"].Index, CultureCost)
		return true
	elseif(player) then
		-- player:GetCulture():SetCivic(GameInfo.Civics["CIVIC_CODE_OF_LAWS"].Index, true)
		local CultureCost  = pCulture:GetCultureCost(GameInfo.Civics["CIVIC_CODE_OF_LAWS"].Index)
		pCulture:SetCulturalProgress(GameInfo.Civics["CIVIC_CODE_OF_LAWS"].Index, CultureCost)		
		return true
	end
	return false
end

-- ===========================================================================
-- ===========================================================================

function SpawnPlayer(iPlayer)
	local player = Players[iPlayer]
	if player then
		if not player:IsBarbarian() then-- and not player:IsAlive() then
			local CivilizationTypeName = PlayerConfigurations[iPlayer]:GetCivilizationTypeName()
			local spawnYear = spawnDates[CivilizationTypeName]
			local isolatedSpawn = false
			if isolatedCivs[CivilizationTypeName] then isolatedSpawn = true end
			local eraBuildingCiv = false
			if eraBuildingCivs[CivilizationTypeName] then eraBuildingCiv = true end
			--print("Check Spawning Date for ", tostring(CivilizationTypeName), "Start Year = ", tostring(spawnYear), "Previous Turn Year = ", tostring(previousTurnYear), "Current Turn Year = ", tostring(currentTurnYear))
			local iTurn = Game.GetCurrentGameTurn()
			local startTurn = GameConfiguration.GetStartTurn()
			-- Give era score before spawn
			local era = player:GetEras():GetEra()
			local playerID = player:GetID()
			if player:IsMajor() then
				if era < currentEra and spawnYear > currentTurnYear then
					Game:GetEras():ChangePlayerEraScore(playerID, 1)
				end
				if spawnYear > currentTurnYear and (iTurn == 1) then
					GetStartingCivics(iPlayer, isolatedSpawn)
				end
			end

			if spawnYear and spawnYear >= previousTurnYear and spawnYear < currentTurnYear then
				local startingPlot = player:GetStartingPlot()
				local oceanStart = false
				if startingPlot:IsWater() then oceanStart = true end
				
				--City conversion code from Tiramasu (unused)
				-- if player:IsMajor() and startingPlot:IsCity() then
					-- local pCity = Cities.GetCityInPlot(startingPlot)
					-- local pCityOwnerID = pCity:GetOwner()
					-- local pDiplomacy = player:GetDiplomacy()
					-- local iWar = WarTypes.FORMAL_WAR
					-- pDiplomacy:SetHasMet(pCityOwnerID)					
					-- ConvertCapital(iPlayer, startingPlot, pCityOwnerID, pCity)
					-- local bCanWar = pDiplomacy:CanDeclareWarOn(pCityOwnerID)
					-- if bCanWar then 
						-- pDiplomacy:DeclareWarOn(pCityOwnerID, iWar, true) 
					-- end	
				-- end	
				
				-- totalslacker: kill units in starting plot or they might prevent spawn
				-- local plotUnits = Units.GetUnitsInPlot(startingPlot)
				-- if plotUnits ~= nil then
					-- local toKill = {}
					-- for i, unit in ipairs(plotUnits) do
						-- table.insert(toKill, unit)
					-- end
					-- for i, unit in ipairs(toKill) do
						-- plotUnits:Destroy(unit)
					-- end					
				-- end
				
				-- totalslacker: the first method to kill units was preventing Sumeria from spawning. This isn't the best way but it works for now
				-- totalslacker: moves the players starting units instead of deleting them
				local plotUnits = Units.GetUnitsInPlot(startingPlot)
				for loop, pUnit in ipairs(plotUnits) do
					local pUnitOwnerID = pUnit:GetOwner()
					local pUnitOwner = Players[pUnitOwnerID]
					if pUnitOwner:IsBarbarian() then
						UnitManager.Kill(pUnit)
						print("Killing barbarian unit to spawn player #"..tostring(iPlayer))
					elseif(not pUnitOwner:IsMajor()) then
						UnitManager.Kill(pUnit)
						print("Killing city-state unit or first-turn settler to spawn player #"..tostring(iPlayer))
					else
						if (iTurn ~= 1) then
							local pUnitType = GameInfo.Units[pUnit:GetType()].UnitType
							UnitManager.Kill(pUnit)
							-- UnitManager.InitUnitValidAdjacentHex(iPlayer, pUnitType, startingPlot:GetX(), startingPlot:GetY())
							-- print("Moving unit to spawn player #"..tostring(iPlayer))						
						end
					end
				end			
				
				print ("----------")
				print(" - Spawning", tostring(CivilizationTypeName), "Start Year = ", tostring(spawnYear), "Previous Turn Year = ", tostring(previousTurnYear), "Current Turn Year = ", tostring(currentTurnYear), "at", startingPlot:GetX(), startingPlot:GetY())
				LuaEvents.SpawnPlayer(iPlayer)
				
				if bApplyBalance and player:IsMajor() and not isolatedSpawn then
					if startingPlot:IsOwned() then
						print("Starting plot is owned. Searching for new starting plot.")
						newStartingPlot = PlayerBuffer(startingPlot)
						print("New starting plot found: "..tostring(newStartingPlot:GetX())..", "..tostring(newStartingPlot:GetY()))
						EraSiegeUnits(iPlayer, newStartingPlot, currentEra)
						GetStartingBonuses(player, newStartingPlot)	
					else
						if (iTurn ~= 1) then
							EraSiegeUnits(iPlayer, startingPlot, currentEra)
						end
						GetStartingBonuses(player, startingPlot)	
					end
					--totalslacker: Gives player Era bonuses and starting units 
					-- GetStartingBonuses(player)	
					--totalslacker: Find closest city of player in spawn zone based on era
					for pPlayer = 0, PlayerManager.GetWasEverAliveCount() - 1 do
						local pCity = FindClosestCity(pPlayer, startingPlot:GetX(), startingPlot:GetY())
						if pCity ~= nullptr then
							print("Calling CheckCity")
							local pCityID = pCity:GetID()
							print("pCityID = "..tostring(pCityID))
							local pFreeCityID = ExposedMembers.CheckCity.CheckCityGovernor(pPlayer, pCityID)
							if pCityID == pFreeCityID then
								CityManager.TransferCityToFreeCities(pCity)
								print("----------")
								print("Converting city to free cities ")
								print("----------")
							else
								print("City could not be converted to free cities. Declaring war on city owner")
								local pDiplomacy = player:GetDiplomacy()
								local iWar = WarTypes.FORMAL_WAR
								pDiplomacy:SetHasMet(pPlayer)
								local bCanWar = pDiplomacy:CanDeclareWarOn(pPlayer)
								if bCanWar then 
									pDiplomacy:DeclareWarOn(pPlayer, iWar, true) 
									print("War declared successfully")
								end	
							end
						end								
					end
					if not player:IsHuman() then
						InitiateInvasions(iPlayer)
						print("Start scripted attack on nearest city if possible")
					end					
				end				
				
				--totalslacker: check for Maori spawn which has its own conditions
				-- Spawn the player's first city
				if not oceanStart then
					if startingPlot:IsOwned() then
						print("Starting plot is owned. Moving starting settler.")
						-- UnitManager.InitUnitValidAdjacentHex(iPlayer, "UNIT_SETTLER", startingPlot:GetX(), startingPlot:GetY())
						-- print("Starting plot is owned. Searching for new starting plot.")
						-- newStartingPlot = PlayerBuffer(startingPlot)		
						UnitManager.InitUnitValidAdjacentHex(iPlayer, "UNIT_SETTLER", newStartingPlot:GetX(), newStartingPlot:GetY())
					elseif(iTurn ~= 1) then
						local iShortestDistance = FindClosestCityDistance(startingPlot:GetX(), startingPlot:GetY())
						if iShortestDistance > 3 then	
							if not eraBuildingCiv then
								-- ImprovementBuilder.SetImprovementType(startingPlot, -1)
								local city = player:GetCities():Create(startingPlot:GetX(), startingPlot:GetY())
								if not city then
									print("Failed to spawn starting city. Spawning settler instead.")
									UnitManager.InitUnit(iPlayer, "UNIT_SETTLER", startingPlot:GetX(), startingPlot:GetY())
								end									
							else
								UnitManager.InitUnit(iPlayer, "UNIT_SETTLER", startingPlot:GetX(), startingPlot:GetY())
							end
						else
							print("City within 3 plots of starting plot. Moving starting settler.")
							UnitManager.InitUnitValidAdjacentHex(iPlayer, "UNIT_SETTLER", startingPlot:GetX(), startingPlot:GetY())
						end		
					else
						if not player:IsHuman() then
							local city = player:GetCities():Create(startingPlot:GetX(), startingPlot:GetY())
							if not city then
								print("Failed to spawn starting city.")
							else
								local playerUnits = player:GetUnits()
								local toKill = {}
								for i, unit in playerUnits:Members() do
									local pUnitType = GameInfo.Units[unit:GetType()].UnitType
									if pUnitType == "UNIT_SETTLER" then									
										table.insert(toKill, unit)
										print("Found first turn settler")
									end
								end
								for i, unit in ipairs(toKill) do
									playerUnits:Destroy(unit)
									print("Killing first turn settler")
								end
							end
						end
					end
				else
					--totalslacker: attempting to spawn a city broke the Maori ocean start bonus, always spawn settler instead
					UnitManager.InitUnit(iPlayer, "UNIT_SETTLER", startingPlot:GetX(), startingPlot:GetY())
				end
				
				--totalslacker: Spawn any extra units specific to this Civ or start (further logic to be implemented in the UnitSpawns function)
				UnitSpawns(iPlayer, startingPlot, isolatedSpawn, CivilizationTypeName)
				
				--Delete hidden settler now that we have a city or units on the map, or the AI will never build more settlers
				DeleteUnitsOffMap(iPlayer)
				
				if player:IsHuman() then
					LuaEvents.RestoreAutoValues()
				end
				return true
			end	
		end
	else
		print("WARNING: player is nil in SpawnPlayer #"..tostring(iPlayer))
	end
end
GameEvents.PlayerTurnStarted.Add( SpawnPlayer )

function GetStartingBonuses(player, startingPlot)


	print(" - Starting era = "..tostring(currentEra))
	SetStartingEra(player:GetID(), currentEra)
	player:GetEras():SetStartingEra(currentEra)
	local playerID = player:GetID()
	local kEraBonuses = GameInfo.StartEras[currentEra]
	local CivilizationTypeName = PlayerConfigurations[playerID]:GetCivilizationTypeName()
	
	-- gold
	local pTreasury = player:GetTreasury()
	local playerGoldBonus = goldBonus
	if currentEra > 0 and kEraBonuses.Gold then
		playerGoldBonus = playerGoldBonus + kEraBonuses.Gold
	end
	print(" - Gold bonus = "..tostring(playerGoldBonus))
	pTreasury:ChangeGoldBalance(playerGoldBonus)	
	
	-- science
	local pScience = player:GetTechs()	
	for iTech, number in pairs(knownTechs) do
		if number >= minCivForTech then
			-- pScience:SetTech(iTech, true)
			local ScienceCost  = pScience:GetResearchCost(iTech)
			pScience:SetResearchProgress(iTech, ScienceCost)			
		else
			pScience:TriggerBoost(iTech)
			pScience:SetResearchingTech(iTech)
		end
	end	
	print(" - Science bonus = "..tostring(scienceBonus))
	pScience:ChangeCurrentResearchProgress(scienceBonus)
	
	-- culture
	local pCulture = player:GetCulture()
	for kCivic in GameInfo.Civics() do
		local iCivic	= kCivic.Index
		local value		= kCivic.value
		if knownCivics[iCivic] then
			if knownCivics[iCivic] >= minCivForCivic then
				-- pCulture:SetCivic(iCivic, true)
				local CultureCost  = pCulture:GetCultureCost(iCivic)
				pCulture:SetCulturalProgress(iCivic, CultureCost)
				pCulture:SetCivicCompletedThisTurn(true)
			else
				pCulture:TriggerBoost(iCivic)
			end
		elseif researchedCivics[iCivic] then
			pCulture:TriggerBoost(iCivic)
			-- local CultureCost  = pCulture:GetCultureCost(iCivic)
			-- pCulture:SetCulturalProgress(iCivic, CultureCost)
		end
	end	
	
	-- get starting governments
	if eraBuildingCivs[CivilizationTypeName] then
		--Unlock Democracy
		pCulture:UnlockGovernment(GameInfo.Governments["GOVERNMENT_DEMOCRACY"].Index)
	end
	
	
	-- faith
	local playerFaithBonus = faithBonus
	if currentEra > 0 and kEraBonuses.Faith then
		playerFaithBonus = playerFaithBonus + kEraBonuses.Faith
	end
	print(" - Faith bonus = "..tostring(playerFaithBonus))
	player:GetReligion():ChangeFaithBalance(playerFaithBonus)
	
	-- token
	print(" - Token bonus = "..tostring(tokenBonus))
	player:GetInfluence():ChangeTokensToGive(tokenBonus)
	
	
	-- units
	local startingPlot = startingPlot
	-- totalslacker: only add settlers after Classical Era	(ancient era = 0, classical = 1, etc) ie: currentEra > 0 adds settlers after the ancient era)
	print(" - Settlers = "..tostring(settlersBonus))
	if settlersBonus > 0 and currentEra > 1 then
		UnitManager.InitUnitValidAdjacentHex(player:GetID(), "UNIT_SETTLER", startingPlot:GetX(), startingPlot:GetY(), settlersBonus)
	end
	
	for kUnits in GameInfo.MajorStartingUnits() do
		if GameInfo.Eras[kUnits.Era].Index == currentEra and not (kUnits.AiOnly) then -- (player:IsHuman() and kUnits.AiOnly) -- to do : difficulty difference check
			local numUnit = math.max(kUnits.Quantity, 1)
			print(" - "..tostring(kUnits.Unit).." = "..tostring(numUnit))
			if not kUnits.Unit == "UNIT_TRADER" then
				UnitManager.InitUnitValidAdjacentHex(player:GetID(), kUnits.Unit, startingPlot:GetX(), startingPlot:GetY(), numUnit)
			end
		end
	end	
end

function SetCurrentBonuses()

	knownTechs		= {}
	knownCivics		= {}
	playersWithCity	= 0

	local totalScience 	= 0
	local totalCulture 	= 0
	local totalGold 	= 0
	local totalCities	= 0
	local totalToken	= 0
	local totalFaith	= 0
	
	for kEra in GameInfo.StartEras() do
		if kEra.Year and kEra.Year < currentTurnYear then
			local era = GameInfo.Eras[kEra.EraType].Index				
			if era > currentEra then
				print ("Changing current Era to current year's Era :" .. tostring(kEra.EraType))
				currentEra = era
			end		
		end
	end	
	
	for iPlayer = 0, PlayerManager.GetWasEverAliveCount() - 1 do
		local player = Players[iPlayer]
		if player and player:IsMajor() and player:GetCities():GetCount() > 0 then
			local CivilizationTypeName = PlayerConfigurations[iPlayer]:GetCivilizationTypeName()
			-- print ("CivilizationTypeName is " .. tostring(CivilizationTypeName))		
			playersWithCity = playersWithCity + 1
			totalCities		= totalCities + player:GetCities():GetCount()
			
			
				
			-- Science	
			local pScience = player:GetTechs()
			totalScience = totalScience + pScience:GetResearchProgress( pScience:GetResearchingTech() )
			for kTech in GameInfo.Technologies() do		
				local iTech	= kTech.Index
				if pScience:HasTech(iTech) then
					if not knownTechs[iTech] then knownTechs[iTech] = 0 end
					knownTechs[iTech] = knownTechs[iTech] + 1
				end
			end
			
			-- Culture
			local pCulture = player:GetCulture()
			researchedCivics[pCulture:GetProgressingCivic()] = true
			for kCivic in GameInfo.Civics() do		
				local iCivic	= kCivic.Index
				if pCulture:HasCivic(iCivic) then
					if not knownCivics[iCivic] then knownCivics[iCivic] = 0 end
					knownCivics[iCivic] = knownCivics[iCivic] + 1
				end
			end
			
			-- Gold
			local pTreasury = player:GetTreasury()			
			totalGold = totalGold + pTreasury:GetGoldYield() + pTreasury:GetTotalMaintenance()			
			if pTreasury:GetGoldBalance() > 0 then
				totalGold = totalGold + pTreasury:GetGoldBalance()
			end
						
			-- Faith
			totalFaith = totalFaith + player:GetReligion():GetFaithYield()
			
			local playerUnits = player:GetUnits(); 	
			for i, unit in playerUnits:Members() do
				local unitInfo = GameInfo.Units[unit:GetType()];
				totalGold = totalGold + unitInfo.Cost
			end
			
			local era = player:GetEras():GetEra()
			if era > currentEra then
				print ("----------")
				print ("Changing current Era to "..tostring(CivilizationTypeName).." Era :" .. tostring(GameInfo.Eras[era].EraType))
				currentEra = era
			end
			
			tokenBonus = tokenBonus + player:GetInfluence():GetTokensToGive()
			for i, minorPlayer in ipairs(PlayerManager.GetAliveMinors()) do
				local iMinorPlayer 		= minorPlayer:GetID()				
				local minorInfluence	= minorPlayer:GetInfluence()		
				if minorInfluence ~= nil then
					tokenBonus = tokenBonus + minorInfluence:GetTokensReceived(iPlayer)
				end
			end
	
		end
	end
	
	if playersWithCity > 0 then
		scienceBonus 	= Round(totalScience/playersWithCity)
		minCivForTech	= playersWithCity*25/100
		minCivForCivic	= playersWithCity*10/100
		goldBonus 		= Round(totalGold/playersWithCity)
		settlersBonus 	= Round((totalCities-1)/playersWithCity)
		tokenBonus 		= Round(totalToken/playersWithCity)
		faithBonus		= Round(totalFaith * (currentEra+1) * 25/100)
	end
	
end
if bApplyBalance then
	GameEvents.OnGameTurnStarted.Add(SetCurrentBonuses)
end

function OnCityCaptured(iPlayer, cityID)
	local city = CityManager.GetCity(iPlayer, cityID)
	local player = Players[iPlayer]
	if not player:IsMajor() then return end	
	if player:GetCities():GetCount() ==  1 then
		CityManager.SetAsOriginalCapital(city)
		print("Player has captured their first city without using a settler. Converting to Original Capital.")
		return true
	end
	if player:GetCities():GetCount() > (currentEra + 1) then 
		local pCapital = player:GetCities():GetCapitalCity()
		local loyaltyBuilding = GameInfo.Buildings["BUILDING_SUPER_MONUMENT"]
		if pCapital:GetBuildings():HasBuilding(loyaltyBuilding.Index) then
			pCapital:GetBuildings():RemoveBuilding(loyaltyBuilding.Index)
			print("Deleting Super Monument from player "..tostring(iPlayer))
		end
		return true
	end		
	return false
end

-- This function would be used to give Super Monuments to players who lose their capital
-- Needs more logic to work correctly, and the idea itself may be unbalanced
function CapitalWasChanged(playerID, cityID)
	local pPlayer = Players[playerID]
	local pCities = pPlayer:GetCities()
	local pCity = pCities:FindID(cityID)
	local loyaltyBuilding = GameInfo.Buildings["BUILDING_SUPER_MONUMENT"].Index
	if pCities:GetCount() < (currentEra + 1) then
		if GameInfo.Buildings[loyaltyBuilding] and not pCity:GetBuildings():HasBuilding(loyaltyBuilding) then
			--WorldBuilder.CityManager():CreateBuilding(city, loyaltyBuilding, 100, cityPlot)
			local pCityBuildQueue = pCity:GetBuildQueue()
			pCityBuildQueue:CreateIncompleteBuilding(GameInfo.Buildings[loyaltyBuilding].Index, 100)
			print("Capital conquered. Spawning new "..tostring(loyaltyBuilding))
		end	
	end	
end

--Credit: LeeS from the Civ 6 Modding Guide, adapted with changes
function CityWasConquered(VictorID, LoserID, CityID, iCityX, iCityY)
	local pPlayer = Players[VictorID]
	local pCity = pPlayer:GetCities():FindID(CityID)
	local sCity_LOC = pCity:GetName()
	print("Player # " .. VictorID .. " : captured the city of " .. Locale.Lookup(sCity_LOC))
	print("Player # " .. LoserID .. " lost the city")
	print("The city is located at (or used to be located at) grid X" .. iCityX .. ", Y" .. iCityY )
	local checkOriginalCapital = ExposedMembers.CheckCityOriginalCapital(VictorID, CityID)
	if checkOriginalCapital then 
		occupiedCapitals[checkOriginalCapital] = true 
		print("An original capital has been conquered by player "..tostring(VictorID).." from player "..tostring(LoserID))
	end
	if not pPlayer:IsMajor() then return end	
	local pCapital = pPlayer:GetCities():GetCapitalCity()
	local loyaltyBuilding = GameInfo.Buildings["BUILDING_SUPER_MONUMENT"].Index
	if pCity:GetBuildings():HasBuilding(loyaltyBuilding) and CityID ~= pCapital:GetID()  then
		pCapital:GetBuildings():RemoveBuilding(loyaltyBuilding)
		print("Deleting Super Monument from a recently conquered city")
	end
	if pPlayer:GetCities():GetCount() > (currentEra + 1) then 
		if pCapital:GetBuildings():HasBuilding(loyaltyBuilding) then
			pCapital:GetBuildings():RemoveBuilding(loyaltyBuilding)
			print("Deleting Super Monument from player "..tostring(VictorID))
		end
	end		
end

function OnCityInitialized(iPlayer, cityID, x, y)
	local city = CityManager.GetCity(iPlayer, cityID)
	local player = Players[iPlayer]
	if not player:IsMajor() then return end
	local cityPlot = Map.GetPlot(x, y)
	local pCapital = player:GetCities():GetCapitalCity()
	local iLoyaltyBuilding = GameInfo.Buildings["BUILDING_SUPER_MONUMENT"].Index	
	local CivilizationTypeName = PlayerConfigurations[iPlayer]:GetCivilizationTypeName()
	print("------------")
	print("Initializing new city for " .. tostring(CivilizationTypeName))
	local bOriginalOwner = false
	if city:GetOriginalOwner() ~= nil then
		bOriginalOwner = true
		print("Original owner is "..tostring(city:GetOriginalOwner()))
	end
	local playerEra = GetStartingEra(iPlayer)
	local kEraBonuses = GameInfo.StartEras[playerEra]
	
	--totalslacker: check for capital for Super Monument
	local superMonument = false
	if city == player:GetCities():GetCapitalCity() then superMonument = true end
	
	--totalslacker: add era buildings
	local eraBuildingSpawn = false
	local eraBuildingForAll = false
	if eraBuildingCivs[CivilizationTypeName] then eraBuildingSpawn = true end
	if bEraBuilding then eraBuildingForAll = true end
	
	-- Era Start Building for Era bonuses
	if eraBuildingSpawn and not eraBuildingForAll then
		local EraBuilding = "BUILDING_CENTER_"..tostring(GameInfo.Eras[playerEra].EraType)
		print("Starting Era Building = "..tostring(EraBuilding))
		if GameInfo.Buildings[EraBuilding] then
			--WorldBuilder.CityManager():CreateBuilding(city, EraBuilding, 100, cityPlot)
			local pCityBuildQueue = city:GetBuildQueue();
			pCityBuildQueue:CreateIncompleteBuilding(GameInfo.Buildings[EraBuilding].Index, 100);
		end	
	elseif(eraBuildingForAll) then
		local EraBuilding = "BUILDING_CENTER_"..tostring(GameInfo.Eras[playerEra].EraType)
		print("Starting Era Building = "..tostring(EraBuilding))
		if GameInfo.Buildings[EraBuilding] then
			--WorldBuilder.CityManager():CreateBuilding(city, EraBuilding, 100, cityPlot)
			local pCityBuildQueue = city:GetBuildQueue();
			pCityBuildQueue:CreateIncompleteBuilding(GameInfo.Buildings[EraBuilding].Index, 100);
		end		
	end
	

	-- Convert first settled city to the Original Capital
	-- if player:GetCities():GetCount() >  1 then
		-- if pCapital:GetOriginalOwner() ~= nil and bOriginalOwner then 
			-- if city:GetOriginalOwner() == iPlayer and pCapital:GetOriginalOwner() ~= iPlayer and not occupiedCapitals[iPlayer] then
				-- CityManager.SetAsOriginalCapital(city)
				-- print("Player has settled their first original city, converting to Original Capital")
			-- end			
		-- end
	-- end
	
	--totalslacker: the line below will prevent every new city after the first from spawning units, buildings and population
	--TODO: conditional based on list ?
	if player:GetCities():GetCount() > (currentEra + 1) then 
		local pCapital = player:GetCities():GetCapitalCity()
		local loyaltyBuilding = GameInfo.Buildings["BUILDING_SUPER_MONUMENT"]
		if pCapital:GetBuildings():HasBuilding(loyaltyBuilding.Index) then
			pCapital:GetBuildings():RemoveBuilding(loyaltyBuilding.Index)
			print("Deleting Super Monument from player "..tostring(iPlayer))
		end
		print("Current era is "..tostring(currentEra))
		return 
	end	
	
	print("Era = "..tostring(playerEra))
	print("StartingPopulationCapital = "..tostring(kEraBonuses.StartingPopulationCapital))
	print("StartingPopulationOtherCities = "..tostring(kEraBonuses.StartingPopulationOtherCities))
	
	if kEraBonuses.StartingPopulationCapital and city == player:GetCities():GetCapitalCity() then 
		city:ChangePopulation(kEraBonuses.StartingPopulationCapital-1)
	elseif kEraBonuses.StartingPopulationOtherCities then
		city:ChangePopulation(kEraBonuses.StartingPopulationOtherCities-1)
	end
	
	for kBuildings in GameInfo.StartingBuildings() do
		if GameInfo.Eras[kBuildings.Era].Index <= playerEra and kBuildings.District == "DISTRICT_CITY_CENTER" then
			local iBuilding = GameInfo.Buildings[kBuildings.Building].Index
			if not city:GetBuildings():HasBuilding(iBuilding) then
				print("Starting Building = "..tostring(kBuildings.Building))
				WorldBuilder.CityManager():CreateBuilding(city, kBuildings.Building, 100, cityPlot)
			end
		end
	end
	
	-- Super Monument
	local iTurn = Game.GetCurrentGameTurn()
	-- local startTurn = GameConfiguration.GetStartTurn()	
	if superMonument and (iTurn ~= 1) then
		local loyaltyBuilding = "BUILDING_SUPER_MONUMENT"
		print("Spawning "..tostring(loyaltyBuilding))
		if GameInfo.Buildings[loyaltyBuilding] then
			--WorldBuilder.CityManager():CreateBuilding(city, loyaltyBuilding, 100, cityPlot)
			local pCityBuildQueue = city:GetBuildQueue()
			pCityBuildQueue:CreateIncompleteBuilding(GameInfo.Buildings[loyaltyBuilding].Index, 100)
		end	
	end	
	
	-- Check for Palace
	if pCapital then
		local palaceBuilding = GameInfo.Buildings["BUILDING_PALACE"].Index		
		print("Has a palace is "..tostring(pCapital:GetBuildings():HasBuilding(palaceBuilding)))
		if pCapital:GetBuildings():HasBuilding(palaceBuilding) then

			print("Palace detected in capital.")
		else
			local pCityBuildQueue = pCapital:GetBuildQueue()
			pCityBuildQueue:CreateIncompleteBuilding(palaceBuilding, 100)			
			-- WorldBuilder.CityManager():CreateBuilding(city, palaceBuilding, 100, cityPlot)
			print("Palace not detected in capital. Spawning a new Palace")
		end
	end
	
	for kUnits in GameInfo.MajorStartingUnits() do
		if GameInfo.Eras[kUnits.Era].Index == playerEra and kUnits.OnDistrictCreated and not (kUnits.AiOnly) then -- (player:IsHuman() and kUnits.AiOnly) -- to do : difficulty difference check
			local numUnit = math.max(kUnits.Quantity, 1)
			print(" - "..tostring(kUnits.Unit).." = "..tostring(numUnit))			
			if not kUnits.Unit == "UNIT_TRADER" then
				UnitManager.InitUnitValidAdjacentHex(iPlayer, kUnits.Unit, x, y, numUnit)
			end
		end
	end	
	
end

-- test capture or creation (these functions are no longer being used)
-- totalslacker: The capture test will only work the first time a city is conquered...
--	It checks the Player ID at the time the city center is removed and compares to original owner ID
--	TODO: Better solution?
local cityCaptureTest = {}
function CityCaptureDistrictRemoved(iPlayer, districtID, cityID, iX, iY)
	local key = iX..","..iY
	cityCaptureTest[key]			= {}
	cityCaptureTest[key].Turn 		= Game.GetCurrentGameTurn()
	cityCaptureTest[key].iPlayer 	= iPlayer
	cityCaptureTest[key].CityID 	= cityID
end
function CityCaptureCityInitialized(iPlayer, cityID, iX, iY)
	local key = iX..","..iY
	local bCaptured = false
	if (	cityCaptureTest[key]
		and cityCaptureTest[key].Turn 	== Game.GetCurrentGameTurn() )
	then
		cityCaptureTest[key].CityInitializedXY = true
		local city = CityManager.GetCity(iPlayer, cityID)
		local originalOwnerID 	= city:GetOriginalOwner()
		local currentOwnerID	= city:GetOwner()
		if cityCaptureTest[key].iPlayer == originalOwnerID then
			print("City captured")
			cityCaptureTest[key] = {}
			bCaptured = true
			OnCityCaptured(currentOwnerID, cityID)
		end
	end
	local CivilizationTypeName = PlayerConfigurations[iPlayer]:GetCivilizationTypeName()
	print (tostring(CivilizationTypeName) .. " is founding a city.")	
	if not bCaptured then
		OnCityInitialized(iPlayer, cityID, iX, iY)
	end
end


-- Initialize
function OnLoadScreenClosed()
	if bApplyBalance then
		-- Events.DistrictRemovedFromMap.Add(CityCaptureDistrictRemoved)
		-- Events.CapitalCityChanged.Add(CapitalWasChanged)
		Events.CityInitialized.Add(OnCityInitialized)
		GameEvents.CityConquered.Add(CityWasConquered)
	end
end
Events.LoadScreenClose.Add(OnLoadScreenClosed)

--[[
function FoundFirstPotentialSpawn()
	for iPlayer = 0, PlayerManager.GetWasEverAliveCount() - 1 do
		local player = Players[iPlayer]
		if player and not player:IsBarbarian() then-- and not player:IsAlive() then
			if SpawnPlayer(iPlayer) then return end
		end
	end
end
--GameEvents.OnGameTurnStarted.Add( FoundFirstPotentialSpawn )

function FoundNextPotentialSpawn(iCurrentAlivePlayer)
	for iPlayer = iCurrentAlivePlayer + 1, PlayerManager.GetWasEverAliveCount() - 1 do
		local player = Players[iPlayer]
		if player and not player:IsBarbarian() then --and not player:IsAlive() then
			if SpawnPlayer(iPlayer) then return end
		end
	end
end
--Events.PlayerTurnDeactivated.Add( FoundNextPotentialSpawn )
--]]

----------------------------------------------------------------------------------------
end
----------------------------------------------------------------------------------------
-- Historical Spawn Dates >>>>>
----------------------------------------------------------------------------------------