-----------------------------------------------------------------------------------------------
-- Client Lua Script for OrionChallenges
-- Copyright (c) NCsoft. All rights reserved
-----------------------------------------------------------------------------------------------
 
require "Window"
require "ChallengesLib"
 
-----------------------------------------------------------------------------------------------
-- OrionChallenges Module Definition
-----------------------------------------------------------------------------------------------
local OrionChallenges = {}
 
-----------------------------------------------------------------------------------------------
-- Constants
-----------------------------------------------------------------------------------------------
-- e.g. local kiExampleVariableMax = 999
local kcrSelectedText = ApolloColor.new("UI_BtnTextHoloPressedFlyby")
local kcrNormalText = ApolloColor.new("UI_BtnTextHoloNormal")

local kStateOutOfRange		= -1
local kStateStartable 		= 1
local kStateLootable 		= 2
local kStateActivated 		= 3
local kStateOnCooldown 		= 4

local bDebug = false
local nVersion, nMinor = 0, 3
local sAuthor = "Troxito@EU-Progenitor"
 
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
	o.cachedChallenges = {}

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
		
		Apollo.RegisterEventHandler("SubZoneChanged",				"OnSubZoneChanged", 				self)
		Apollo.RegisterEventHandler("ChallengeUnlocked",			"OnChallengeUnlocked", 				self)
		Apollo.RegisterEventHandler("InterfaceMenuListHasLoaded",	"OnInterfaceMenuListHasLoaded", 	self)
		Apollo.RegisterEventHandler("OrionChallengesToggle",		"OnOrionChallengesToggle", 			self)
		Apollo.RegisterEventHandler("OrionChallengesOrderChanged",	"OnOrionChallengesOrderChanged", 	self)
		Apollo.RegisterEventHandler("WindowManagementReady",		"OnWindowManagementReady", 			self)
		
		
		self.timerPos = ApolloTimer.Create(0.5, true, "TimerUpdateDistance", self)
		self.currentZoneId = GameLib.GetCurrentZoneId()
		self.isVisible = false
		self.tChallenges = self:GetChallengesByZoneSorted()
		self.populating = false
	end
end

-----------------------------------------------------------------------------------------------
-- OrionChallenges Functions
-----------------------------------------------------------------------------------------------
-- Define general functions here

function Debug(str)
	if bDebug then
		Print(str)
	end
end

-- on SlashCommand "/oc"
function OrionChallenges:OnOrionChallengesToggle()
	if not self.isVisible then
		self:OnShow()
	else
		self:OnClose()
	end
end

-----------------------------------------------------------------------------------------------
-- Hook Functions
-----------------------------------------------------------------------------------------------
function OrionChallenges:OnShow()
	self.wndMain:Invoke()
	self.timerPos:Start()
	self:PopulateItemList()
	self.isVisible = true
	self:UpdateInterfaceMenuAlerts()
end

function OrionChallenges:OnClose()
	self.wndMain:Show(false)
	self.timerPos:Stop()
	self.isVisible = false
	self:UpdateInterfaceMenuAlerts()
end

function OrionChallenges:OnSubZoneChanged()
	self.currentZoneId = GameLib.GetCurrentZoneId()
	self:PopulateItemList()
end

function OrionChallenges:OnChallengeUnlocked()
	local zoneId = GameLib.GetCurrentZoneId()
	if zoneId ~= nil and self.cachedChallenges[zoneId] ~= nil then
		self.cachedChallenges[zoneId] = nil
	elseif zoneId == -1 then
		self.cachedChallenges = {}
	end
end

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
	
		if moving then
			for i=1, #self.tItems do
				self:UpdateDistance(i)
				self:HandleButtonControl(i)
			end
		end
		
		self.lastZoneId = self.currentZoneId
		self.tChallenges = self:GetChallengesByZoneSorted()
	end
end

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

	end
end

function OrionChallenges:OnInterfaceMenuListHasLoaded()
	Event_FireGenericEvent("InterfaceMenuList_NewAddOn", "OrionChallenges", {"OrionChallengesToggle", "", "Icon_Windows32_UI_CRB_InterfaceMenu_ChallengeLog"})
	self:UpdateInterfaceMenuAlerts()
end

function OrionChallenges:UpdateInterfaceMenuAlerts()
	Event_FireGenericEvent("InterfaceMenuList_AlertAddOn", "OrionChallenges", {self.isVisible, nil, 0})
