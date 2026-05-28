-------------------------------------------------------------------------------
-- Project: AscensionProfessionHelper
-- Author: Aka-DoctorCode
-- File: AscensionProfessionHelper.lua
-------------------------------------------------------------------------------
---@diagnostic disable: undefined-global, undefined-field, inject-field

local addonName, Ascension = ...
Ascension.crafting = { queue = {}, currentTargetItem = nil }
Ascension.inventory = {}
Ascension.isDebugEnabled = false

function Ascension.log(message)
    if Ascension.isDebugEnabled then
        print("|cff00ff00[" .. addonName .. "]|r " .. tostring(message))
    end
end

-------------------------------------------------------------------------------
-- UI AND LOGIC
-------------------------------------------------------------------------------
local massDestroyButton = CreateFrame("Button", "AscensionMassDestroyBtn", UIParent, "SecureActionButtonTemplate, BackdropTemplate")
massDestroyButton:RegisterForClicks("AnyUp", "AnyDown")
massDestroyButton:SetSize(150, 40)
massDestroyButton:SetAttribute("*type1", "macro")
massDestroyButton:Hide()

local categoryPanels = {}
local itemFrames = {}
local blFrames = {}
local searchFilter = ""

function Ascension.crafting.updateBlacklistUI()
    local activePanel = categoryPanels[4]
    if not activePanel then return end

    for _, f in ipairs(blFrames) do f:Hide() end
    local y = -45
    local i = 1
    for id, _ in pairs(AscensionDB.blacklist or {}) do
        local name, link = C_Item.GetItemInfo(id)
        local itemName = name or ("Item " .. id)
        
        if searchFilter == "" or string.find(string.lower(itemName), string.lower(searchFilter)) then
            local f = blFrames[i]
            if not f then
                f = CreateFrame("Button", nil, activePanel, "BackdropTemplate")
                f:SetHeight(40)
                f:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8" })
                f:SetBackdropColor(0, 0, 0, 0.3)
                f:SetScript("OnEnter", function() f:SetBackdropColor(0.2, 0.2, 0.2, 0.8) end)
                f:SetScript("OnLeave", function() f:SetBackdropColor(0, 0, 0, 0.3) end)
                
                local text = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
                text:SetPoint("LEFT", 10, 0)
                text:SetJustifyH("LEFT")
                text:SetWordWrap(false)
                f.text = text

                local ilvlText = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
                ilvlText:SetPoint("RIGHT", -10, 0)
                ilvlText:SetJustifyH("RIGHT")
                ilvlText:SetTextColor(0.7, 0.7, 0.7)
                f.ilvlText = ilvlText
                
                text:SetPoint("RIGHT", ilvlText, "LEFT", -10, 0)

                f:RegisterForClicks("RightButtonUp")
                f:SetScript("OnClick", function(self, button)
                    if button == "RightButton" then
                        local lib = LibStub("AscensionSuit-UI", true)
                        if lib and lib.UX and lib.UX.showContextMenu then
                            lib.UX:showContextMenu(self, {
                                {
                                    text = "Remove from Blacklist",
                                    func = function()
                                        AscensionDB.blacklist[f.itemId] = nil
                                        Ascension.log("Removed from blacklist.")
                                        Ascension.crafting.updateBlacklistUI()
                                        Ascension.crafting.updateDestroyQueue()
                                    end
                                }
                            })
                        end
                    end
                end)
                table.insert(blFrames, f)
            end
            
            f.itemId = id
            local name, link, quality, ilvl = C_Item.GetItemInfo(id)
            local icon = C_Item.GetItemIconByID(id)
            local iconStr = icon and ("|T" .. icon .. ":30:30|t ") or ""
            f.text:SetText(iconStr .. (link or itemName))
            f.ilvlText:SetText(ilvl and ("iLvl " .. ilvl) or "")
            f:ClearAllPoints()
            f:SetPoint("TOPLEFT", 10, y)
            f:SetPoint("RIGHT", activePanel, "RIGHT", -10, y)
            f:Show()
            y = y - 45
            i = i + 1
        end
    end
    activePanel:SetHeight(math.abs(y) + 20)
end

function Ascension.crafting.isItemDestroyable(itemId)
    if AscensionDB and AscensionDB.blacklist and AscensionDB.blacklist[itemId] then
        return false, nil
    end

    local tooltipData = C_TooltipInfo.GetItemByID(itemId)
    if tooltipData then
        for _, line in ipairs(tooltipData.lines) do
            if line.leftText == "Prospectable" then return true, "Prospecting" end
            if line.leftText == "Millable" then return true, "Milling" end
        end
    end
    
    local itemQuality = select(3, C_Item.GetItemInfo(itemId))
    local classId = select(12, C_Item.GetItemInfo(itemId))
    if (classId == 2 or classId == 4) and itemQuality and itemQuality >= 2 and itemQuality <= 4 then
        return true, "Disenchant"
    end

    return false, nil
