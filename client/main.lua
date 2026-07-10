local spawnedPeds = {}
local nearestStore = nil

local function vehLabel(model)
    local name = GetLabelText(GetDisplayNameFromVehicleModel(model))
    if not name or name == '' or name == 'NULL' then
        name = GetDisplayNameFromVehicleModel(model)
    end
    return name
end

local function statusLine(v)
    return ('🔧 %d%%  |  🛠️ %d%%  |  ⛽ %d%%  |  🧼 %d%%'):format(v.body, v.engine, v.fuel, v.dirt or 0)
end

local function ownerLine(veh)
    return (veh.isGroup and '🏢 ' or '👤 ') .. (veh.owner or '—')
end

local function vehDescription(veh)
    return ('%s  •  %s\n%s'):format(veh.plate, ownerLine(veh), statusLine(veh))
end

local function applySpawnedVehicle(netId, props)
    local entity = lib.waitFor(function()
        local e = NetworkGetEntityFromNetworkId(netId)
        if e and e ~= 0 and DoesEntityExist(e) then return e end
    end, 'Vehicle failed to spawn', 5000)

    if not entity then return end

    local tries = 0
    while not NetworkHasControlOfEntity(entity) and tries < 20 do
        NetworkRequestControlOfEntity(entity)
        Wait(50)
        tries += 1
    end
    lib.setVehicleProperties(entity, props)

    if props.fuelLevel then
        SetVehicleFuelLevel(entity, props.fuelLevel + 0.0)
        if Config.FuelStatebag then
            Entity(entity).state:set(Config.FuelStatebag, props.fuelLevel + 0.0, true)
        end
    end

    if props.engineHealth then SetVehicleEngineHealth(entity, props.engineHealth + 0.0) end
    if props.bodyHealth then SetVehicleBodyHealth(entity, props.bodyHealth + 0.0) end
    if props.tankHealth then SetVehiclePetrolTankHealth(entity, props.tankHealth + 0.0) end

    return entity
end

local function findGarage(garageId)
    for _, g in ipairs(Config.Garages or {}) do
        if g.id == garageId then return g end
    end
end

local function getSpawnPoints(obj)
    if obj.spawnPoints then return obj.spawnPoints end
    if obj.spawn then return { obj.spawn } end
    return {}
end

local function isSpotFree(coords, radius)
    radius = radius or 2.5
    local target = vec3(coords.x, coords.y, coords.z)
    for _, veh in ipairs(GetGamePool('CVehicle')) do
        if DoesEntityExist(veh) and #(GetEntityCoords(veh) - target) < radius then return false end
    end
    for _, obj in ipairs(GetGamePool('CObject')) do
        if DoesEntityExist(obj) and #(GetEntityCoords(obj) - target) < radius then return false end
    end
    return true
end

local function pickFreeSpawnIndex(points)
    for i, p in ipairs(points) do
        if isSpotFree(p) then return i end
    end
    return nil
end

local function takeOut(veh, garageId)
    local spawnIndex = nil
    local garage = findGarage(garageId)
    if garage then
        local points = getSpawnPoints(garage)
        if #points > 0 then
            spawnIndex = pickFreeSpawnIndex(points)
            if not spawnIndex then
                return lib.notify({ description = 'All exits are blocked by a vehicle or object.', type = 'error' })
            end
        end
    end

    local ok, data = lib.callback.await('m3_garages:takeOut', false, veh.id, garageId, spawnIndex, vehLabel(veh.model))
    if not ok then
        lib.notify({ description = data or 'Failed to take out the vehicle', type = 'error' })
        return
    end

    applySpawnedVehicle(data.netId, data.props)
end

