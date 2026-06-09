-------------------------------------------------------------------------------
-- Project: AscensionProfessionHelper
-- Author: Aka-DoctorCode
-- File: AscensionProfessionHelper.lua
-------------------------------------------------------------------------------
---@diagnostic disable: undefined-global, undefined-field, inject-field

local addonName, Ascension = ...
Ascension.crafting = { queue = {}, currentTargetItem = nil, sessionConfirmed = false, allowedDangerousItems = {} }

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

local destroyOverlayBtn = CreateFrame("Button", "AscensionMassDestroyOverlayBtn", UIParent, "BackdropTemplate")
destroyOverlayBtn:SetSize(150, 40)
destroyOverlayBtn:Hide()
destroyOverlayBtn:SetScript("OnClick", function()
    if not Ascension.crafting.currentTargetItem then return end
    StaticPopupDialogs["ASCENSION_CONFIRM_DESTROY"] = {
        text = "Are you sure you want to start destroying items?",
        button1 = "Yes",
        button2 = "No",
        OnAccept = function()
            Ascension.crafting.sessionConfirmed = true
            if AscensionDB.lastBind and _G.AscensionProfHelperUI then
                SetOverrideBindingClick(_G.AscensionProfHelperUI, true, AscensionDB.lastBind, "AscensionMassDestroyBtn", "LeftButton")
            end
            destroyOverlayBtn:Hide()
            Ascension.crafting.updateDestroyQueue()
        end,
        timeout = 0,
        whileDead = true,
        hideOnEscape = true,
    }
    StaticPopup_Show("ASCENSION_CONFIRM_DESTROY")
end)

local categoryPanels = {}
local itemFrames = {}
local blFrames = {}
local searchFilter = ""

function Ascension.crafting.updateBlacklistUI()
    local activePanel = categoryPanels[4]
    if not activePanel then return end

    for _, f in ipairs(blFrames) do f:Hide() end
    local y = -70
    local i = 1
    for id, _ in pairs(AscensionCharDB.blacklist or {}) do
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
                                        AscensionCharDB.blacklist[f.itemId] = nil
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