end

function Ascension.crafting.updateDestroyQueue()
    if InCombatLockdown() then return end
    
    local activeTab = 1
    if _G.AscensionProfHelperUI and _G.AscensionProfHelperUI.tabbedUI then
        activeTab = _G.AscensionProfHelperUI.tabbedUI:getActiveTab()
    end

    local tabCategoryMap = {
        [1] = "Disenchant",
        [2] = "Milling",
        [3] = "Prospecting"
    }
    
    local targetCategory = tabCategoryMap[activeTab]
    if not targetCategory then
        Ascension.crafting.currentTargetItem = nil
        massDestroyButton:SetAttribute("macrotext", "")
        massDestroyButton:SetAttribute("macrotext1", "")
        massDestroyButton:SetAttribute("*macrotext1", "")
        massDestroyButton:SetAttribute("macrotext-down", "")
        massDestroyButton:SetAttribute("macrotext1-down", "")
        massDestroyButton:SetAttribute("*macrotext1-down", "")
        massDestroyButton:Hide()
        return
    end

    local foundItems = {}
    local orderedLinks = {}
    local targetBag, targetSlot, targetSpell, targetItem = nil, nil, nil, nil
    
    for bagIndex = 0, 4 do
        for slotIndex = 1, C_Container.GetContainerNumSlots(bagIndex) do
            local itemInfo = C_Container.GetContainerItemInfo(bagIndex, slotIndex)
            if itemInfo and itemInfo.itemID and not itemInfo.isLocked then
                local isDestroyable, spellName = Ascension.crafting.isItemDestroyable(itemInfo.itemID)
                if isDestroyable and spellName == targetCategory then
                    local link = itemInfo.hyperlink
                    if link then
                        if not foundItems[link] then
                            foundItems[link] = { count = 0, itemId = itemInfo.itemID }
                            table.insert(orderedLinks, link)
                        end
                        foundItems[link].count = foundItems[link].count + 1
                        
                        if not targetBag then
                            targetBag = bagIndex
                            targetSlot = slotIndex
                            targetSpell = spellName
                            targetItem = itemInfo.itemID
                        end
                    end
                end
            end
        end
    end
    
    local activePanel = categoryPanels[activeTab]
    if activePanel then
        for _, f in ipairs(itemFrames) do f:Hide() end
        local y = -5
        local i = 1
        for _, link in ipairs(orderedLinks) do
            local data = foundItems[link]
            local count = data.count
            local id = data.itemId
            local f = itemFrames[i]
            if not f then
                f = CreateFrame("Button", nil, activePanel, "BackdropTemplate")
                f:SetHeight(40)
                f:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8" })
                f:SetBackdropColor(0, 0, 0, 0.3)
                f:SetScript("OnEnter", function() f:SetBackdropColor(0.2, 0.2, 0.2, 0.8) end)
                f:SetScript("OnLeave", function() f:SetBackdropColor(0, 0, 0, 0.3) end)
                
                local text = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
                text:SetPoint("LEFT", 10, 0)
                text:SetJustifyH("LEFT")
                text:SetWordWrap(false)
                f.text = text

                local ilvlText = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
                ilvlText:SetPoint("RIGHT", -10, 0)
                ilvlText:SetJustifyH("RIGHT")
                ilvlText:SetTextColor(0.7, 0.7, 0.7)
                f.ilvlText = ilvlText
                
                text:SetPoint("RIGHT", ilvlText, "LEFT", -10, 0)

                f:RegisterForClicks("RightButtonUp")
                f:SetScript("OnClick", function(self, button)
                    if button == "RightButton" then
                        local lib = LibStub("AscensionSuit-UI", true)
                        if lib and lib.UX and lib.UX.showContextMenu then
                            lib.UX:showContextMenu(self, {
                                {
                                    text = "Blacklist Item",
                                    func = function()
                                        AscensionDB.blacklist[f.itemId] = true
                                        Ascension.log("Blacklisted item " .. f.itemId)
                                        Ascension.crafting.updateDestroyQueue()
                                    end
                                }
                            })
                        end
                    end
                end)
                table.insert(itemFrames, f)
            end
            
            f:SetParent(activePanel)
            f.itemId = id
            local detailedILvl = C_Item.GetDetailedItemLevelInfo(link)
            local icon = C_Item.GetItemIconByID(id)
            local iconStr = icon and ("|T" .. icon .. ":30:30|t ") or ""
            f.text:SetText(count .. "x " .. iconStr .. link)
            f.ilvlText:SetText(detailedILvl and ("iLvl " .. detailedILvl) or "")
            f:ClearAllPoints()
            f:SetPoint("TOPLEFT", 10, y)
            f:SetPoint("RIGHT", activePanel, "RIGHT", -10, y)
            f:Show()
            y = y - 45
            i = i + 1
        end
        activePanel:SetHeight(math.abs(y) + 60)
    end

    if targetBag and targetSlot and targetSpell and targetCategory then
        Ascension.crafting.currentTargetItem = targetItem
        
        local castSpellName = targetSpell
        if targetSpell == "Disenchant" then
            local info = C_Spell and C_Spell.GetSpellInfo and C_Spell.GetSpellInfo(13262)
            castSpellName = info and info.name or (GetSpellInfo and GetSpellInfo(13262)) or "Disenchant"
        elseif targetSpell == "Milling" then
            local info = C_Spell and C_Spell.GetSpellInfo and C_Spell.GetSpellInfo(51005)
            castSpellName = info and info.name or (GetSpellInfo and GetSpellInfo(51005)) or "Milling"
        elseif targetSpell == "Prospecting" then
            local info = C_Spell and C_Spell.GetSpellInfo and C_Spell.GetSpellInfo(31252)
            castSpellName = info and info.name or (GetSpellInfo and GetSpellInfo(31252)) or "Prospecting"
        end
        
        massDestroyButton:SetAttribute("type", "macro")
        massDestroyButton:SetAttribute("type1", "macro")
        massDestroyButton:SetAttribute("*type1", "macro")
        massDestroyButton:SetAttribute("type-down", "macro")
        massDestroyButton:SetAttribute("type1-down", "macro")
        massDestroyButton:SetAttribute("*type1-down", "macro")
        
        local text = "/cast " .. castSpellName .. "\n/use " .. targetBag .. " " .. targetSlot
        massDestroyButton:SetAttribute("macrotext", text)
        massDestroyButton:SetAttribute("macrotext1", text)
        massDestroyButton:SetAttribute("*macrotext1", text)
        massDestroyButton:SetAttribute("macrotext-down", text)
        massDestroyButton:SetAttribute("macrotext1-down", text)
        massDestroyButton:SetAttribute("*macrotext1-down", text)
        
        massDestroyButton:Show()
    else
        Ascension.crafting.currentTargetItem = nil
        massDestroyButton:SetAttribute("macrotext", "")
        massDestroyButton:SetAttribute("macrotext1", "")
        massDestroyButton:SetAttribute("*macrotext1", "")
        massDestroyButton:SetAttribute("macrotext-down", "")
        massDestroyButton:SetAttribute("macrotext1-down", "")
        massDestroyButton:SetAttribute("*macrotext1-down", "")
        massDestroyButton:Hide()
    end
