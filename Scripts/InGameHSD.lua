------------------------------------------------------------------------------
--	FILE:	 InGameHSD.lua
--  Gedemon (2017)
--	changelog (Gathering Storm):
--	(*)	added ExposedMembers context for UI
------------------------------------------------------------------------------
include("ScriptHSD.lua");
print ("loading InGameHSD.lua")

----------------------------------------------------------------------------------------
-- Historical Spawn Dates <<<<<
----------------------------------------------------------------------------------------

--totalslacker: added these to ExposedMembers for UI and Gameplay scripts to communicate after Gathering Storm update
LuaEvents = ExposedMembers.LuaEvents

local defaultQuickMovement 	= UserConfiguration.GetValue("QuickMovement")
local defaultQuickCombat 	= UserConfiguration.GetValue("QuickCombat")
local defaultAutoEndTurn	= UserConfiguration.GetValue("AutoEndTurn") 

function SetTurnYear(iTurn)
	previousTurnYear 	= Calendar.GetTurnYearForGame( iTurn )
	currentTurnYear 	= Calendar.GetTurnYearForGame( iTurn + 1 )
	nextTurnYear 		= Calendar.GetTurnYearForGame( iTurn + 2 )
	GameConfiguration.SetValue("PreviousTurnYear", previousTurnYear)
	GameConfiguration.SetValue("CurrentTurnYear", currentTurnYear)
	GameConfiguration.SetValue("NextTurnYear", nextTurnYear)
	LuaEvents.SetPreviousTurnYear(previousTurnYear)
	LuaEvents.SetCurrentTurnYear(currentTurnYear)
	LuaEvents.SetNextTurnYear(nextTurnYear)
end
Events.TurnEnd.Add( SetTurnYear )

function SetAutoValues()
	--UserConfiguration.SetValue("QuickMovement", 1)
	--UserConfiguration.SetValue("QuickCombat", 1)
	UserConfiguration.SetValue("AutoEndTurn", 1)
end
LuaEvents.SetAutoValues.Add(SetAutoValues)

function RestoreAutoValues()
	--UserConfiguration.SetValue("QuickMovement", defaultQuickMovement)
	--UserConfiguration.SetValue("QuickCombat", 	defaultQuickCombat 	)
	UserConfiguration.SetValue("AutoEndTurn", 	defaultAutoEndTurn	)
end
LuaEvents.RestoreAutoValues.Add(RestoreAutoValues)

function SetStartingEra(iPlayer, era)
	local key = "StartingEra"..tostring(iPlayer)
	print ("saving key = "..key..", value = ".. tostring(era))
	GameConfiguration.SetValue(key, era)
end
LuaEvents.SetStartingEra.Add( SetStartingEra )

function CheckCityGovernor(pPlayerID, pCityID)
	local pPlayer = Players[pPlayerID]
	local pCity = pPlayer:GetCities():FindID(pCityID)
	local pGovernor = pCity:GetAssignedGovernor()
	local pCapital = pCity:IsOriginalCapital()
	if (pGovernor == nil or not pGovernor:IsEstablished()) and not pCapital then
		print ("Returning city ID to transfer to free cities")
		local pFreeCityID = pCity:GetID()
		return pFreeCityID
	else
		print ("City could not be transferred to free cities")
		return false
	end
end
ExposedMembers.CheckCity.CheckCityGovernor = CheckCityGovernor

