-----------------------------------------------------------------------------------------------
-- Client Lua Script for OrionChallenges
-- Copyright (c) NCsoft. All rights reserved
-----------------------------------------------------------------------------------------------
 
require "Window"
require "ChallengesLib"
local bit = require "bit"
 
-----------------------------------------------------------------------------------------------
-- OrionChallenges Module Definition
-----------------------------------------------------------------------------------------------
local OrionChallenges = {}

-- Default OrionChallenges settings
local tDefaultSettings = {
	nMaxItems				= 10,		-- maximum number of displayed challenges
	nFilteredChallenges		= 0,		-- BITWISE representation of filtered challenges -> see ktFilters for filter masks
	bLockWindow				= false,	-- lock window position
	bAutostart				= false,	-- autostart challenges
	bAutoloot				= false,	-- autoloot challenges
	bHideWindowOnChallenge	= false,	-- hide frame when starting a challenge
	bHideUnderground		= false,	-- hide underground challenges, or else display it with "?" distance
	bShowIgnoredChallenges	= false		-- show ignored challenges, NYI
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

-- type filters
local ktFilters = {
	FILTER_GENERAL	= 1,
	FILTER_ITEM		= 2,
	FILTER_ABILITY	= 3,
	FILTER_COMBAT	= 4
}

-- Set this to true to enable debug outputs
local bDebug = true

-- Addon Version
local nVersion, nMinor, nTick = 0, 4, 4
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
        
		
		
		self.timerPos = ApolloTimer.Create(0.5, true, "TimerUpdateDistance", self)
		self.timerPos:Stop()
		self.currentZoneId = -1
		self.tCachedChallenges = {}
		self.tChallenges = {}
		self.populating = false
		self.bHiddenBySetting = false
		
		self.wndMain:FindChild("Header"):FindChild("Title"):SetText("OrionChallenges v"..nVersion.."."..nMinor.."."..nTick)
		self.wndMain:FindChild("Header"):FindChild("Title"):SetTooltip("Written by "..sAuthor)
		
		self.wndSettings = Apollo.LoadForm(self.xmlDoc, "Settings", nil, self)
		self.wndSettings:Show(false)
		
		if not self.tUserSettings then
			self.tUserSettings = tDefaultSettings
		end
		
		self:UpdateSettingControls()
		Debug("Initialized")
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
function Debug(str)
	if bDebug then
		Print("[OrionChallenges] " .. str)
	end
end

-- on SlashCommand "/oc"
function OrionChallenges:OnOrionChallengesToggle()
	if not self.wndMain:IsShown() then
		self:OnShow()
	else
		self:OnClose()
	end
end

-----------------------------------------------------------------------------------------------
-- Hook Functions
-----------------------------------------------------------------------------------------------

---------------------------------
-- Invoked when the main window is shown
---------------------------------
function OrionChallenges:OnShow()
	self.wndMain:Invoke()
	self:LockUnlockWindow()
	self.timerPos:Start()
	self:PopulateItemList(true)
	self:UpdateInterfaceMenuAlerts()
end

---------------------------------
-- Invoked when the main window is closed
---------------------------------
function OrionChallenges:OnClose()
	self.wndMain:Show(false)
	self.timerPos:Stop()
	self:UpdateInterfaceMenuAlerts()
	self:OnSettingsClose()
end

---------------------------------
-- Invoked when the player changes his subzone
---------------------------------
function OrionChallenges:OnSubZoneChanged()
	if self.currentZoneId ~= GameLib.GetCurrentZoneId() then
		Debug("Zone  changed. From " .. self.currentZoneId .. " to " .. GameLib.GetCurrentZoneId())
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
	self:UpdateInterfaceMenuAlerts()
end

function OrionChallenges:UpdateInterfaceMenuAlerts()
	Event_FireGenericEvent("InterfaceMenuList_AlertAddOn", "OrionChallenges", {self.isVisible, nil, 0})
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
    Event_FireGenericEvent("WindowManagementAdd", {wnd = self.wndMain, strName = "OrionChallenges"})
end


---------------------------------
-- Challenge Hooks
---------------------------------
function OrionChallenges:OnChallengeActivate()
	if self.tUserSettings.bHideWindowOnChallenge and self.wndMain:IsShown() then
		self.bHiddenBySetting = true
		self:OnClose()
	end
end

function OrionChallenges:ShowWindowAfterChallenge()
	if self.tUserSettings.bHideWindowOnChallenge and self.bHiddenBySetting then
		self.bHiddenBySetting = false
		self:OnShow()
	end
end

function OrionChallenges:OnChallengeAbadon()
	self:ShowWindowAfterChallenge()
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
		--local nChallengeType = challenge:GetType()
		if not (self.tUserSettings.bHideUnderground and self:GetChallengeDistance(challenge) == nil) 
			--[[and not ((nChallengeType == CHALLENGE_GENERAL and self:HasFilter(ktFilters.FILTER_GENERAL))
				or (nChallengeType == CHALLENGE_ITEM and self:HasFilter(ktFilters.FILTER_ITEM))
				or (nChallengeType == CHALLENGE_ABILITY and self:HasFilter(ktFilters.FILTER_ABILITY))
				or (nChallengeType == CHALLENGE_COMBAT and self:HasFilter(ktFilters.FILTER_COMBAT)) ]]--
		then
			table.insert(challenge, filteredChallenges)
		end
	end
	
	table.sort(filteredChallenges, function(challenge1, challenge2) 
		local dist1 = self:GetChallengeDistance(challenge1)
		local dist2 = self:GetChallengeDistance(challenge2)
		local sameDist = dist1 == dist2
		return sameDist and challenge1:GetName() > challenge2:GetName() or dist1 < dist2
	end)
	
	return filteredChallenges
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
		
		wndControl:SetText(sText)
		wndControl:SetBGColor(sBGColor)
		wndControl:Show(bEnableCtrl)
		
		wndItemText:SetText(challenge:GetName())
		wndItemText:SetTextColor(kcrNormalText)
		
		self:UpdateDistance(index, challenge)
	end
end
-----------------------------------------------------------------------------------------------
-- Helper functions
-- Taken from Carbine's ChallengeLog addon
-----------------------------------------------------------------------------------------------
function OrionChallenges:HelperIsInZone(tZoneRestrictionInfo)
	return tZoneRestrictionInfo.idSubZone == 0 or GameLib.IsInWorldZone(tZoneRestrictionInfo.idSubZone)
end

function OrionChallenges:IsStartable(clgCurrent)
    return clgCurrent:GetCompletionCount() < clgCurrent:GetCompletionTotal() or clgCurrent:GetCompletionTotal() == -1
end

-----------------------------------------------------------------------------------------------
-- ItemList Functions
-----------------------------------------------------------------------------------------------
-- populate item list
function OrionChallenges:PopulateItemList(bForce)
	if not self.populating or bForce then
		Debug("Populating.")
		self.populating = true
		-- make sure the item list is empty to start with
		self:DestroyItemList()
	
		local challenges = self:GetChallengesByZoneSorted()
		self.tChallenges = challenges		
		for i = 1, self:GetMaxChallenges() do
			self:AddItem(i, challenges[i])
		end
		
		-- now all the item are added, call ArrangeChildrenVert to list out the list items vertically
		self.wndItemList:ArrangeChildrenVert()
		self:ResizeHeight()
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
			if self.tUserSettings.bAutostart and math.floor(distance) == 0 then
				ChallengesLib.ActivateChallenge(challenge:GetId())
			end
		else
			-- challenge is underground
			wndDistance:SetText("?")
		end
		wndDistance:SetTextColor(kcrNormalText)
		
		local challenges = self.tChallenges
		if challenges[index+1] and self:GetChallengeDistance(challenges[index+1]) < self:GetChallengeDistance(challenge) then
			self:OnOrionChallengesOrderChanged()
		end
	end
end

--[[
	return ( x1 & mask ) == mask
]]--
function OrionChallenges:HasFilter(nFilter)
	return bit.band(self.tUserSettings.nFilteredChallenges, nFilter) == nFilter
end

-----------------------------------------------------------------------------------------------
-- Settings Frame
-----------------------------------------------------------------------------------------------
function OrionChallenges:RepositionSettingsFrame()
	local nWidth, nHeight = 400, 200
	local nLeft, nTop, nRight, nBottom = self.wndMain:GetAnchorOffsets()
	self.wndSettings:SetAnchorOffsets(nRight, nTop + 10, nRight + nWidth, nTop + 10 + nHeight)
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

	Debug("OnSave")

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

	Debug("OnRestore")

	self.tUserSettings = tSavedData
	-- merge changes
	for k, v in pairs(tDefaultSettings) do
		if not self.tUserSettings[k] then
			self.tUserSettings[k] = v
		end
	end
end

function OrionChallenges:GetSettingControl(sParent)
	return self.wndSettings:FindChild("Content"):FindChild(sParent):FindChild("Control")
end

function OrionChallenges:UpdateSettingControls()
	local wnd = self.wndSettings
	local wndMaxItems			= self:GetSettingControl("MaxItems")
	local wndAutostart			= self:GetSettingControl("Autostart")
	local wndHideOnChallenge	= self:GetSettingControl("HideWindowOnChallenge")
	local wndHideUnderground	= self:GetSettingControl("HideUndergroundChallenges")
	local wndLockPosition		= self:GetSettingControl("LockWindow")
	local wndAutoloot			= self:GetSettingControl("Autoloot")
	
	Debug("Updating settings.")
	wndMaxItems:SetText(self.tUserSettings.nMaxItems)
	wndAutostart:SetCheck(self.tUserSettings.bAutostart)
	wndHideOnChallenge:SetCheck(self.tUserSettings.bHideWindowOnChallenge)
	wndHideUnderground:SetCheck(self.tUserSettings.bHideUnderground)
	wndLockPosition:SetCheck(self.tUserSettings.bLockWindow)
	wndAutoloot:SetCheck(self.tUserSettings.bAutoloot)
	self:LockUnlockWindow()
end

function OrionChallenges:OnMaxItemsChanged()
	local val = self:GetSettingControl("MaxItems"):GetText()
	if not tonumber(val) or tonumber(val) < 1 then
		self:GetSettingControl("MaxItems"):SetText(self.tUserSettings.nMaxItems)
		return
	end
	
	self.tUserSettings.nMaxItems = tonumber(val)
	self:OnSettingChanged()
end

function OrionChallenges:OnHideUndergroundChallengesToggle()
	Debug("OnHideUndergroundChallengesToggle")
	self.tUserSettings.bHideUnderground = self:GetSettingControl("HideUndergroundChallenges"):IsChecked()
	self:OnSettingChanged()
end

function OrionChallenges:OnHideWindowOnChallengeToggle()
	Debug("OnHideWindowOnChallengeToggle")
	self.tUserSettings.bHideWindowOnChallenge = self:GetSettingControl("HideWindowOnChallenge"):IsChecked()
	self:OnSettingChanged()
end

function OrionChallenges:OnLockWindowToggle()
	Debug("OnLockWindowToggle")
	self.tUserSettings.bLockWindow = self:GetSettingControl("LockWindow"):IsChecked()
	self:LockUnlockWindow()
	self:OnSettingChanged()
end

function OrionChallenges:OnAutolootToggle()
	Debug("OnAutolootToggle")
	self.tUserSettings.bAutoloot = self:GetSettingControl("Autoloot"):IsChecked()
	self:OnSettingChanged()
end

function OrionChallenges:OnFilterToggle()
	Debug("OnFilterToggle")
	local nNewMask = 0
	local tControls = { 
		{ control = self:GetSettingControl("FilterGeneral"),	mask = ktFilters.FILTER_GENERAL }, 
		{ control = self:GetSettingControl("FilterItem"),		mask = ktFilters.FILTER_ITEM }, 
		{ control = self:GetSettingControl("FilterAbility"),	mask = ktFilters.FILTER_ABILITY },
		{ control = self:GetSettingControl("FilterCombat"),		mask = ktFilters.FILTER_COMBAT }
	}
	
	for i=1, #tControls do
		local obj = tControls[i]
		if obj.control:IsChecked() then
			nNewMask = nNewMask + obj.mask
		end
	end
	
	self.tUserSettings.nFilteredChallenges = nNewMask
	self:OnSettingChanged()
end

function OrionChallenges:OnSettingChanged()
	self:PopulateItemList()
end

function OrionChallenges:LockUnlockWindow()
	if self.tUserSettings.bLockWindow then
		self.wndMain:RemoveStyle("Moveable")
	else
		self.wndMain:AddStyle("Moveable")
	end
end

-----------------------------------------------------------------------------------------------
-- OrionChallenges Instance
-----------------------------------------------------------------------------------------------
local OrionChallengesInst = OrionChallenges:new()
OrionChallengesInst:Init()