function Ascension.crafting.isItemDestroyable(bagIndex, slotIndex, itemId, itemLink)
    if AscensionCharDB and AscensionCharDB.blacklist and AscensionCharDB.blacklist[itemId] then
        return false, nil
    end
    if Ascension.crafting.sessionBlacklist and Ascension.crafting.sessionBlacklist[itemId] then
        return false, nil
    end

    local tooltipData
    if bagIndex and slotIndex then
        tooltipData = C_TooltipInfo.GetBagItem(bagIndex, slotIndex)
    else
        tooltipData = C_TooltipInfo.GetItemByID(itemId)
    end

    local isNotDisenchantable = false
    local isRelicByTooltip = false

    if tooltipData then
        for _, line in ipairs(tooltipData.lines) do
            -- Extract text aggressively to miss nothing (checks leftText, rightText, and hidden args)
            local fullText = (line.leftText or "") .. " " .. (line.rightText or "")
            if line.args then
                for _, arg in ipairs(line.args) do
                    if arg.stringVal then
                        fullText = fullText .. arg.stringVal .. " "
                    end
                end
            end
            
            -- Clean color codes, textures, and line breaks completely
            local plainText = string.gsub(fullText, "|c%x%x%x%x%x%x%x%x", "")
            plainText = string.gsub(plainText, "|r", "")
            plainText = string.gsub(plainText, "|T.-|t", "")
            plainText = string.gsub(plainText, "\n", "")
            
            local lowerText = string.lower(plainText)
            
            if string.find(lowerText, "prospectable") or string.find(lowerText, "se puede prospectar") or (ITEM_PROSPECTABLE and string.find(plainText, ITEM_PROSPECTABLE, 1, true)) then 
                if  C_SpellBook.IsSpellInSpellBook(31252) or  C_SpellBook.IsSpellInSpellBook(78670) or  C_SpellBook.IsSpellInSpellBook(132623) then return true, "Prospecting" end
            end
            
            if string.find(lowerText, "millable") or string.find(lowerText, "molible") or string.find(lowerText, "se puede moler") or (ITEM_MILLABLE and string.find(plainText, ITEM_MILLABLE, 1, true)) then 
                if  C_SpellBook.IsSpellInSpellBook(51005) or  C_SpellBook.IsSpellInSpellBook(2108) then return true, "Milling" end
            end
            
            -- Detect if it CANNOT be disenchanted
            if string.find(lowerText, "cannot be disenchanted") or string.find(lowerText, "not disenchantable") or string.find(lowerText, "no se puede desencantar") or string.find(lowerText, "no desencantable") then
                isNotDisenchantable = true
            end
            if ITEM_DISENCHANT_NOT_DISENCHANTABLE and string.find(plainText, ITEM_DISENCHANT_NOT_DISENCHANTABLE, 1, true) then
                isNotDisenchantable = true
            end
            
            -- Fallback for Relics
            if string.find(lowerText, "artifact relic") or string.find(lowerText, "reliquia artefacto") or string.find(lowerText, "reliquia de artefacto") then
                isRelicByTooltip = true
            end
        end
    end
    
    local _, _, itemQuality, itemLevel, _, _, _, _, equipLoc, _, _, classId, subClassId = C_Item.GetItemInfo(itemLink or itemId)
    
    local isRelic = (classId == 3 and subClassId == 11) or isRelicByTooltip
    
    -- Cache error prevention
    if not isRelic and (not classId or not itemQuality) then return false, nil end

    if isNotDisenchantable and not isRelic then return false, nil end
    
    -- Strict blacklist of equipment locations that the game catalogs as armor/weapon but CANNOT be disenchanted
    local invalidEquipLocs = {
        ["INVTYPE_TABARD"]          = true,
        ["INVTYPE_BODY"]            = true, -- Shirts
        ["INVTYPE_BAG"]             = true,
        ["INVTYPE_QUIVER"]          = true,
        ["INVTYPE_PROFESSION_TOOL"] = true,
        ["INVTYPE_PROFESSION_GEAR"] = true,
        [""]                        = true  -- Non-equippable items (Miscellaneous trash that slips through)
    }

    if invalidEquipLocs[equipLoc] then
        if not (classId == 3 and subClassId == 11) then
            return false, nil
        end
    end

    -- Discard cosmetics, fishing poles, and old tools explicitly
    if classId == 4 and subClassId == 5 then return false, nil end
    if classId == 2 and subClassId == 20 then return false, nil end

    -- Fallback Disenchant logic: Weapons(2), Armor(4), and Artifact Relics (3,11)
    local maxQual = AscensionDB.deMaxQuality or 4
    local isWeaponOrArmor = (classId == 2 or classId == 4)
    
    if isRelic then
        return true, "Disenchant", true
    end
    
    local sellPrice = select(11, C_Item.GetItemInfo(itemLink or itemId))
    
    if (isWeaponOrArmor and itemQuality >= 2 and itemQuality <= maxQual) then
        -- Starter/Booster weapons that cannot be destroyed usually have 0 sell price
        if sellPrice == 0 then
            return false, nil
        end
        if (itemLevel and itemLevel > 4) then
            return true, "Disenchant", false
        end
    end

    return false, nil, false
end

function Ascension.crafting.isItemDangerous(link, itemId)
    local itemEquipLoc = select(9, C_Item.GetItemInfo(link))
    if not itemEquipLoc or itemEquipLoc == "" then return false end
    
    local inventorySlotId = nil
    if itemEquipLoc == "INVTYPE_HEAD" then inventorySlotId = 1
    elseif itemEquipLoc == "INVTYPE_NECK" then inventorySlotId = 2
    elseif itemEquipLoc == "INVTYPE_SHOULDER" then inventorySlotId = 3
    elseif itemEquipLoc == "INVTYPE_CHEST" or itemEquipLoc == "INVTYPE_ROBE" then inventorySlotId = 5
    elseif itemEquipLoc == "INVTYPE_WAIST" then inventorySlotId = 6
    elseif itemEquipLoc == "INVTYPE_LEGS" then inventorySlotId = 7
    elseif itemEquipLoc == "INVTYPE_FEET" then inventorySlotId = 8
    elseif itemEquipLoc == "INVTYPE_WRIST" then inventorySlotId = 9
    elseif itemEquipLoc == "INVTYPE_HAND" then inventorySlotId = 10
    elseif itemEquipLoc == "INVTYPE_FINGER" then inventorySlotId = 11
    elseif itemEquipLoc == "INVTYPE_TRINKET" then inventorySlotId = 13
    elseif itemEquipLoc == "INVTYPE_CLOAK" then inventorySlotId = 15
    elseif itemEquipLoc == "INVTYPE_WEAPON" or itemEquipLoc == "INVTYPE_2HWEAPON" or itemEquipLoc == "INVTYPE_WEAPONMAINHAND" then inventorySlotId = 16
    elseif itemEquipLoc == "INVTYPE_SHIELD" or itemEquipLoc == "INVTYPE_WEAPONOFFHAND" or itemEquipLoc == "INVTYPE_HOLDABLE" then inventorySlotId = 17
    end
    
    if not inventorySlotId then return false end

    local detailedILvl = C_Item.GetDetailedItemLevelInfo(link)
    if not detailedILvl then return false end

    local function getSlotILvl(slot)
        local l = GetInventoryItemLink("player", slot)
        if not l then return 0 end
        return C_Item.GetDetailedItemLevelInfo(l) or 0
    end

    local equippedILvl = getSlotILvl(inventorySlotId)
    if inventorySlotId == 11 then equippedILvl = math.min(equippedILvl, getSlotILvl(12)) end
    if inventorySlotId == 13 then equippedILvl = math.min(equippedILvl, getSlotILvl(14)) end

    if detailedILvl >= equippedILvl then
        return true
    end
    return false