function CheckCityOriginalCapital(pPlayerID, pCityID)
	local pPlayer = Players[pPlayerID]
	local pCity = CityManager.GetCity(iPlayer, cityID)
	local bOriginalCapital = false
	-- if pCity:IsOriginalCapital() then 
		-- print("IsOriginalCapital is "..tostring(pCity:IsOriginalCapital()))
		-- bOriginalCapital = true 
	-- end
	if pPlayer:IsMajor() and pCity then
		if pCity:IsOriginalCapital() and pCity:GetOriginalOwner() == pCity:GetOwner() then
			if pCity:IsCapital() then
				-- Original capitial still owned by original owner
				print("Found original capital")
				return false
			else
				local pOriginalOwner = pCity:GetOriginalOwner()
				print("Found occupied capital")
				return pOriginalOwner
			end
		elseif pCity:IsOriginalCapital() and pCity:GetOriginalOwner() ~= pCity:GetOwner() then
			local pOriginalOwner = pCity:GetOriginalOwner()
			print("Found occupied capital")
			return pOriginalOwner			
		elseif pCity:IsCapital() then
			-- New capital
			print("Found new capital")
			return false
		else
			-- Other cities
			print("Found non-capital city")
			return false
		end	
	end
	return bOriginalCapital
end
ExposedMembers.CheckCityOriginalCapital = CheckCityOriginalCapital

-- all credit for the code below goes to Tiramasu, taken from the Free City States mod
function GetPlayerCityUIDatas(pPlayerID, pCityID)
	local CityUIDataList = {}	
	local pPlayer = Players[pPlayerID]
	local pCity = pPlayer:GetCities():FindID(pCityID)	
	if pCity then	
		local kCityUIDatas :table = {	
			iPosX = nil,
			iPosY = nil,
			iCityID = nil,
			sCityName = "",
			CityPlotCoordinates = {},
			CityDistricts = {},
			CityBuildings = {},
			CityReligions = {},
		}		
		--General City Datas:
		kCityUIDatas.iPosX = pCity:GetX()
		kCityUIDatas.iPosY = pCity:GetY()		
		kCityUIDatas.iCityID = pCity:GetID()
		kCityUIDatas.sCityName = pCity:GetName()
		--City Tiles Datas:
		local kCityPlots :table = Map.GetCityPlots():GetPurchasedPlots( pCity )				
		for _,plotID in pairs(kCityPlots) do
			local pPlot:table = Map.GetPlotByIndex(plotID)
			local kCoordinates:table = {
				iX = pPlot:GetX(), 
				iY = pPlot:GetY() 
			}
			table.insert(kCityUIDatas.CityPlotCoordinates, kCoordinates)
		end
		--City District Datas:
		local pCityDistricts :table	= pCity:GetDistricts()			
		for _, pDistrict in pCityDistricts:Members() do
			table.insert(kCityUIDatas.CityDistricts, {
				iPosX = pDistrict:GetX(), 
				iPosY = pDistrict:GetY(), 
				iType = pDistrict:GetType(), 
				bPillaged = pCityDistricts:IsPillaged(pDistrict:GetType()),
			})
		end
		--City Buildings Datas: (actually these Datas can also be accessed in gameplay context)
		local pCityBuildings = pCity:GetBuildings()
		for pBuilding in GameInfo.Buildings() do
			if( pCityBuildings:HasBuilding(pBuilding.Index) ) then				
				table.insert(kCityUIDatas.CityBuildings, {				
					iBuildingID = pBuilding.Index,
					bIsPillaged = pCityBuildings:IsPillaged(pBuilding.Index),
				})
			end
		end
		--Religious Pressure Data:
		local pReligions :table = pCity:GetReligion():GetReligionsInCity()
		for _, religionData in pairs(pReligions) do
			table.insert(kCityUIDatas.CityReligions, {
				iReligionType = religionData.Religion,
				iPressure = religionData.Pressure,
			})
		end
		--Save all City Datas:
		table.insert(CityUIDataList, kCityUIDatas)
	end	
	return CityUIDataList
end
ExposedMembers.GetPlayerCityUIDatas = GetPlayerCityUIDatas

-- Set current & next turn year ASAP when (re)loading
LuaEvents.SetCurrentTurnYear(Calendar.GetTurnYearForGame(Game.GetCurrentGameTurn()))
LuaEvents.SetNextTurnYear(Calendar.GetTurnYearForGame(Game.GetCurrentGameTurn()+1))

-- Broacast that we're ready to set HSD
LuaEvents.InitializeHSD()


