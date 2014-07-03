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

local bDebug = true
local nVersion, nMinor = 0, 1
 
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
	o.playerUnit = GameLib.GetPlayerUnit()

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
		Apollo.RegisterSlashCommand("oc", "OnOrionChallengesOnShow", self)
		
		Apollo.RegisterEventHandler("SubZoneChanged", "OnSubZoneChanged", self)

		self.timerPos = ApolloTimer.Create(0.5, true, "TimerUpdateDistance", self)
		self.currentZoneId = GameLib.GetCurrentZoneId()

		-- Do additional Addon initialization here
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
function OrionChallenges:OnOrionChallengesOnShow()
	self.wndMain:Invoke() -- show the window
	self.timerPos:Start()
	-- populate the item list
	self:PopulateItemList()
end

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

function OrionChallenges:GetChallengeDistance(challenge)
	if challenge ~= nil and challenge:GetMapLocation() ~= nil then
		local target = challenge:GetMapLocation()
		local player = self.playerUnit:GetPosition()
		return Vector3.New(target.x - player.x, target.y - player.y, target.z - player.z):Length()
	end
	
	return 0
end

function OrionChallenges:HelperIsInZone(tZoneRestrictionInfo)
	return tZoneRestrictionInfo.idSubZone == 0 or GameLib.IsInWorldZone(tZoneRestrictionInfo.idSubZone)
end

function OrionChallenges:IsStartable(clgCurrent)
    return clgCurrent:GetCompletionCount() < clgCurrent:GetCompletionTotal() or clgCurrent:GetCompletionTotal() == -1
end


-----------------------------------------------------------------------------------------------
-- Hook Functions
-----------------------------------------------------------------------------------------------
function OrionChallenges:OnClose()
	self.wndMain:Show(false)
	self.timerPos:Stop()
end

function OrionChallenges:OnSubZoneChanged()
	self.currentZoneId = GameLib.GetCurrentZoneId()
	self.playerUnit = GameLib.GetPlayerUnit()

	self:PopulateItemList()
end

function OrionChallenges:TimerUpdateDistance()
	self.curPosition = self.playerUnit:GetPosition()
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

	if moving or self.lastZoneId ~= currentZoneId then
		self:PopulateItemList()
	end
	self.lastZoneId = self.currentZoneId
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

-----------------------------------------------------------------------------------------------
-- ItemList Functions
-----------------------------------------------------------------------------------------------
-- populate item list
function OrionChallenges:PopulateItemList()
	-- make sure the item list is empty to start with
	self:DestroyItemList()

	local challenges = self:GetChallengesByZoneSorted(self.currentZoneId)
	
	local max = #challenges < 10 and #challenges or 10
	for i = 1, max do
		self:AddItem(i, challenges[i])
	end
	
	-- now all the item are added, call ArrangeChildrenVert to list out the list items vertically
	self.wndItemList:ArrangeChildrenVert()
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
	local wndItemText = wnd:FindChild("Text")
	if wndItemText then -- make sure the text wnd exist
		local wndDistance = wnd:FindChild("Distance")
		local wndControl = wnd:FindChild("Control")
		local wndTimer = wnd:FindChild("Timer")
		local bEnable = not challenge:IsInCooldown() and self:IsStartable(challenge)
			and not challenge:IsActivated() and not challenge:ShouldCollectReward() 
			and self:HelperIsInZone(challenge:GetZoneRestrictionInfo())
			
		local sText = ""
		local sBGColor = "ff000000"
		local bEnableCtrl = true
		
		wndTimer:Show(false)
		if bEnable then
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
			wndTimer:SetText(c:GetTimeStr())
		else
			bEnableCtrl = false
		end
		
		wndControl:SetText(sText)
		wndControl:SetBGColor(sBGColor)
		wndControl:Show(bEnableCtrl)
		
		wndItemText:SetText(challenge:GetName())
		wndItemText:SetTextColor(kcrNormalText)
		
		self:UpdateDistance(wndDistance, challenge)
	end
	wnd:SetData({index = index, challenge = challenge})
end

function OrionChallenges:UpdateDistance(wndDistance, c)
	local distance = self:GetChallengeDistance(c)
	wndDistance:SetText(math.floor(distance).."m")
	wndDistance:SetTextColor(kcrNormalText)
end

-----------------------------------------------------------------------------------------------
-- OrionChallenges Instance
-----------------------------------------------------------------------------------------------
local OrionChallengesInst = OrionChallenges:new()
OrionChallengesInst:Init()