end

function Ascension.crafting.updateDestroyQueue()
    if InCombatLockdown() then 
        return 
    end
    
    local mainUI = _G.AscensionProfHelperUI
    local isShown = true


    local activeTab = 1
    if _G.AscensionProfHelperUI and _G.AscensionProfHelperUI.tabbedUI then
        activeTab = _G.AscensionProfHelperUI.tabbedUI:getActiveTab() or 1
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
        if _G.AscensionMassDestroyOverlayBtn then _G.AscensionMassDestroyOverlayBtn:Hide() end
        return
    end

    local foundItems = {}
    local orderedLinks = {}
    local targetBag, targetSlot, targetSpell, targetItem = nil, nil, nil, nil
    local partialStacks = {}
    local pendingCombines = {}
    
    for bagIndex = 0, 5 do
        for slotIndex = 1, C_Container.GetContainerNumSlots(bagIndex) do
            local itemInfo = C_Container.GetContainerItemInfo(bagIndex, slotIndex)
            local itemLink = itemInfo and (itemInfo.hyperlink or C_Container.GetContainerItemLink(bagIndex, slotIndex))
            
            if itemInfo and itemInfo.itemID and not itemInfo.isLocked then
                local isDestroyable, spellName, isConfirmedRelic = Ascension.crafting.isItemDestroyable(bagIndex, slotIndex, itemInfo.itemID, itemLink)
                
                local skipItem = false
                if AscensionDB.includeSoulbound == false and itemInfo.isBound then
                    if not isConfirmedRelic then
                        skipItem = true
                    end
                end

                if not skipItem and isDestroyable and spellName == targetCategory then
                    if itemLink then
                        if not foundItems[itemLink] then
                            foundItems[itemLink] = { count = 0, itemId = itemInfo.itemID }
                            table.insert(orderedLinks, itemLink)
                            Ascension.crafting.lastDebugAddedItem = itemLink
                        end
                        foundItems[itemLink].count = foundItems[itemLink].count + itemInfo.stackCount
                        
                        local isDangerous = Ascension.crafting.isItemDangerous(itemLink, itemInfo.itemID)
                        foundItems[itemLink].isDangerous = isDangerous
                        
                        local minQty = (spellName == "Milling" or spellName == "Prospecting") and 5 or 1
                        
                        if minQty > 1 and itemInfo.stackCount % minQty ~= 0 then
                            if partialStacks[itemInfo.itemID] then
                                table.insert(pendingCombines, {
                                    sBag = partialStacks[itemInfo.itemID].bag,
                                    sSlot = partialStacks[itemInfo.itemID].slot,
                                    tBag = bagIndex,
                                    tSlot = slotIndex
                                })
                                partialStacks[itemInfo.itemID] = nil
                            else
                                partialStacks[itemInfo.itemID] = { bag = bagIndex, slot = slotIndex }
                            end
                        end

                        if not targetBag and (not isDangerous or Ascension.crafting.allowedDangerousItems[itemInfo.itemID]) and itemInfo.stackCount >= minQty then
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

    if #pendingCombines > 0 and not CursorHasItem() and not InCombatLockdown() then
        local c = pendingCombines[1]
        C_Container.PickupContainerItem(c.sBag, c.sSlot)
        C_Container.PickupContainerItem(c.tBag, c.tSlot)
        ClearCursor()
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

                f:RegisterForClicks("LeftButtonUp", "RightButtonUp")
                f:SetScript("OnClick", function(self, button)
                    if self.isDangerous and not Ascension.crafting.allowedDangerousItems[self.itemId] then
                        StaticPopupDialogs["ASCENSION_HANDLE_DANGEROUS"] = {
                            text = "This item might be an upgrade. Do you want to delete it or blacklist it?",
                            button1 = "Delete",
                            button2 = "Blacklist",
                            button3 = "Cancel",
                            OnAccept = function()
                                Ascension.crafting.allowedDangerousItems[self.itemId] = true
                                Ascension.crafting.updateDestroyQueue()
                            end,
                            OnCancel = function(popup, data, reason)
                                if reason == "clicked" then
                                    AscensionCharDB.blacklist[self.itemId] = true
                                    Ascension.crafting.updateDestroyQueue()
                                    Ascension.crafting.updateBlacklistUI()
                                end
                            end,
                            timeout = 0,
                            whileDead = true,
                            hideOnEscape = true,
                        }
                        StaticPopup_Show("ASCENSION_HANDLE_DANGEROUS")
                    elseif button == "RightButton" then
                        local lib = LibStub("AscensionSuit-UI", true)
                        if lib and lib.UX and lib.UX.showContextMenu then
                            lib.UX:showContextMenu(self, {
                                {
                                    text = "Blacklist Item",
                                    func = function()
                                        AscensionCharDB.blacklist[f.itemId] = true
                                        Ascension.log("Blacklisted item " .. f.itemId)
                                        Ascension.crafting.updateDestroyQueue()
                                        Ascension.crafting.updateBlacklistUI()
                                    end
                                },
                                {
                                    text = "Ignore for Session",
                                    func = function()
                                        Ascension.crafting.sessionBlacklist = Ascension.crafting.sessionBlacklist or {}
                                        Ascension.crafting.sessionBlacklist[f.itemId] = true
                                        Ascension.log("Ignored item " .. f.itemId .. " for session")
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
            f.isDangerous = data.isDangerous
            if f.isDangerous and not Ascension.crafting.allowedDangerousItems[id] then
                f:SetBackdropBorderColor(1, 0, 0, 1)
            else
                f:SetBackdropBorderColor(0, 0, 0, 0)
            end
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
            local spellInfo = C_Spell.GetSpellInfo(13262)
            castSpellName = spellInfo and spellInfo.name or "Disenchant"
        elseif targetSpell == "Milling" then
            local spellInfo = C_Spell.GetSpellInfo(51005)
            castSpellName = spellInfo and spellInfo.name or "Milling"
        elseif targetSpell == "Prospecting" then
            local spellInfo = C_Spell.GetSpellInfo(31252)
            castSpellName = spellInfo and spellInfo.name or "Prospecting"
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
        
        if not Ascension.crafting.sessionConfirmed then
            massDestroyButton:Hide()
            if _G.AscensionMassDestroyOverlayBtn then _G.AscensionMassDestroyOverlayBtn:Show() end
        else
            if _G.AscensionMassDestroyOverlayBtn then _G.AscensionMassDestroyOverlayBtn:Hide() end
            massDestroyButton:Show()
        end
    else
        Ascension.crafting.currentTargetItem = nil
        massDestroyButton:SetAttribute("macrotext", "")
        massDestroyButton:SetAttribute("macrotext1", "")
        massDestroyButton:SetAttribute("*macrotext1", "")
        massDestroyButton:SetAttribute("macrotext-down", "")
        massDestroyButton:SetAttribute("macrotext1-down", "")
        massDestroyButton:SetAttribute("*macrotext1-down", "")
        massDestroyButton:Hide()
        if _G.AscensionMassDestroyOverlayBtn then _G.AscensionMassDestroyOverlayBtn:Hide() end
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
errorEventFrame:SetScript("OnEvent", function(self, event, arg1, arg2)
    -- Compatibilidad cruzada: En APIs modernas es (errorType, message), en antiguas es (message)
    local msg = ""
    if type(arg2) == "string" then
        msg = arg2
    elseif type(arg1) == "string" then
        msg = arg1
    end
    
    local lowerMsg = string.lower(msg)
    local isDestroyError = false
    
    -- 1. Comprobación de variables globales de error del juego
    if msg == ERR_NOT_DISENCHANTABLE then isDestroyError = true end
    if msg == (ERR_SPELL_FAILED_SKILL_LINE_NOT_KNOWN or "") then isDestroyError = true end
    
    -- 2. Comprobación agresiva de texto (Inglés y Español)
    if string.find(lowerMsg, "disenchant") or string.find(lowerMsg, "desencantar") then isDestroyError = true end
    if string.find(lowerMsg, "mill") or string.find(lowerMsg, "moler") then isDestroyError = true end
    if string.find(lowerMsg, "prospect") or string.find(lowerMsg, "prospectar") then isDestroyError = true end
    if string.find(lowerMsg, "skill") or string.find(lowerMsg, "habilidad") then isDestroyError = true end
    if string.find(lowerMsg, "invalid target") or string.find(lowerMsg, "objetivo no válido") then isDestroyError = true end
    
    -- 3. Catch modern WoW specific disenchant failures
    if string.find(lowerMsg, "cannot be") or string.find(lowerMsg, "no se puede") then isDestroyError = true end

    -- Si detectamos una falla relacionada con intentar destruir el objeto
    if isDestroyError and Ascension.crafting.currentTargetItem then
        -- Lo añadimos a la base de datos de bloqueados
        AscensionCharDB.blacklist[Ascension.crafting.currentTargetItem] = true
        Ascension.log("Auto-bloqueado por rechazo del servidor: " .. msg)
        
        -- Movemos el current target a nil para forzar el recálculo y no quedarnos atrapados
        Ascension.crafting.currentTargetItem = nil
        
        -- Actualizamos la cola para que desaparezca visualmente y pase al siguiente
        Ascension.crafting.updateDestroyQueue()
        Ascension.crafting.updateBlacklistUI()
        
        -- Limpiamos el texto rojo de error de la pantalla para que no moleste
        if UIErrorsFrame then UIErrorsFrame:Clear() end
    end
end)



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
            searchBox:SetPoint("TOPLEFT", 10, -30)
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
                        
                        AscensionDB.lastBind = bindStr
                        if _G.AscensionProfHelperUI then
                            SetOverrideBindingClick(_G.AscensionProfHelperUI, true, bindStr, "AscensionMassDestroyBtn", "LeftButton")
                        end
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
                            if _G.AscensionProfHelperUI then
                                ClearOverrideBindings(_G.AscensionProfHelperUI)
                            end
                            Ascension.log("Removed bind: " .. AscensionDB.lastBind)
                            AscensionDB.lastBind = nil
                        end
                    end
                end
            })
            unbindBtn:ClearAllPoints()
            unbindBtn:SetPoint("TOPLEFT", bindBtn, "BOTTOMLEFT", 0, -10)
            
            local title2 = panel.content:CreateFontString(nil, "OVERLAY", "GameFontHighlightLarge")
            title2:SetPoint("TOPLEFT", unbindBtn, "BOTTOMLEFT", 0, -20)
            title2:SetText("Destroy Settings")

            local maxQualDrop = ctx:createDropdown({
                parent = panel.content,
                text = "Max Disenchant Quality",
                options = {
                    { label = "Uncommon", value = 2 },
                    { label = "Rare", value = 3 },
                    { label = "Epic", value = 4 },
                },
                getter = function() return AscensionDB.deMaxQuality or 4 end,
                setter = function(val) AscensionDB.deMaxQuality = val; Ascension.crafting.updateDestroyQueue() end,
                width = 220
            })
            maxQualDrop:ClearAllPoints()
            maxQualDrop:SetPoint("TOPLEFT", title2, "BOTTOMLEFT", 10, -15)

            local includeSoulboundCb = CreateFrame("CheckButton", nil, panel.content, "UICheckButtonTemplate")
            includeSoulboundCb:SetPoint("TOPLEFT", maxQualDrop, "BOTTOMLEFT", -5, -10)
            includeSoulboundCb.text = includeSoulboundCb:CreateFontString(nil, "OVERLAY", "GameFontNormal")
            includeSoulboundCb.text:SetPoint("LEFT", includeSoulboundCb, "RIGHT", 0, 1)
            includeSoulboundCb.text:SetText("Include Soulbound Items")
            includeSoulboundCb:SetChecked(AscensionDB.includeSoulbound)
            includeSoulboundCb:SetScript("OnClick", function(self)
                AscensionDB.includeSoulbound = self:GetChecked()
                Ascension.crafting.updateDestroyQueue()
            end)
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
                    if _G.AscensionMassDestroyOverlayBtn then _G.AscensionMassDestroyOverlayBtn:Hide() end
                elseif i == 5 then
                    if _G.AscensionMassDestroyBtn then _G.AscensionMassDestroyBtn:Hide() end
                    if _G.AscensionMassDestroyOverlayBtn then _G.AscensionMassDestroyOverlayBtn:Hide() end
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

    if _G.AscensionMassDestroyOverlayBtn then
        _G.AscensionMassDestroyOverlayBtn:SetBackdrop({
            bgFile = styles.files.bgFile,
            edgeFile = styles.files.edgeFile,
            edgeSize = 1,
            insets = { left = 1, right = 1, top = 1, bottom = 1 }
        })
        _G.AscensionMassDestroyOverlayBtn:SetBackdropColor(unpack(styles.colors.surfaceLight or {0.2, 0.2, 0.2, 1}))
        _G.AscensionMassDestroyOverlayBtn:SetBackdropBorderColor(unpack(styles.colors.blackDetail or {0, 0, 0, 1}))
        local overlayText = _G.AscensionMassDestroyOverlayBtn:CreateFontString(nil, "OVERLAY", styles.fonts.label or "GameFontNormal")
        overlayText:SetPoint("CENTER", 0, 0)
        overlayText:SetText("Start Destroy")
        overlayText:SetTextColor(unpack(styles.colors.textLight or {1, 1, 1, 1}))
        _G.AscensionMassDestroyOverlayBtn:SetFontString(overlayText)
        _G.AscensionMassDestroyOverlayBtn:SetScript("OnEnter", massDestroyButton:GetScript("OnEnter"))
        _G.AscensionMassDestroyOverlayBtn:SetScript("OnLeave", massDestroyButton:GetScript("OnLeave"))
        _G.AscensionMassDestroyOverlayBtn:SetScript("OnMouseDown", function(self) overlayText:SetPoint("CENTER", 1, -1) end)
        _G.AscensionMassDestroyOverlayBtn:SetScript("OnMouseUp", function(self) overlayText:SetPoint("CENTER", 0, 0) end)
    end



    -- Anchor secure button to main frame (centered in the right panel)
    massDestroyButton:SetParent(mainFrame)
    massDestroyButton:SetPoint("BOTTOM", mainFrame, "BOTTOMLEFT", 300, 20)
    
    if _G.AscensionMassDestroyOverlayBtn then
        _G.AscensionMassDestroyOverlayBtn:SetParent(mainFrame)
        _G.AscensionMassDestroyOverlayBtn:SetPoint("BOTTOM", mainFrame, "BOTTOMLEFT", 300, 20)
    end

    mainFrame:HookScript("OnShow", function()
        Ascension.crafting.sessionConfirmed = false
        if AscensionDB.lastBind then
            SetOverrideBindingClick(mainFrame, true, AscensionDB.lastBind, "AscensionMassDestroyOverlayBtn", "LeftButton")
        end
        Ascension.crafting.updateDestroyQueue()
    end)
    mainFrame:HookScript("OnHide", function()
        ClearOverrideBindings(mainFrame)
    end)

    _G.SLASH_ASCENSIONPROFHELPER1 = "/aph"
    _G.SlashCmdList["ASCENSIONPROFHELPER"] = function() mainFrame:Show() end

    _G.SLASH_APHDEBUG1 = "/aphdebug"
    _G.SlashCmdList["APHDEBUG"] = function(msg)
        local itemName, itemLink = GameTooltip:GetItem()
        if not itemLink then
            print("APH Debug: Hover over an item and type /aphdebug")
            return
        end
        local itemId = select(1, C_Item.GetItemInfoInstant(itemLink))
        local _, _, q, L, _, _, _, _, E, _, _, c, s = C_Item.GetItemInfo(itemLink)
        print("APH Debug:", itemLink)
        print("Class:", c, "SubClass:", s, "EquipLoc:", E, "Quality:", q, "iLvl:", L)
        
        local isDestroyable, spellName = Ascension.crafting.isItemDestroyable(nil, nil, itemId, itemLink)
        print("isDestroyable returns:", isDestroyable, "spell:", spellName)
        
        -- Check skipItem logic
        local skipItem = false
        local isBound = true -- assume bound for test
        if AscensionDB.includeSoulbound == false and isBound then
            if not (c == 3 and s == 11) then
                skipItem = true
            end
        end
        print("skipItem would be:", skipItem)
    end

    _G.SLASH_APHDEBUGSCAN1 = "/aphdebugscan"
    _G.SlashCmdList["APHDEBUGSCAN"] = function()
        print("APH Debug Scan: Scanning bags 0-5...")
        local totalDestroyable = 0
        for bagIndex = 0, 5 do
            for slotIndex = 1, C_Container.GetContainerNumSlots(bagIndex) do
                local itemInfo = C_Container.GetContainerItemInfo(bagIndex, slotIndex)
                if itemInfo and itemInfo.itemID then
                    local itemLink = itemInfo.hyperlink or C_Container.GetContainerItemLink(bagIndex, slotIndex)
                    local isDestroyable, spellName, isRelic = Ascension.crafting.isItemDestroyable(bagIndex, slotIndex, itemInfo.itemID, itemLink)
                    if isDestroyable then
                        totalDestroyable = totalDestroyable + 1
                        print("Found:", itemLink, "Locked:", tostring(itemInfo.isLocked), "Relic:", tostring(isRelic))
                        
                        -- DUMP TOOLTIP FOR WEAPONS TO FIND MISSING TEXT
                        if not isRelic then
                            local tooltipData = C_TooltipInfo.GetBagItem(bagIndex, slotIndex)
                            if tooltipData then
                                print("  [Tooltip Dump for " .. itemLink .. "]:")
                                for _, line in ipairs(tooltipData.lines) do
                                    local fullText = (line.leftText or "") .. " " .. (line.rightText or "")
                                    if line.args then
                                        for _, arg in ipairs(line.args) do
                                            if arg.stringVal then fullText = fullText .. arg.stringVal .. " " end
                                        end
                                    end
                                    local plainText = string.gsub(fullText, "|c%x%x%x%x%x%x%x%x", "")
                                    plainText = string.gsub(plainText, "|r", "")
                                    plainText = string.gsub(plainText, "|T.-|t", "")
                                    plainText = string.gsub(plainText, "\n", "")
                                    if plainText ~= "" and plainText ~= " " then
                                        print("    - " .. plainText)
                                    end
                                end
                            end
                        end
                        -- END DUMP
                    end
                end
            end
        end
        print("Total destroyable items found:", totalDestroyable)
    end

    _G.SLASH_APHDEBUGBL1 = "/aphdebugbl"
    _G.SlashCmdList["APHDEBUGBL"] = function()
        print("APH Debug Blacklist:")
        local count = 0
        if AscensionCharDB and AscensionCharDB.blacklist then
            for id, val in pairs(AscensionCharDB.blacklist) do
                local name = C_Item.GetItemInfo(id) or ("Unknown Item " .. tostring(id))
                print("  [" .. tostring(id) .. "] -> " .. name .. " = " .. tostring(val))
                count = count + 1
            end
        else
            print("  AscensionCharDB.blacklist is nil!")
        end
        print("Total items in blacklist:", count)
    end
end

local eventFrame = CreateFrame("Frame")
eventFrame:RegisterEvent("ADDON_LOADED")
eventFrame:RegisterEvent("PLAYER_LOGIN")
eventFrame:SetScript("OnEvent", function(self, event, arg1)
    if event == "ADDON_LOADED" and arg1 == addonName then
        AscensionDB = AscensionDB or {}
        AscensionCharDB = AscensionCharDB or {}
        
        if AscensionDB.blacklist then
            AscensionCharDB.blacklist = AscensionDB.blacklist
            AscensionDB.blacklist = nil
        end
        
        AscensionCharDB.blacklist = AscensionCharDB.blacklist or {}
        if AscensionDB.includeSoulbound == nil then AscensionDB.includeSoulbound = true end
        if AscensionDB.deMaxQuality == nil then AscensionDB.deMaxQuality = 4 end
        Ascension.crafting.sessionBlacklist = {}
    elseif event == "PLAYER_LOGIN" then
        createUI()
        if _G.AscensionProfHelperUI then
            _G.AscensionProfHelperUI:Hide()
        end
    end
end)
