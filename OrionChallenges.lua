-----------------------------------------------------------------------------------------------
-- Client Lua Script for OrionChallenges
-- Copyright (c) NCsoft. All rights reserved
-- 
-- OrionChallenges (c) 2014 Christian Troller (http://www.christiantroller.ch) (http://www.github.com/ctroller)
-- OrionChallenges can be downloaded from Curse (http://www.curse.com/ws-addons/wildstar/222022-orionchallenges)
-- 
-----------------------------------------------------------------------------------------------
-- Licensed under the Apache License, Version 2.0 (the "License"); you may not use this file except in compliance with
-- the License. You may obtain a copy of the License at
-- 
-- http://www.apache.org/licenses/LICENSE-2.0
--
-- Unless required by applicable law or agreed to in writing, software distributed under the License is distributed on
-- an "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied. See the License for the
-- specific language governing permissions and limitations under the License.
-----------------------------------------------------------------------------------------------
 
require "Window"
require "ChallengesLib"

local bit = nil
 
-----------------------------------------------------------------------------------------------
-- OrionChallenges Module Definition
-----------------------------------------------------------------------------------------------
local OrionChallenges = {}

-- Default OrionChallenges settings
local tDefaultSettings = {
	nMaxItems					= 10,		-- maximum number of displayed challenges
	nFilteredChallenges			= 0,		-- BITWISE representation of filtered challenges -> see ktFilters for filter masks
	bLockWindow					= false,	-- lock window position
	bAutostart					= false,	-- autostart challenges
	bAutoloot					= false,	-- autoloot challenges
	bHideWindowOnChallenge		= false,	-- hide frame when starting a challenge
	bHideUnderground			= false,	-- hide underground challenges, or else display it with "?" distance
	bShowIgnoredChallenges		= false,	-- show ignored challenges
	tIgnoredChallenges			= {},
	bShowChallengesOnMap		= true,		-- show challenges on zone map
	bHideCompletedChallenges	= false,	-- hide completed challenges
	bShown						= false,
	bDebug						= false
}
 
-----------------------------------------------------------------------------------------------
-- Constants
-----------------------------------------------------------------------------------------------
-- e.g. local kiExampleVariableMax = 999
local kcrSelectedText = ApolloColor.new("UI_BtnTextHoloPressedFlyby")
local kcrNormalText = ApolloColor.new("UI_BtnTextHoloNormal")

-- Medal Sprite locations
local ksSpriteBronzeMedal	= "CRB_ChallengeTrackerSprites:sprChallengeTierBronze"
local ksSpriteSilverMedal	= "CRB_ChallengeTrackerSprites:sprChallengeTierSilver"
local ksSpriteGoldMedal		= "CRB_ChallengeTrackerSprites:sprChallengeTierGold"

local ksSpriteChallenge		= "CRB_ChallengeTrackerSprites:sprChallengeTypeGenericLarge"

-- type filters
-- combine filters for enabling multiple type filterling, like (FILTER_GENERAL + FILTER_COMBAT) = 9, etc
local ktFilters = {
	FILTER_GENERAL	= 1,
	FILTER_ITEM		= 2,
	FILTER_ABILITY	= 4,
	FILTER_COMBAT	= 8
}

-- Addon Version
local nVersion, nMinor, nTick = 1, 4, 0
local sAuthor = "Troxito@EU-Progenitor"

local bInitializing = false
 
-----------------------------------------------------------------------------------------------
-- Initialization
-----------------------------------------------------------------------------------------------
function OrionChallenges:new(o)
    o = o or {}
    setmetatable(o, self)
    self.__index = self 

    -- initialize variables here
	o.tItems = {} -- keep track of all the list items
	o.wndSelectedListItem = nil -- keep track of which list item is currently selected

    return o
end

function OrionChallenges:Init()
	local bHasConfigureFunction = false
	local strConfigureButtonText = ""
	local tDependencies = {
		-- "UnitOrPackageName",
	}
    Apollo.RegisterAddon(self, bHasConfigureFunction, strConfigureButtonText, tDependencies)
end
 

-----------------------------------------------------------------------------------------------
-- OrionChallenges OnLoad
-----------------------------------------------------------------------------------------------
function OrionChallenges:OnLoad()
	bit = Apollo.GetPackage("Orion:numberlua-1.0").tPackage.bit
    -- load our form file
	self.xmlDoc = XmlDoc.CreateFromFile("OrionChallenges.xml")
	self.xmlDoc:RegisterCallback("OnDocLoaded", self)
end

-----------------------------------------------------------------------------------------------
-- OrionChallenges OnDocLoaded
-----------------------------------------------------------------------------------------------
function OrionChallenges:OnDocLoaded()
	if self.xmlDoc ~= nil and self.xmlDoc:IsLoaded() then
	    self.wndMain = Apollo.LoadForm(self.xmlDoc, "OrionChallengesForm", nil, self)
		if self.wndMain == nil then
			Apollo.AddAddonErrorText(self, "Could not load the main window for some reason.")
			return
		end

		-- item list
		self.wndItemList = self.wndMain:FindChild("ItemList")
		self.wndMain:Show(false, true)
		self:RestoreWindowPosition()

		-- if the xmlDoc is no longer needed, you should set it to nil
		-- self.xmlDoc = nil
		
		-- Register handlers for events, slash commands and timer, etc.
		-- e.g. Apollo.RegisterEventHandler("KeyDown", "OnKeyDown", self)
		Apollo.RegisterSlashCommand("oc", "OnOrionChallengesToggle", self)
		
		Apollo.RegisterEventHandler("SubZoneChanged",				"OnSubZoneChanged",					self)
		Apollo.RegisterEventHandler("ChallengeUnlocked",			"InvalidateCachedChallenges",		self)
		Apollo.RegisterEventHandler("InterfaceMenuListHasLoaded",	"OnInterfaceMenuListHasLoaded",		self)
		Apollo.RegisterEventHandler("OrionChallengesToggle",		"OnOrionChallengesToggle",			self)
		Apollo.RegisterEventHandler("OrionChallengesOrderChanged",	"OnOrionChallengesOrderChanged",	self)
		Apollo.RegisterEventHandler("WindowManagementReady",		"OnWindowManagementReady",			self)
        
		Apollo.RegisterEventHandler("ChallengeActivate",			"OnChallengeActivate",				self)
		Apollo.RegisterEventHandler("ChallengeAbandon",				"OnChallengeAbandon",				self)
		Apollo.RegisterEventHandler("ChallengeCompleted",			"OnChallengeCompleted",				self)
		
		Apollo.RegisterEventHandler("ToggleZoneMap", 				"OnToggleZoneMap", 					self)
		Apollo.RegisterEventHandler("GenericEvent_ZoneMap_ZoneChanged", "OnZoneMapInit", self)
		
		self.timerPos = ApolloTimer.Create(0.5, true, "TimerUpdateDistance", self)
		self.timerPos:Stop()
		self.currentZoneId = -1
		self.tCachedChallenges = {}
		self.tChallenges = {}
		self.populating = false
		self.bHiddenBySetting = false
		self.tChallengesById = {}
		
		self.tZoneMapObjects = {}
		
		self.wndMain:FindChild("Header"):FindChild("Title"):SetText("OrionChallenges v"..nVersion.."."..nMinor.."."..nTick)
		self.wndMain:FindChild("Header"):FindChild("Title"):SetTooltip("Written by "..sAuthor)
		
		self.wndSettings = Apollo.LoadForm(self.xmlDoc, "Settings", nil, self)
		self.wndSettings:Show(false)
		
		if not self.tUserSettings then
			self.tUserSettings = tDefaultSettings
		end
		
		self:UpdateSettingControls()
		
		if self.tUserSettings.bShown and self.wndMain and not self.wndMain:IsShown() then
			self:OnOrionChallengesToggle()
		end
			
		self:Debug("Initialized")
	end
end

-----------------------------------------------------------------------------------------------
-- OrionChallenges Functions
-----------------------------------------------------------------------------------------------
-- Define general functions here

---------------------------------
-- Prints a string to the debug chat channel
-- @param str The string to print
---------------------------------
function OrionChallenges:Debug(str)
	if self.tUserSettings and self.tUserSettings.bDebug then
		Print("[OrionChallenges] " .. str)
	end
end

-----------------------------------------------------------------------------------------------
-- Hook Functions
-----------------------------------------------------------------------------------------------

function OrionChallenges:RestoreWindowPosition()
	if self.wndMain and self.tUserSettings.tAnchor ~= nil then
		self.wndMain:SetAnchorOffsets(unpack(self.tUserSettings.tAnchor))
	end
end

---------------------------------
-- Zone Map interaction
---------------------------------

function OrionChallenges:OnZoneMapInit()
	self:Debug("OnZoneMapInit")
	local zoneMap = self:GetZoneMap()
	
	if zoneMap ~= nil then	
		-- only do this if we haven't initialized the overlay type (=wndZoneMap PRESENT)
		if self.eObjectTypeChallenge == nil then
			if zoneMap then
				self.eObjectTypeChallenge = zoneMap.wndZoneMap:CreateOverlayType() -- create a new overlay type for filtering
				self.wndZoneMap = zoneMap.wndZoneMap -- store the zone map copy
					
				-- now we need to add the new overlay type to the allowed zoom types of the zone map
				table.insert(zoneMap.arAllowedTypesScaled, self.eObjectTypeChallenge)
				table.insert(zoneMap.arAllowedTypesPanning, self.eObjectTypeChallenge)
				table.insert(zoneMap.arAllowedTypesSuperPanning, self.eObjectTypeChallenge)
			end
		end
			
		-- and set it visible by default.
		zoneMap:SetTypeVisibility(self.eObjectTypeChallenge, true)
		self:AddChallengesToZoneMap()
	end
end

function OrionChallenges:AddChallengesToZoneMap()
	if self.wndZoneMap and self.tUserSettings.bShowChallengesOnMap and self.eObjectTypeChallenge then
		self:Debug("AddChallengesToZoneMap")
		for k, challenge in pairs(self.tChallenges) do
			if self.tZoneMapObjects[challenge:GetId()] == nil then
				local loc = challenge:GetMapLocation()
				if loc ~= nil then
					local tInfo = {
						strIcon = ksSpriteChallenge,
						strIconEdge = "",
						crObject = challenge:GetCompletionCount()>0 and  CColor.new(1, 1, 1, 1) or CColor.new(0.5, 0.5, 0.5, 1),				
						crEdge = CColor.new(1, 1, 1, 1)
					}
					
					self.tZoneMapObjects[challenge:GetId()] = self.wndZoneMap:AddObject(self.eObjectTypeChallenge, loc, "Challenge: "..challenge:GetName(), tInfo, {bNeverShowOnEdge = true, bFixedSizeMedium = true})
				end
			end		
		end
	end
end

---------------------------------
-- Invoked when the main window is shown
---------------------------------
function OrionChallenges:OnOrionChallengesToggle()
	self:Debug("OnOrionChallengesToggle")
	local visible = self.wndMain:IsShown()
	if not visible then
		self:LockUnlockWindow()
		self.timerPos:Start()
		self:RestoreWindowPosition()
		self:PopulateItemList()
		self.tUserSettings.bShown = true
	else
		self.timerPos:Stop()
		self:OnSettingsClose()
		self.tUserSettings.bShown = false
	end

	self.wndMain:Show(not visible)
end

---------------------------------
-- Invoked when the player changes his subzone
---------------------------------
function OrionChallenges:OnSubZoneChanged()
	if self.currentZoneId ~= GameLib.GetCurrentZoneId() then
		self:Debug("Zone changed. From " .. self.currentZoneId .. " to " .. GameLib.GetCurrentZoneId())
		self.currentZoneId = GameLib.GetCurrentZoneId()
		self:PopulateItemList(true)
	end
end

---------------------------------
-- Invoked every 0.5s
-- Handles distance and button updates for every currently active challenge
---------------------------------
function OrionChallenges:TimerUpdateDistance()
	if GameLib.GetPlayerUnit() then
		self.curPosition = GameLib.GetPlayerUnit():GetPosition()
		if self.curPosition == nil then return end
		if self.lastPosition == nil then
			self.lastPosition = self.curPosition
		end
		
		local moving = true
		if  math.abs(self.lastPosition.x - self.curPosition.x) < 0.01 and 
			math.abs(self.lastPosition.y - self.curPosition.y) < 0.01 and 
			math.abs(self.lastPosition.z - self.curPosition.z) < 0.01 then	
			moving = false
		end

		for i=1, #self.tItems do
			if moving then self:UpdateDistance(i) end
			self:HandleButtonControl(i)
		end
		
		self.lastZoneId = self.currentZoneId
	end
end

function OrionChallenges:OnIgnoreChallengeToggle(wndHandler, wndControl)
	if wndHandler ~= wndControl then return end
	local data = wndControl:GetParent():GetData()
	
	self:Debug("OnIgnoreChallengeToggle")
	if data ~= nil then
		local challenge = data.challenge
		if self:IsIgnored(challenge) then
			self:IgnoreChallenge(challenge, false)
		else
			self:IgnoreChallenge(challenge, true)
		end
		
		self:PopulateItemList()
		self:HandleButtonControl(data.index)
	end
end

---------------------------------
-- Invoked when an item is clicked in the frame
---------------------------------
function OrionChallenges:OnListItemSelected(wndHandler, wndControl)
    -- make sure the wndControl is valid
    if wndHandler ~= wndControl then
        return
    end
    
    -- change the old item's text color back to normal color
    local wndItemText
    if self.wndSelectedListItem ~= nil then
        wndItemText = self.wndSelectedListItem:FindChild("Text")
        wndItemText:SetTextColor(kcrNormalText)
    end
    
	-- wndControl is the item selected - change its color to selected
	self.wndSelectedListItem = wndControl
	wndItemText = self.wndSelectedListItem:FindChild("Text")
    wndItemText:SetTextColor(kcrSelectedText)

	local data = wndControl:GetData()
	ChallengesLib.ShowHintArrow(data.challenge:GetId())
end


---------------------------------
-- Invoked when the challenge control button is clicked
---------------------------------
function OrionChallenges:OnChallengeControlClicked(wndHandler, wndControl)
	if wndHandler ~= wndControl then
        return
    end
	local data = wndControl:GetParent():GetData()
	if data ~= nil then
		local challenge = data.challenge
		if challenge:ShouldCollectReward() then
			Event_FireGenericEvent("ChallengeRewardShow", challenge:GetId())
		elseif challenge:IsActivated() then
			ChallengesLib.AbandonChallenge(challenge:GetId())
		else
			ChallengesLib.ShowHintArrow(challenge:GetId())
			ChallengesLib.ActivateChallenge(challenge:GetId())
		end
		
		self:HandleButtonControl(data.index)
	end
end

---------------------------------
-- Invoked when the interface menu list has loaded
---------------------------------
function OrionChallenges:OnInterfaceMenuListHasLoaded()
	Event_FireGenericEvent("InterfaceMenuList_NewAddOn", "OrionChallenges", {"OrionChallengesToggle", "", "Icon_Windows32_UI_CRB_InterfaceMenu_ChallengeLog"})
end

---------------------------------
-- Invoked when the currently displayed challenge order has changed
---------------------------------
function OrionChallenges:OnOrionChallengesOrderChanged()
	self.tChallenges = self:GetChallengesByZoneSorted()
	self:PopulateItemList()
end

---------------------------------
-- Enables window management support
---------------------------------
function OrionChallenges:OnWindowManagementReady()
    --Event_FireGenericEvent("WindowManagementAdd", {wnd = self.wndMain, strName = "OrionChallenges"})
end


---------------------------------
-- Challenge Hooks
---------------------------------
function OrionChallenges:OnChallengeActivate()
	if self.tUserSettings.bHideWindowOnChallenge and self.wndMain:IsShown() then
		self.bHiddenBySetting = true
		self:OnOrionChallengesToggle()
	end
end

function OrionChallenges:ShowWindowAfterChallenge()
--	self:Debug("ShowWindowAfterChallenge: " .. self.tUserSettings.bHideWindowOnChallenge and 1 or 0 .. "|" .. self.bHiddenBySetting and 1 or 0)
	if self.tUserSettings.bHideWindowOnChallenge and self.bHiddenBySetting then
		self.bHiddenBySetting = false
		self:OnOrionChallengesToggle()
	end
end

function OrionChallenges:GetChallengeById(nChallengeId)
	if self.tChallengesById[nChallengeId] ~= nil then
		return self.tChallengesById[nChallengeId]
	end
	
	for i, challenge in pairs(ChallengesLib.GetActiveChallengeList()) do
		if i == nChallengeId then
			self.tChallengesById[nChallengeId] = challenge
			return challenge
		end
	end
end

function OrionChallenges:OnChallengeAbandon(nChallengeId)
	self:ShowWindowAfterChallenge()
	local challenge = self:GetChallengeById(nChallengeId)
	if self.tUserSettings.bAutoloot and challenge:ShouldCollectReward() then
		Event_FireGenericEvent("ChallengeRewardShow", nChallengeId)
	end
end

function OrionChallenges:OnChallengeCompleted(nChallengeId)
	self:ShowWindowAfterChallenge()
	if self.tUserSettings.bAutoloot then
		Event_FireGenericEvent("ChallengeRewardShow", nChallengeId)
	end
end

-----------------------------------------------------------------------------------------------
-- General Functions
-----------------------------------------------------------------------------------------------

---------------------------------
-- Returns the number of currently maximum displayed challenges
-- @return Number of currently maximum displayed challenges
---------------------------------
function OrionChallenges:GetMaxChallenges()
	local challenges = self.tChallenges
	return #challenges < self.tUserSettings.nMaxItems and #challenges or self.tUserSettings.nMaxItems
end

---------------------------------
-- Resizes the main window to match the number of challenges displayed
---------------------------------
function OrionChallenges:ResizeHeight()
	local nLeft, nTop, nRight, nBottom = self.wndMain:GetAnchorOffsets()
	self.wndMain:SetAnchorOffsets(nLeft, nTop, nRight, nTop + 45 + (25 * self:GetMaxChallenges()))

	if self.wndSettings:IsShown() then
		self:RepositionSettingsFrame()
	end
end

---------------------------------
-- Invalidates the challenge cache
---------------------------------
function OrionChallenges:InvalidateCachedChallenges()
	local nZoneId = GameLib.GetCurrentZoneId()
	if nZoneId ~= nil and self.tCachedChallenges[nZoneId] ~= nil then
		self.tCachedChallenges[nZoneId] = nil
	end
end

---------------------------------
-- Returns an unsorted list of challenges which belong to a given (default: current zone) zone
-- @param nZoneId the zone id to filter challenges from
-- @return A table of filtered challenges
---------------------------------
function OrionChallenges:GetChallengesByZone(nZoneId)
	nZoneId = nZoneId and nZoneId or GameLib.GetCurrentZoneId()
	
	if self.tCachedChallenges[nZoneId] ~= nil then
		return self.tCachedChallenges[nZoneId]
	end
	
	local returnValue = {}
	
	for i, challenge in pairs(ChallengesLib.GetActiveChallengeList()) do
		if GameLib.IsZoneInZone(GameLib.GetCurrentZoneId(), challenge:GetZoneInfo().idZone) then
			table.insert(returnValue, challenge)
		end
	end
	
	return returnValue
end

---------------------------------
-- Returns an sorted (by distance) list of challenges which belong to a given (default: current zone) zone
-- @param nZoneId the zone id to filter challenges from
-- @return A table of filtered and sorted challenges
---------------------------------
function OrionChallenges:GetChallengesByZoneSorted(nZoneId)
	local challenges = self:GetChallengesByZone(nZoneId)
	
	-- filter based on user settings
	local filteredChallenges = {}
	for k, challenge in pairs(challenges) do
		local nChallengeType = challenge:GetType()
		if self:IsIgnored(challenge) then
			self:Debug("Challenge " .. challenge:GetName() .. " is ignored. Display? " .. (self.tUserSettings.bShowIgnoredChallenges and "true" or "false"))
		end
		if not (self.tUserSettings.bHideUnderground and self:GetChallengeDistance(challenge) == nil) 
			and not ((nChallengeType == ChallengesLib.ChallengeType_General and self:HasFilter(ktFilters.FILTER_GENERAL))
				or (nChallengeType == ChallengesLib.ChallengeType_Item and self:HasFilter(ktFilters.FILTER_ITEM))
				or (nChallengeType == ChallengesLib.ChallengeType_Ability and self:HasFilter(ktFilters.FILTER_ABILITY))
				or (nChallengeType == ChallengesLib.ChallengeType_Combat and self:HasFilter(ktFilters.FILTER_COMBAT)))
			and not (not self.tUserSettings.bShowIgnoredChallenges and self:IsIgnored(challenge))
			and not (self.tUserSettings.bHideCompletedChallenges and challenge:GetCompletionCount() > 0)
		then
			table.insert(filteredChallenges, challenge)
		end
	end
	
	table.sort(filteredChallenges, function(challenge1, challenge2) 
		local dist1 = self:GetChallengeDistance(challenge1)
		local dist2 = self:GetChallengeDistance(challenge2)
		if dist1 == nil and not self.tUserSettings.bHideUnderground then dist1 = -1 end
		if dist2 == nil and not self.tUserSettings.bHideUnderground then dist2 = -1 end
		local sameDist = dist1 == dist2
		return sameDist and challenge1:GetName() > challenge2:GetName() or dist1 < dist2
	end)
	
	return filteredChallenges
end

function OrionChallenges:IgnoreChallenge(challenge, bIgnore)
	local id = challenge:GetId()
	bIgnore = (bIgnore == nil and true or bIgnore)
	self.tUserSettings.tIgnoredChallenges[id] = bIgnore and bIgnore or nil
end

function OrionChallenges:IsIgnored(challenge)
	return self.tUserSettings.tIgnoredChallenges[challenge:GetId()] == true
end

---------------------------------
-- Returns the distance in meters from the player to a challenge 
-- @param challenge The challenge object to check agains
-- @return Float representation of the distance in meters
---------------------------------
function OrionChallenges:GetChallengeDistance(challenge)
	if challenge ~= nil and challenge:GetMapLocation() ~= nil then
		local target = challenge:GetMapLocation()
		if GameLib.GetPlayerUnit() then
			local player = GameLib.GetPlayerUnit():GetPosition()
			return Vector3.New(target.x - player.x, target.y - player.y, target.z - player.z):Length()
		end
	end
	
	return nil
end

---------------------------------
-- Does the control button magicks
-- @param index The selected button item index
---------------------------------
function OrionChallenges:HandleButtonControl(index)
	local wnd = self.tItems[index]
	if wnd then
		local challenge = wnd:GetData().challenge
		local wndItemText = wnd:FindChild("Text")
		local wndDistance = wnd:FindChild("Distance")
		local wndControl = wnd:FindChild("Control")
		local wndTimer = wnd:FindChild("Timer")
		local wndIgnore = wnd:FindChild("Ignore")
	
		local startable = not challenge:IsInCooldown() and self:IsStartable(challenge)
				and not challenge:IsActivated() and not challenge:ShouldCollectReward() 
				and self:HelperIsInZone(challenge:GetZoneRestrictionInfo())
		local sText, sBGColor, bEnableCtrl = "", "ff000000", true
		
		wndTimer:Show(false)
		if startable then
			sText = "Start"
			sBGColor = "ff00ff00"
		elseif challenge:IsActivated() then
			sText = "Stop"
			sBGColor = "ffda4f49"
		elseif challenge:ShouldCollectReward() then
			sText = "Loot"
			sBGColor = "ffdaa520"
		elseif challenge:IsInCooldown() then
			bEnableCtrl = false
			wndTimer:Show(true)
			wndTimer:SetText(challenge:GetTimeStr())
		else
			bEnableCtrl = false
		end
		
		if wndIgnore then
			local sTooltip = "Visible"
			if self:IsIgnored(challenge) then
				sTooltip = "Ignored"
			end
			
			wndIgnore:SetCheck(not self:IsIgnored(challenge))
			wndIgnore:SetTooltip(sTooltip)
		end
		wndControl:SetText(sText)
		wndControl:SetBGColor(sBGColor)
		wndControl:Show(bEnableCtrl)
		
		wndItemText:SetText((self.tUserSettings.bDebug and "#"..challenge:GetId().." " or "")..challenge:GetName())
		wndItemText:SetTextColor(kcrNormalText)
		
		self:UpdateDistance(index, challenge)
	end
end
-----------------------------------------------------------------------------------------------
-- Helper functions
-----------------------------------------------------------------------------------------------
function OrionChallenges:HelperIsInZone(tZoneRestrictionInfo)
	return tZoneRestrictionInfo.idSubZone == 0 or GameLib.IsInWorldZone(tZoneRestrictionInfo.idSubZone)
end

function OrionChallenges:IsStartable(clgCurrent)
    return clgCurrent:GetCompletionCount() < clgCurrent:GetCompletionTotal() or clgCurrent:GetCompletionTotal() == -1
end

function OrionChallenges:GetZoneMap()
	--								Carbine		jjflanigan
	local tOrderedZoneMapAddons = { "ZoneMap", "GuardZoneMap" }
	for k, v in pairs(tOrderedZoneMapAddons) do
		local zoneMap = Apollo.GetAddon(v)
		if zoneMap ~= nil then
			return zoneMap
		end
	end
end

-----------------------------------------------------------------------------------------------
-- ItemList Functions
-----------------------------------------------------------------------------------------------
-- populate item list
function OrionChallenges:PopulateItemList(bForce)
	if not self.populating or bForce then
		self:Debug("Populating.")
		self.populating = true
		-- make sure the item list is empty to start with
		self:DestroyItemList()
	
		local challenges = self:GetChallengesByZoneSorted()
		
		self.tChallenges = challenges		
		for i = 1, self:GetMaxChallenges() do
			local clg = challenges[i]
			self:AddItem(i, clg)	
			--self:AddToZoneMap(clg)
		end

		-- now all the item are added, call ArrangeChildrenVert to list out the list items vertically
		self:ResizeHeight() 
		self.wndItemList:ArrangeChildrenVert()
		self.populating = false
	end
end

-- clear the item list
function OrionChallenges:DestroyItemList()
	-- destroy all the wnd inside the list
	for idx,wnd in ipairs(self.tItems) do
		wnd:Destroy()
	end

	-- clear the list item array
	self.tItems = {}
	self.wndSelectedListItem = nil
end

-- add an item into the item list
function OrionChallenges:AddItem(index, challenge)
	local wnd = Apollo.LoadForm(self.xmlDoc, "ListItem", self.wndItemList, self)
	self.tItems[index] = wnd
	wnd:SetData({index = index, challenge = challenge})
	self:HandleButtonControl(index)
	wnd:SetTooltip(challenge:GetDescription())
end

---------------------------------
-- Updates the distance display of an item
-- @param index The item index
-- @param challenge The currently selected item challenge
---------------------------------
function OrionChallenges:UpdateDistance(index, challenge)
	local wnd = self.tItems[index]
	if wnd then
		local wndDistance = wnd:FindChild("Distance")
		if challenge and challenge:GetMapLocation() ~= nil then
			local distance = self:GetChallengeDistance(challenge)
			wndDistance:SetText(math.floor(distance).."m")
			if self.tUserSettings.bAutostart and math.floor(distance) <= 5 and not challenge:IsActivated() then
				ChallengesLib.ActivateChallenge(challenge:GetId())
			end
		else
			-- challenge is underground
			wndDistance:SetText("?")
		end
		wndDistance:SetTextColor(kcrNormalText)
		
		local challenges = self.tChallenges
		if challenges[index+1] then
			local d1 = self:GetChallengeDistance(challenges[index+1])
			local d2 = self:GetChallengeDistance(challenge)
			if d1 and d2 and d1 < d2 then
				self:OnOrionChallengesOrderChanged()
			end
		end
	end
end

--[[
	return ( x1 & mask ) == mask
]]--
function OrionChallenges:HasFilter(nFilter)
	return bit.band(self.tUserSettings.nFilteredChallenges, nFilter) == nFilter
end

function OrionChallenges:SaveAnchorPosition()
	self.tUserSettings.tAnchor = {self.wndMain:GetAnchorOffsets()}
end

-----------------------------------------------------------------------------------------------
-- Settings Frame
-----------------------------------------------------------------------------------------------
function OrionChallenges:RepositionSettingsFrame()
	local nWidth, nHeight = self.wndSettings:GetWidth(), self.wndSettings:GetHeight()
	local nLeft, nTop, nRight, nBottom = self.wndMain:GetAnchorOffsets()
	local nsWidth, _ = Apollo.GetScreenSize()
	self:Debug(nLeft ..";" .. nWidth .. ";" .. nsWidth)
	if nLeft + nWidth > nsWidth - nWidth then
		self.wndSettings:SetAnchorOffsets(nLeft - nWidth, nTop + 10, nLeft, nTop + 10 + nHeight)
	else
		self.wndSettings:SetAnchorOffsets(nRight, nTop + 10, nRight + nWidth, nTop + 10 + nHeight)
	end
end

function OrionChallenges:OnSettingsToggle()
	-- set settings frame bounds
	self:RepositionSettingsFrame()
	self.wndSettings:Show(not self.wndSettings:IsShown())
	if self.wndSettings:IsShown() then
		self.wndSettings:ToFront()
	end
end

function OrionChallenges:OnSettingsClose()
	self.wndSettings:Show(false)
end

---------------------------------
-- Invoked when the user reloads his UI or logs out
-- @param eType the save level
-- @return Table of user settings
---------------------------------
function OrionChallenges:OnSave(eType)
	if eType ~= GameLib.CodeEnumAddonSaveLevel.Character then
    	return nil
  	end

	self:Debug("OnSave")
	return self.tUserSettings
end

---------------------------------
-- Invoked when the addon is loaded
-- @param eType the save level
-- @param tSavedData the saved data
---------------------------------
function OrionChallenges:OnRestore(eType, tSavedData)
	if eType ~= GameLib.CodeEnumAddonSaveLevel.Character then
    	return nil
  	end

	self:Debug("OnRestore")

	self.tUserSettings = tSavedData
	-- merge changes
	for k, v in pairs(tDefaultSettings) do
		if self.tUserSettings[k] == nil then			
			self.tUserSettings[k] = v
		end
	end
end

---------------------------------
-- Returns the control element from a given parent under the uppermost Content settings window
-- @param sParent the parent element name
-- @return the child control element
---------------------------------
function OrionChallenges:GetSettingControl(sParent)
	return self:FindChildByPath(self.wndSettings, "Content/"..sParent.."/Control")
end

---------------------------------
-- Updates and sets the settings form elements to its corresponding values
---------------------------------
function OrionChallenges:UpdateSettingControls()
	local wnd = self.wndSettings
	local wndMaxItems				= self:GetSettingControl("MaxItems")
	local wndAutostart				= self:GetSettingControl("Autostart")
	local wndHideOnChallenge		= self:GetSettingControl("HideWindowOnChallenge")
	local wndHideUnderground		= self:GetSettingControl("HideUndergroundChallenges")
	local wndLockPosition			= self:GetSettingControl("LockWindow")
	local wndAutoloot				= self:GetSettingControl("Autoloot")
	local wndIgnoredChallenges		= self:GetSettingControl("ShowIgnoredChallenges")
	local wndShowChallengesOnMap	= self:GetSettingControl("ShowChallengesOnMap")
	local wndHideCompleted			= self:GetSettingControl("HideCompletedChallenges")
	
	self:Debug("Updating settings.")
	wndMaxItems:SetText(self.tUserSettings.nMaxItems)
	wndAutostart:SetCheck(self.tUserSettings.bAutostart)
	wndHideOnChallenge:SetCheck(self.tUserSettings.bHideWindowOnChallenge)
	wndHideUnderground:SetCheck(self.tUserSettings.bHideUnderground)
	wndLockPosition:SetCheck(self.tUserSettings.bLockWindow)
	wndAutoloot:SetCheck(self.tUserSettings.bAutoloot)
	wndIgnoredChallenges:SetCheck(self.tUserSettings.bShowIgnoredChallenges)
	wndShowChallengesOnMap:SetCheck(self.tUserSettings.bShowChallengesOnMap)
	wndHideCompleted:SetCheck(self.tUserSettings.bHideCompletedChallenges)
	self:OnFilterToggle()
	self:LockUnlockWindow()
end

---------------------------------
-- Invoked when the user changes the max items setting
---------------------------------
function OrionChallenges:OnMaxItemsChanged()
	local val = self:GetSettingControl("MaxItems"):GetText()
	if not tonumber(val) or tonumber(val) < 1 then
		self:GetSettingControl("MaxItems"):SetText(self.tUserSettings.nMaxItems)
		return
	end
	
	self.tUserSettings.nMaxItems = tonumber(val)
	self:OnSettingChanged()
end

---------------------------------
-- Invoked when the user toggles the hide underground challenges setting
---------------------------------
function OrionChallenges:OnHideUndergroundChallengesToggle()
	self:Debug("OnHideUndergroundChallengesToggle")
	self.tUserSettings.bHideUnderground = self:GetSettingControl("HideUndergroundChallenges"):IsChecked()
	self:OnSettingChanged()
end

---------------------------------
-- Invoked when the user toggles the hide during challenge setting
---------------------------------
function OrionChallenges:OnHideWindowOnChallengeToggle()
	self:Debug("OnHideWindowOnChallengeToggle")
	self.tUserSettings.bHideWindowOnChallenge = self:GetSettingControl("HideWindowOnChallenge"):IsChecked()
	self:OnSettingChanged()
end

---------------------------------
-- Invoked when the user toggles the lock window position setting
---------------------------------
function OrionChallenges:OnLockWindowToggle()
	self:Debug("OnLockWindowToggle")
	self.tUserSettings.bLockWindow = self:GetSettingControl("LockWindow"):IsChecked()
	self:LockUnlockWindow()
	self:OnSettingChanged()
end

---------------------------------
-- Invoked when the user toggles the automatically show reward window setting
---------------------------------
function OrionChallenges:OnAutolootToggle()
	self:Debug("OnAutolootToggle")
	self.tUserSettings.bAutoloot = self:GetSettingControl("Autoloot"):IsChecked()
	self:OnSettingChanged()
end

---------------------------------
-- Invoked when the user toggles the autostart challenges setting
---------------------------------
function OrionChallenges:OnAutostartToggle()
	self:Debug("OnAutostartToggle")
	self.tUserSettings.bAutostart = self:GetSettingControl("Autostart"):IsChecked()
	self:OnSettingChanged()
end

---------------------------------
-- Invoked when the user toggles the show ignored challenges setting
---------------------------------
function OrionChallenges:OnShowIgnoredChallengesToggle()
	self:Debug("OnShowIgnoredChallengesToggle")
	self.tUserSettings.bShowIgnoredChallenges = self:GetSettingControl("ShowIgnoredChallenges"):IsChecked()
	self:OnSettingChanged()
end

---------------------------------
-- Invoked when the user toggles the show challenges on map setting
---------------------------------
function OrionChallenges:OnShowChallengesOnMapToggle()
	self:Debug("OnShowChallengesOnMapToggle")
	self.tUserSettings.bShowChallengesOnMap = self:GetSettingControl("ShowChallengesOnMap"):IsChecked()
	self:OnSettingChanged()
end

---------------------------------
-- Invoked when the user toggles the hide completed challenges setting
---------------------------------
function OrionChallenges:OnHideCompletedChallengesToggle()
	self:Debug("OnHideCompletedChallengesToggle")
	self.tUserSettings.bHideCompletedChallenges = self:GetSettingControl("HideCompletedChallenges"):IsChecked()
	self:OnSettingChanged()
end

---------------------------------
-- Returns the filter control with the given name
-- @param sFilter the filter name
-- @return the window control for the given name
---------------------------------
function OrionChallenges:GetFilterControl(sFilter)
	return self:FindChildByPath(self.wndSettings, "Content/Filter/Content/"..sFilter)
end

---------------------------------
-- Invoked when the user toggles any of the filter settings
---------------------------------
function OrionChallenges:OnFilterToggle()
	self:Debug("OnFilterToggle")
	local nNewMask = 0
	local tControls = { 
		{ control = self:GetFilterControl("FilterGeneral"),	mask = ktFilters.FILTER_GENERAL }, 
		{ control = self:GetFilterControl("FilterItem"),	mask = ktFilters.FILTER_ITEM }, 
		{ control = self:GetFilterControl("FilterAbility"),	mask = ktFilters.FILTER_ABILITY },
		{ control = self:GetFilterControl("FilterCombat"),	mask = ktFilters.FILTER_COMBAT }
	}
	
	for i=1, #tControls do
		local obj = tControls[i]
		if obj.control:IsChecked() then
			nNewMask = nNewMask + obj.mask
		end
	end
	
	self:Debug("New Mask: " .. nNewMask)
	
	self.tUserSettings.nFilteredChallenges = nNewMask
	self:OnSettingChanged()
end

---------------------------------
-- Invoked when any of the settings changed. Repopulates the main window.
---------------------------------
function OrionChallenges:OnSettingChanged()
	self:PopulateItemList()
end

---------------------------------
-- Locks or unlocks the main window
---------------------------------
function OrionChallenges:LockUnlockWindow()
	if self.tUserSettings.bLockWindow then
		self.wndMain:RemoveStyle("Moveable")
	else
		self.wndMain:AddStyle("Moveable")
	end
end

-----------------------------------------------------------------------------------------------
-- Extensions
-----------------------------------------------------------------------------------------------

---------------------------------
-- String splitting
-- @param str the string to split
-- @param pat the splitting pattern
-- @return table containing the splitted string parts
---------------------------------
function string.split(str, pat)
	local t = {}  -- NOTE: use {n = 0} in Lua-5.0
	local fpat = "(.-)" .. pat
	local last_end = 1
	local s, e, cap = str:find(fpat, 1)
	while s do
		if s ~= 1 or cap ~= "" then
			table.insert(t,cap)
		end
		last_end = e+1
		s, e, cap = str:find(fpat, last_end)
	end
	if last_end <= #str then
		cap = str:sub(last_end)
		table.insert(t, cap)
	end
	return t
end

---------------------------------
-- Tries to find a window child by a given XML-Like path
-- @param sPath the child window path
-- @param sSeparator The path separator, defaults to '/'
-- @return The found child window or nil
---------------------------------
function OrionChallenges:FindChildByPath(wndParent, sPath, sSeparator)
	sSeparator = sSeparator or "/"
	local tParts = sPath:split(sSeparator)
	local wndCurrent = wndParent
	for k, v in pairs(tParts) do
		local wnd = wndCurrent:FindChild(v)
		if wnd == nil then
			wndCurrent = nil
			break
		end
		
		wndCurrent = wnd
	end
	
	return wndCurrent
end

------------------------------------------------------------------------------------
-- OrionChallenges Instance
-----------------------------------------------------------------------------------------------
local OrionChallengesInst = OrionChallenges:new()
OrionChallengesInst:Init()