local function openGarage(garageId)
    local vehicles = lib.callback.await('m3_garages:getVehicles', false, garageId)

    local options = {}
    if not vehicles or #vehicles == 0 then
        options[#options + 1] = { title = 'No vehicles', disabled = true }
    else
        for _, veh in ipairs(vehicles) do
            options[#options + 1] = {
                title       = vehLabel(veh.model),
                description = vehDescription(veh),
                icon        = veh.blocked and 'lock' or 'car',
                iconColor   = veh.blocked and '#ff453a' or nil,
                metadata    = {
                    { label = 'VIN', value = veh.vin or '—' },
                    { label = 'Status', value = veh.blocked and 'Blocked by police' or 'In garage' },
                },
                onSelect = function()
                    if veh.blocked then
                        lib.notify({ description = 'Vehicle is blocked by police', type = 'error' })
                    else
                        takeOut(veh, garageId)
                    end
                end,
            }
        end
    end

    lib.registerContext({
        id = 'm3_garage_main',
        title = 'Garage',
        options = options,
    })
    lib.showContext('m3_garage_main')
end

local function finalizeTransfer(veh, targetType, targetValue)
    local fee = Config.TransferFee or 0
    local content = fee > 0
        and ('Transferring vehicle **%s** costs **$%d**. Continue?'):format(veh.plate, fee)
        or  ('Transfer vehicle **%s**?'):format(veh.plate)

    local confirm = lib.alertDialog({
        header = 'Vehicle transfer',
        content = content,
        centered = true,
        cancel = true,
    })
    if confirm ~= 'confirm' then return end

    local ok, data = lib.callback.await('m3_garages:transfer', false, veh.id, targetType, targetValue)
    if ok then
        local paid = (type(data) == 'table' and data.fee) or fee
        lib.notify({ description = paid > 0 and ('Vehicle transferred (-$%d)'):format(paid) or 'Vehicle transferred', type = 'success' })
    else
        lib.notify({ description = (type(data) == 'string' and data) or 'Transfer failed', type = 'error' })
    end
end

local selecting = false

local function runSelector(items, onPick)
    if selecting then return end
    if not items or #items == 0 then
        return lib.notify({ description = 'Nobody nearby', type = 'error' })
    end

    local index = 1
    selecting = true

    local function showUI()
        lib.showTextUI(items[index].label, { position = 'right-center', icon = 'list' })
    end
    showUI()

    CreateThread(function()
        while selecting do
            local c = items[index] and items[index].coords()
            if c then
                DrawMarker(2, c.x, c.y, c.z, 0.0, 0.0, 0.0, 180.0, 0.0, 0.0,
                    0.35, 0.35, 0.35, 30, 130, 255, 200, true, true, 2, false, nil, nil, false)
            end

            DisableControlAction(0, 174, true)
            DisableControlAction(0, 175, true)
            DisableControlAction(0, 176, true)
            DisableControlAction(0, 177, true)

            if IsDisabledControlJustPressed(0, 174) then
                index = index - 1; if index < 1 then index = #items end; showUI()
            elseif IsDisabledControlJustPressed(0, 175) then
                index = index + 1; if index > #items then index = 1 end; showUI()
            elseif IsDisabledControlJustPressed(0, 176) then
                selecting = false; lib.hideTextUI(); onPick(items[index].value); return
            elseif IsDisabledControlJustPressed(0, 177) then
                selecting = false; lib.hideTextUI(); return
            end

            Wait(0)
        end
    end)
end

local function selectNearbyPlayer(onPick)
    local players = lib.getNearbyPlayers(GetEntityCoords(cache.ped), 15.0, false)
    local items = {}
    for i, p in ipairs(players) do
        local ped = p.ped
        items[#items + 1] = {
            label = ('Player #%d'):format(i),
            coords = function() return GetEntityCoords(ped) + vec3(0.0, 0.0, 1.2) end,
            value = GetPlayerServerId(p.id),
        }
    end
    runSelector(items, onPick)
end

local function openFirmList(veh)
    local groups = lib.callback.await('m3_garages:getPlayerGroups', false)

    local options = {}
    if not groups or #groups == 0 then
        options[#options + 1] = { title = 'You are not in any company', disabled = true }
    else
        for _, g in ipairs(groups) do
            options[#options + 1] = {
                title = g.label,
                icon = 'building',
                onSelect = function() finalizeTransfer(veh, 'group', g.name) end,
            }
        end
    end

    lib.registerContext({
        id = 'm3_transfer_firms',
        title = 'TRANSFER TO',
        menu = 'm3_transfer_target',
        options = options,
    })
    lib.showContext('m3_transfer_firms')
end

local function openTransferTarget(veh, backMenu)
    lib.registerContext({
        id = 'm3_transfer_target',
        title = 'REGISTRATION - TRANSFER TARGET',
        menu = backMenu,
        options = {
            {
                title = 'Person',
                description = 'Transfer the vehicle to a person.',
                icon = 'user',
                onSelect = function()
                    selectNearbyPlayer(function(serverId) finalizeTransfer(veh, 'person', serverId) end)
                end,
            },
            {
                title = 'Company',
                description = 'Transfer the vehicle to a company.',
                icon = 'building',
                onSelect = function() openFirmList(veh) end,
            },
        },
    })
    lib.showContext('m3_transfer_target')
end

local function openGradePicker(kind, veh, backMenu)
    local info = lib.callback.await('m3_garages:getGroupGrades', false) or {}
    local grades = info.grades or {}

    local options = {}
    if kind == 'use' then
        options[#options + 1] = {
            title = 'Everyone (no restriction)',
            icon = 'users',
            onSelect = function()
                local ok, err = lib.callback.await('m3_garages:setVehicleAccess', false, veh.id, kind, 0)
                lib.notify({ description = ok and 'Access updated' or (err or 'Error'), type = ok and 'success' or 'error' })
            end,
        }
    end

    for _, g in ipairs(grades) do
        options[#options + 1] = {
            title = g.label,
            description = 'This rank and above',
            icon = kind == 'use' and 'key' or 'user-shield',
            onSelect = function()
                local ok, err = lib.callback.await('m3_garages:setVehicleAccess', false, veh.id, kind, g.grade)
                lib.notify({ description = ok and 'Access updated' or (err or 'Error'), type = ok and 'success' or 'error' })
            end,
        }
    end

    if #options == 0 then
        options[#options + 1] = { title = 'No ranks', disabled = true }
    end

    local id = 'm3_grade_picker'
    lib.registerContext({
        id = id,
        title = kind == 'use' and 'WHO CAN USE' or 'WHO CAN TRANSFER',
        menu = backMenu,
        options = options,
    })
    lib.showContext(id)
end

local function openVehicleActions(veh, backMenu)
    local id = 'm3_veh_actions'
    local options = {
        { title = 'Transfer vehicle', icon = 'right-left', arrow = true, onSelect = function() openTransferTarget(veh, id) end },
    }
    if veh.isGroup and veh.canManage then
        options[#options + 1] = {
            title = 'Who can use', description = 'Set the rank required to use the vehicle',
            icon = 'key', arrow = true, onSelect = function() openGradePicker('use', veh, id) end,
        }
        options[#options + 1] = {
            title = 'Who can transfer', description = 'Set the rank required to transfer the vehicle',
            icon = 'user-shield', arrow = true, onSelect = function() openGradePicker('transfer', veh, id) end,
        }
    end
    lib.registerContext({ id = id, title = vehLabel(veh.model), menu = backMenu, options = options })
    lib.showContext(id)
end

local function openTransferList(category, title)
    local vehicles = lib.callback.await('m3_garages:getTransferVehicles', false, category)
    local menuId = 'm3_transfer_list'

    local options = {}
    if not vehicles or #vehicles == 0 then
        options[#options + 1] = { title = 'No vehicles', disabled = true }
    else
        for _, veh in ipairs(vehicles) do
            options[#options + 1] = {
                title       = vehLabel(veh.model),
                description = ('Plate: %s\nVIN: %s'):format(veh.plate, veh.vin or '—'),
                icon        = 'car',
                onSelect    = function()
                    if veh.isGroup and veh.canManage then
                        openVehicleActions(veh, menuId)
                    else
                        openTransferTarget(veh, menuId)
                    end
                end,
            }
        end
    end

    lib.registerContext({
        id = menuId,
        title = title,
        menu = 'm3_transfer_main',
        options = options,
    })
    lib.showContext(menuId)
end

local function openTransfer()
    local cats = lib.callback.await('m3_garages:getTransferCategories', false)

    local options = {
        {
            title = 'Personal vehicles',
            icon = 'user',
            arrow = true,
            onSelect = function() openTransferList('personal', 'Personal vehicles') end,
        },
    }

    if cats and cats.hasGroup then
        options[#options + 1] = {
            title = 'Company vehicles ' .. (cats.groupLabel or ''),
            icon = 'building',
            arrow = true,
            onSelect = function() openTransferList('group', 'Company vehicles ' .. (cats.groupLabel or '')) end,
        }
    end

    lib.registerContext({
        id = 'm3_transfer_main',
        title = 'REGISTRATION - VEHICLE TRANSFER',
        options = options,
    })
    lib.showContext('m3_transfer_main')
end

local function openImpound(impoundIndex, impoundLabel)
    local vehicles = lib.callback.await('m3_garages:getImpound', false)

    local options = {}
    if not vehicles or #vehicles == 0 then
        options[#options + 1] = { title = 'No vehicles in the impound', disabled = true }
    else
        for _, veh in ipairs(vehicles) do
            options[#options + 1] = {
                title       = vehLabel(veh.model),
                description = vehDescription(veh),
                icon        = 'car',
                metadata    = {
                    { label = 'VIN', value = veh.vin or '—' },
                    { label = 'Fee', value = '$' .. veh.fee },
                },
                onSelect    = function()
                    local confirm = lib.alertDialog({
                        header = 'Impound retrieval',
                        content = ('Retrieve **%s** for **$%d**?'):format(veh.plate, veh.fee),
                        centered = true,
                        cancel = true,
                    })
                    if confirm ~= 'confirm' then return end

                    local spawnIndex = nil
                    local impounds = Config.Impounds or (Config.Impound and { Config.Impound }) or {}
                    local impound = impounds[impoundIndex]
                    if impound then
                        local points = getSpawnPoints(impound)
                        if #points > 0 then
                            spawnIndex = pickFreeSpawnIndex(points)
                            if not spawnIndex then
                                return lib.notify({ description = 'All exits are blocked by a vehicle or object.', type = 'error' })
                            end
                        end
                    end

                    local ok, data = lib.callback.await('m3_garages:impoundRetrieve', false, veh.id, impoundIndex, spawnIndex, vehLabel(veh.model))
                    if not ok then
                        lib.notify({ description = type(data) == 'string' and data or 'Retrieval failed', type = 'error' })
                        return
                    end
                    applySpawnedVehicle(data.netId, data.props)
                    lib.notify({ description = ('Vehicle retrieved for $%d'):format(data.fee), type = 'success' })
                end,
            }
        end
    end

    lib.registerContext({ id = 'm3_garage_impound', title = impoundLabel or 'Impound', options = options })
    lib.showContext('m3_garage_impound')
end

local function spawnPed(data)
    RequestModel(data.model)
    while not HasModelLoaded(data.model) do Wait(0) end

    local ped = CreatePed(0, data.model, data.coords.x, data.coords.y, data.coords.z - 1.0, data.coords.w, false, true)
    SetEntityInvincible(ped, true)
    SetBlockingOfNonTemporaryEvents(ped, true)
    FreezeEntityPosition(ped, true)
    if data.scenario then TaskStartScenarioInPlace(ped, data.scenario, 0, true) end
    SetModelAsNoLongerNeeded(data.model)
    spawnedPeds[#spawnedPeds + 1] = ped
    return ped
end

CreateThread(function()
    for _, garage in ipairs(Config.Garages) do
        local ped = spawnPed(garage.npc)
        exports.ox_target:addLocalEntity(ped, {
            {
                name = 'm3_garage_open_' .. garage.id,
                icon = 'fa-solid fa-warehouse',
                label = 'Open garage',
                onSelect = function() openGarage(garage.id) end,
            },
        })

        local storeCoords = garage.storePoints or (garage.store and { garage.store.coords }) or {}
        local storeRadius = garage.storeRadius or (garage.store and garage.store.radius) or 6.0

        for _, coords in ipairs(storeCoords) do
            lib.points.new({
                coords = coords.xyz or coords,
                distance = storeRadius,
                garage = garage,
                nearby = function(self)
                    local isDriver = cache.vehicle and cache.seat == -1

                    if isDriver then
                        nearestStore = self.garage
                        if not self.textShown then
                            self.textShown = true
                            lib.showTextUI(('[%s] Store in garage'):format(Config.StoreKey), {
                                position = 'left-center',
                                icon = 'warehouse',
                            })
                        end
                    elseif self.textShown then
                        self.textShown = false
                        nearestStore = nil
                        lib.hideTextUI()
                    end
                end,
                onExit = function(self)
                    if self.textShown then
                        self.textShown = false
                        lib.hideTextUI()
                    end
                    nearestStore = nil
                end,
            })
        end
    end

    for i, tp in ipairs(Config.TransferPoints) do
        local ped = spawnPed(tp.npc)
        exports.ox_target:addLocalEntity(ped, {
            {
                name = 'm3_garage_transfer_' .. i,
                icon = 'fa-solid fa-file-signature',
                label = 'Vehicle transfer',
                onSelect = function() openTransfer() end,
            },
        })

        if tp.blip and tp.blip.enable then
            local blip = AddBlipForCoord(tp.npc.coords.x, tp.npc.coords.y, tp.npc.coords.z)
            SetBlipSprite(blip, tp.blip.sprite)
            SetBlipColour(blip, tp.blip.color)
            SetBlipScale(blip, tp.blip.scale)
            SetBlipAsShortRange(blip, true)
            BeginTextCommandSetBlipName('STRING')
            AddTextComponentSubstringPlayerName(tp.blip.label or 'Vehicle registration')
            EndTextCommandSetBlipName(blip)
        end
    end

    local impounds = Config.Impounds or (Config.Impound and { Config.Impound }) or {}

    if Config.ImpoundBlipName then
        AddTextEntry('m3_impound_blip', Config.ImpoundBlipName)
    end

    for i, imp in ipairs(impounds) do
        local label = imp.label or 'Impound'
        local ped = spawnPed(imp.npc)
        exports.ox_target:addLocalEntity(ped, {
            {
                name = 'm3_garage_impound_' .. i,
                icon = 'fa-solid fa-truck-ramp-box',
                label = 'Impound',
                onSelect = function() openImpound(i, label) end,
            },
        })

        if imp.blip and imp.blip.enable then
            local blip = AddBlipForCoord(imp.npc.coords.x, imp.npc.coords.y, imp.npc.coords.z)
            SetBlipSprite(blip, imp.blip.sprite)
            SetBlipDisplay(blip, 4)
            SetBlipColour(blip, imp.blip.color)
            SetBlipScale(blip, imp.blip.scale)
            SetBlipAsShortRange(blip, true)
            if Config.ImpoundBlipName then
                BeginTextCommandSetBlipName('m3_impound_blip')
                EndTextCommandSetBlipName(blip)
            else
                BeginTextCommandSetBlipName('STRING')
                AddTextComponentSubstringPlayerName(label)
                EndTextCommandSetBlipName(blip)
            end
        end
    end
end)

local towAllowed = false

CreateThread(function()
    while true do
        towAllowed = lib.callback.await('m3_garages:isTowAllowed', false) or false
        Wait(5000)
    end
end)

exports.ox_target:addGlobalVehicle({
    {
        name = 'm3_garage_tow',
        icon = 'fa-solid fa-truck-pickup',
        label = 'Tow vehicle',
        distance = 3.0,
        canInteract = function()
            return towAllowed
        end,
        onSelect = function(data)
            local confirm = lib.alertDialog({
                header = 'Tow vehicle',
                content = 'Do you really want to tow this vehicle to the impound?',
                centered = true,
                cancel = true,
            })
            if confirm ~= 'confirm' then return end

            local done = lib.progressBar({
                duration = Config.TowDuration,
                label = 'Towing vehicle...',
                useWhileDead = false,
                canCancel = true,
                disable = { move = true, car = true, combat = true },
                anim = { scenario = 'WORLD_HUMAN_STAND_MOBILE' },
            })
            if not done then
                lib.notify({ description = 'Tow cancelled', type = 'error' })
                return
            end

            local netId = NetworkGetNetworkIdFromEntity(data.entity)
            local ok, err = lib.callback.await('m3_garages:tow', false, netId)
            if not ok then
                lib.notify({ description = err or 'Tow failed', type = 'error' })
            end
        end,
    },
})

local function attemptStore()
    if not nearestStore then return end

    local ped = PlayerPedId()
    local veh = GetVehiclePedIsIn(ped, false)
    if veh == 0 then
        lib.notify({ description = 'You must be in a vehicle', type = 'error' })
        return
    end
    if GetPedInVehicleSeat(veh, -1) ~= ped then
        lib.notify({ description = 'You must be the driver', type = 'error' })
        return
    end

    local props = lib.getVehicleProperties(veh)
    local garageId = nearestStore.id
    local netId = NetworkGetNetworkIdFromEntity(veh)

    local ok, err = lib.callback.await('m3_garages:store', false, props, garageId, netId)
    if ok then
        lib.hideTextUI()
    else
        lib.notify({ description = err or 'Failed to store vehicle', type = 'error' })
    end
end

lib.addKeybind({
    name = 'm3_store_vehicle',
    description = 'Store vehicle in garage',
    defaultKey = Config.StoreKey,
    onPressed = attemptStore,
})

RegisterNetEvent('m3_garages:collectVehicle', function(garageId)
    local ped = PlayerPedId()
    local veh = GetVehiclePedIsIn(ped, false)
    if veh == 0 then
        lib.notify({ description = 'You are not in any vehicle', type = 'error' })
        return
    end

    local props = lib.getVehicleProperties(veh)
    local netId = NetworkGetNetworkIdFromEntity(veh)
    TriggerServerEvent('m3_garages:saveCollected', garageId, props, netId)
end)

AddEventHandler('onResourceStop', function(res)
    if res ~= GetCurrentResourceName() then return end
    for _, ped in ipairs(spawnedPeds) do
        if DoesEntityExist(ped) then DeleteEntity(ped) end
    end
    lib.hideTextUI()
end)

local function toggleNearestLock()
    if not Config.Keys or not Config.Keys.enable then return end
    local ped = cache.ped
    local veh

    if IsPedInAnyVehicle(ped, false) then
        veh = GetVehiclePedIsIn(ped, false)
    else
        veh = lib.getClosestVehicle(GetEntityCoords(ped), Config.Keys.lockRadius or 5.0, false)
    end

    if not veh or veh == 0 then
        return lib.notify({ description = 'No vehicle nearby.', type = 'error' })
    end
    TriggerServerEvent('m3_garages:toggleLock', NetworkGetNetworkIdFromEntity(veh))
end

exports('useKey', function()
    toggleNearestLock()
end)

exports('giveKey', function(slot)
    exports.ox_inventory:closeInventory()
    Wait(150)
    selectNearbyPlayer(function(serverId)
        TriggerServerEvent('m3_garages:giveKey', slot, serverId)
    end)
end)

lib.addKeybind({
    name = 'm3_vehiclekey',
    description = 'Lock/unlock vehicle (key)',
    defaultKey = (Config.Keys and Config.Keys.lockKey) or 'K',
    onPressed = function()
        toggleNearestLock()
    end,
})

local function applyLockState(veh, value)
    if veh and veh ~= 0 and DoesEntityExist(veh) then
        SetVehicleDoorsLocked(veh, value and 2 or 1)
    end
end

local function lockEffects(veh, locked)
    if not (veh and veh ~= 0 and DoesEntityExist(veh)) then return end
    SetVehicleLights(veh, 2)
    CreateThread(function() Wait(220); SetVehicleLights(veh, 0) end)
end

AddStateBagChangeHandler('vehLocked', nil, function(bagName, _, value)
    local netId = tonumber(bagName:match('entity:(%d+)'))
    if not netId then return end
    local veh = NetworkGetEntityFromNetworkId(netId)
    if veh and veh ~= 0 then
        applyLockState(veh, value)
        lockEffects(veh, value)
        return
    end
    CreateThread(function()
        local tries = 0
        while tries < 20 do
            veh = NetworkGetEntityFromNetworkId(netId)
            if veh and veh ~= 0 and DoesEntityExist(veh) then
                applyLockState(veh, value)
                return
            end
            Wait(100)
            tries += 1
        end
    end)
end)

RegisterNetEvent('m3_garages:lockFeedback', function(netId, locked)
    local ped = cache.ped
    if not IsPedInAnyVehicle(ped, false) then
        CreateThread(function()
            local dict = 'anim@mp_player_intmenu@key_fob@'
            lib.requestAnimDict(dict)
            TaskPlayAnim(ped, dict, 'fob_click', 4.0, -4.0, -1, 48, 0, false, false, false)
            Wait(900)
            StopAnimTask(ped, dict, 'fob_click', 2.0)
            RemoveAnimDict(dict)
        end)
    end

end)