end

local bagEventFrame = CreateFrame("Frame")
bagEventFrame:RegisterEvent("BAG_UPDATE_DELAYED")
bagEventFrame:RegisterEvent("BAG_UPDATE")
bagEventFrame:SetScript("OnEvent", function()
    Ascension.crafting.updateDestroyQueue()
end)

local errorEventFrame = CreateFrame("Frame")
errorEventFrame:RegisterEvent("UI_ERROR_MESSAGE")
errorEventFrame:SetScript("OnEvent", function(self, event, errorType, message)
    if message == ERR_NOT_DISENCHANTABLE then
        if Ascension.crafting.currentTargetItem then
            AscensionDB.blacklist[Ascension.crafting.currentTargetItem] = true
            Ascension.log("Auto-blacklisted: " .. Ascension.crafting.currentTargetItem)
            Ascension.crafting.updateDestroyQueue()
            if UIErrorsFrame then UIErrorsFrame:Clear() end
        end
    end
end)

local LibStub = _G.LibStub

local function createUI()
    local lib = LibStub and LibStub:GetLibrary("AscensionSuit-UI", true)
    if not lib then return end

    local ctx = lib:CreateContext()

    local buildFuncs = {
        function(panel) categoryPanels[1] = panel.content end, -- Disenchant
        function(panel) categoryPanels[2] = panel.content end, -- Milling
        function(panel) categoryPanels[3] = panel.content end, -- Prospecting
        function(panel)
            categoryPanels[4] = panel.content
            
            local searchBox = CreateFrame("EditBox", nil, panel.content, "InputBoxTemplate")
            searchBox:SetSize(200, 30)
            searchBox:SetPoint("TOPLEFT", 10, -10)
            searchBox:SetAutoFocus(false)
            searchBox:SetScript("OnTextChanged", function(self)
                searchFilter = self:GetText()
                Ascension.crafting.updateBlacklistUI()
            end)
            
            local label = searchBox:CreateFontString(nil, "OVERLAY", "GameFontNormal")
            label:SetPoint("BOTTOMLEFT", searchBox, "TOPLEFT", 0, 2)
            label:SetText("Search Blacklist:")
            
            Ascension.crafting.updateBlacklistUI()
        end,
        function(panel)
            categoryPanels[5] = panel.content
            
            local title = panel.content:CreateFontString(nil, "OVERLAY", "GameFontHighlightLarge")
            title:SetPoint("TOPLEFT", 10, -10)
            title:SetText("Options & Macro")
            
            local desc1 = panel.content:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
            desc1:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -10)
            desc1:SetPoint("RIGHT", panel.content, "RIGHT", -20, 0)
            desc1:SetJustifyH("LEFT")
            desc1:SetWordWrap(true)
            desc1:SetText("Blizzard's interface does not permit automatic casting. You must click manually.")

            local desc2 = panel.content:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
            desc2:SetPoint("TOPLEFT", desc1, "BOTTOMLEFT", 0, -10)
            desc2:SetPoint("RIGHT", panel.content, "RIGHT", -20, 0)
            desc2:SetJustifyH("LEFT")
            desc2:SetWordWrap(true)
            desc2:SetText("However, you can bind the button to your mouse wheel to speed it up!")
            
            local desc3 = panel.content:CreateFontString(nil, "OVERLAY", "GameFontHighlightLarge")
            desc3:SetPoint("TOPLEFT", desc2, "BOTTOMLEFT", 0, -15)
            desc3:SetPoint("RIGHT", panel.content, "RIGHT", -20, 0)
            desc3:SetJustifyH("LEFT")
            desc3:SetWordWrap(true)
            desc3:SetText("Select your preferred modifier and direction below, then click Apply Bind.")
            
            local modDrop = ctx:createDropdown({
                parent = panel.content,
                text = "Modifier",
                options = {
                    { label = "SHIFT", value = "SHIFT" },
                    { label = "CTRL", value = "CTRL" },
                    { label = "ALT", value = "ALT" },
                    { label = "CMD", value = "META" },
                },
                getter = function() return AscensionDB.macroMod or "SHIFT" end,
                setter = function(val) AscensionDB.macroMod = val end,
                width = 220
            })
            modDrop:ClearAllPoints()
            modDrop:SetPoint("TOPLEFT", desc3, "BOTTOMLEFT", 10, -20)
            
            local dirDrop = ctx:createDropdown({
                parent = panel.content,
                text = "Direction",
                options = {
                    { label = "UP", value = "MOUSEWHEELUP" },
                    { label = "DOWN", value = "MOUSEWHEELDOWN" },
                },
                getter = function() return AscensionDB.macroDir or "MOUSEWHEELUP" end,
                setter = function(val) AscensionDB.macroDir = val end,
                width = 220
            })
            dirDrop:ClearAllPoints()
            dirDrop:SetPoint("TOPLEFT", modDrop, "BOTTOMLEFT", 0, -10)
            
            local bindBtn = ctx:createButton({
                parent = panel.content,
                text = "Apply Bind",
                width = 220,
                height = 40,
                onClick = function()
                    if not InCombatLockdown() then
                        if AscensionDB.lastBind then
                            SetBinding(AscensionDB.lastBind, nil)
                        end
                        
                        local bindStr = (AscensionDB.macroMod or "SHIFT") .. "-" .. (AscensionDB.macroDir or "MOUSEWHEELUP")
                        local bindingMode = (GetCurrentBindingSet() == 2) and 1 or 2
                        
                        SetBinding(bindStr, nil, bindingMode)
                        SetBindingClick(bindStr, "AscensionMassDestroyBtn", "LeftButton")
                        SaveBindings(GetCurrentBindingSet())
                        
                        AscensionDB.lastBind = bindStr
                        Ascension.log("Bound " .. bindStr .. " directly to Destroy Button!")
                    end
                end
            })
            bindBtn:ClearAllPoints()
            bindBtn:SetPoint("TOPLEFT", dirDrop, "BOTTOMLEFT", 0, -20)
            
            local unbindBtn = ctx:createButton({
                parent = panel.content,
                text = "Remove Bind",
                width = 220,
                height = 40,
                onClick = function()
                    if not InCombatLockdown() then
                        if AscensionDB.lastBind then
                            SetBinding(AscensionDB.lastBind, nil)
                            SaveBindings(GetCurrentBindingSet())
                            Ascension.log("Removed bind: " .. AscensionDB.lastBind)
                            AscensionDB.lastBind = nil
                        end
                    end
                end
            })
            unbindBtn:ClearAllPoints()
            unbindBtn:SetPoint("TOPLEFT", bindBtn, "BOTTOMLEFT", 0, -10)
        end
    }

    local mainFrame = ctx:createMainFrame({
        name     = "AscensionProfessionHelperFrame",
        title    = "Ascension Profession Helper",
        tabNames = { "Disenchant", "Milling", "Prospecting", "Blacklist", "Options" },
        tabFuncs = buildFuncs,
        width    = 450,
        height   = 400
    })

    if mainFrame.frame and mainFrame.frame.SetResizeBounds then
        mainFrame.frame:SetResizeBounds(400, 300, 2000, 2000)
    end

    _G.AscensionProfHelperUI = mainFrame

    if mainFrame.tabbedUI then
        -- Adjust panels so they don't overlap the bottom button
        for i, panel in ipairs(mainFrame.tabbedUI.panels) do
            panel:SetPoint("BOTTOMRIGHT", -10, 70)
            panel:HookScript("OnShow", function()
                if i == 4 then
                    Ascension.crafting.updateBlacklistUI()
                    if _G.AscensionMassDestroyBtn then _G.AscensionMassDestroyBtn:Hide() end
                elseif i == 5 then
                    if _G.AscensionMassDestroyBtn then _G.AscensionMassDestroyBtn:Hide() end
                else
                    Ascension.crafting.updateDestroyQueue()
                end
            end)
        end
    end

    -- Style secure button like AscensionSuit
    local styles = ctx.styles
    massDestroyButton:SetBackdrop({
        bgFile = styles.files.bgFile,
        edgeFile = styles.files.edgeFile,
        edgeSize = 1,
        insets = { left = 1, right = 1, top = 1, bottom = 1 }
    })
    massDestroyButton:SetBackdropColor(unpack(styles.colors.surfaceLight or {0.2, 0.2, 0.2, 1}))
    massDestroyButton:SetBackdropBorderColor(unpack(styles.colors.blackDetail or {0, 0, 0, 1}))
    
    local btnText = massDestroyButton:CreateFontString(nil, "OVERLAY", styles.fonts.label or "GameFontNormal")
    btnText:SetPoint("CENTER", 0, 0)
    btnText:SetText("Destroy Next")
    btnText:SetTextColor(unpack(styles.colors.textLight or {1, 1, 1, 1}))
    massDestroyButton:SetFontString(btnText)

    massDestroyButton:SetScript("OnEnter", function(self)
        if styles.colors.primary then self:SetBackdropColor(unpack(styles.colors.primary)) end
        if styles.colors.textLight then self:SetBackdropBorderColor(unpack(styles.colors.textLight)) end
    end)
    massDestroyButton:SetScript("OnLeave", function(self)
        if styles.colors.surfaceLight then self:SetBackdropColor(unpack(styles.colors.surfaceLight)) end
        if styles.colors.blackDetail then self:SetBackdropBorderColor(unpack(styles.colors.blackDetail)) end
    end)
    massDestroyButton:SetScript("OnMouseDown", function(self) btnText:SetPoint("CENTER", 1, -1) end)
    massDestroyButton:SetScript("OnMouseUp", function(self) btnText:SetPoint("CENTER", 0, 0) end)

    -- Anchor secure button to main frame (centered in the right panel)
    massDestroyButton:SetParent(mainFrame)
    massDestroyButton:SetPoint("BOTTOM", mainFrame, "BOTTOMLEFT", 300, 20)

    mainFrame:HookScript("OnShow", function()
        Ascension.crafting.updateDestroyQueue()
    end)

    _G.SLASH_ASCENSIONPROF1 = "/aph"
    _G.SlashCmdList["ASCENSIONPROF"] = function() mainFrame:Show() end
end

local eventFrame = CreateFrame("Frame")
eventFrame:RegisterEvent("ADDON_LOADED")
eventFrame:RegisterEvent("PLAYER_LOGIN")
eventFrame:SetScript("OnEvent", function(self, event, arg1)
    if event == "ADDON_LOADED" and arg1 == addonName then
        AscensionDB = AscensionDB or {}
        AscensionDB.blacklist = AscensionDB.blacklist or {}
    elseif event == "PLAYER_LOGIN" then
        createUI()
    end
end)