end

function OrionChallenges:OnOrionChallengesOrderChanged()
	self:PopulateItemList()
end

function OrionChallenges:OnWindowManagementReady()
    Event_FireGenericEvent("WindowManagementAdd", {wnd = self.wndMain, strName = "OrionChallenges"})
end

-----------------------------------------------------------------------------------------------
-- General Functions
-----------------------------------------------------------------------------------------------
function OrionChallenges:GetChallengesByZone(zoneId)
	zoneId = zoneId and zoneId or GameLib.GetCurrentZoneId()

	if self.cachedChallenges[zoneId] ~= nil then
		return self.cachedChallenges[zoneId]
	end

	local returnValue = {}
	
	for i, challenge in pairs(ChallengesLib.GetActiveChallengeList()) do
		if GameLib.IsZoneInZone(zoneId, challenge:GetZoneInfo().idZone) then
			table.insert(returnValue, challenge)
		end
	end
	
	table.insert(self.cachedChallenges, zoneId, returnValue)
	
	return returnValue
end

function OrionChallenges:GetChallengesByZoneSorted(zoneId)
	local challenges = self:GetChallengesByZone(zoneId)
	table.sort(challenges, function(challenge1, challenge2) 
		local dist1 = self:GetChallengeDistance(challenge1)
		local dist2 = self:GetChallengeDistance(challenge2)
		local sameDist = dist1 == dist2
		return sameDist and challenge1:GetName() > challenge2:GetName() or dist1 < dist2
	end)
	
	return challenges
end

function OrionChallenges:GetChallengeDistance(challenge)
	if challenge ~= nil and challenge:GetMapLocation() ~= nil then
		local target = challenge:GetMapLocation()
		if GameLib.GetPlayerUnit() then
			local player = GameLib.GetPlayerUnit():GetPosition()
			return Vector3.New(target.x - player.x, target.y - player.y, target.z - player.z):Length()
		end
	end
	
	return 0
end

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
			sText = "Cancel"
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
-----------------------------------------------------------------------------------------------
function OrionChallenges:HelperIsInZone(tZoneRestrictionInfo)
	return tZoneRestrictionInfo.idSubZone == 0 or GameLib.IsInWorldZone(tZoneRestrictionInfo.idSubZone)
end

function OrionChallenges:IsStartable(clgCurrent)
    return clgCurrent:GetCompletionCount() < clgCurrent:GetCompletionTotal() or clgCurrent:GetCompletionTotal() == -1
end

function OrionChallenges:IsSameChallengeOrder()
	local tCurrChallenges = self:GetChallengesByZoneSorted()
	local tOldChallenges = self.tChallenges
	if #tCurrChallenges == #tOldChallenges then
		for i=1, #tCurrChallenges do
			local challenge1 = tCurrChallenges[i]
			local challenge2 = tOldChallenges[i]
			if challenge1:GetId() ~= challenge2:GetId() then
				return false
			end
		end
	else
		return false
	end
	
	return true
end

-----------------------------------------------------------------------------------------------
-- ItemList Functions
-----------------------------------------------------------------------------------------------
-- populate item list
function OrionChallenges:PopulateItemList()
	if not self.populating then
		self.populating = true
		-- make sure the item list is empty to start with
		self:DestroyItemList()
	
		local challenges = self:GetChallengesByZoneSorted(self.currentZoneId)
		
		local max = #challenges < 10 and #challenges or 10
		for i = 1, max do
			self:AddItem(i, challenges[i])
		end
		
		-- now all the item are added, call ArrangeChildrenVert to list out the list items vertically
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

function OrionChallenges:UpdateDistance(index, challenge)
	local wnd = self.tItems[index]
	local wndDistance = wnd:FindChild("Distance")
	local distance = self:GetChallengeDistance(challenge)
	wndDistance:SetText(math.floor(distance).."m")
	wndDistance:SetTextColor(kcrNormalText)
	
	local challenges = self:GetChallengesByZoneSorted()
	if challenges[index] and wnd:GetData() and wnd:GetData().challenge and wnd:GetData().challenge:GetId() ~= challenges[index]:GetId() then
		self:OnOrionChallengesOrderChanged()
	end
end

-----------------------------------------------------------------------------------------------
-- OrionChallenges Instance
-----------------------------------------------------------------------------------------------
local OrionChallengesInst = OrionChallenges:new()
OrionChallengesInst:Init()
