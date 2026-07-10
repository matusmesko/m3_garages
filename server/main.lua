local function getGarage(garageId)
    for _, g in ipairs(Config.Garages) do
        if g.id == garageId then return g end
    end
end

local function notify(source, msg, type)
    TriggerClientEvent('ox_lib:notify', source, { title = 'Garage', description = msg, type = type or 'inform' })
end

local function isTrue(v)
    return v == true or v == 1
end

local function normPlate(p)
    return (tostring(p or ''):gsub('%s+$', ''))
end

local function giveVehicleKey(source, plate, label)
    if not Config.Keys or not Config.Keys.enable then return end
    plate = normPlate(plate)
    if plate == '' then return end
    local have = exports.ox_inventory:Search(source, 'count', Config.Keys.item, { plate = plate }) or 0
    if have > 0 then return end
    exports.ox_inventory:AddItem(source, Config.Keys.item, 1, { plate = plate, label = label or plate })
end

local function removeVehicleKey(source, plate)
    if not Config.Keys or not Config.Keys.enable then return end
    plate = normPlate(plate)
    if plate == '' then return end
    local slots = exports.ox_inventory:Search(source, 'slots', Config.Keys.item, { plate = plate })
    if slots and slots[1] then
        exports.ox_inventory:RemoveItem(source, Config.Keys.item, 1, nil, slots[1].slot)
    end
end

local function hasVehicleKey(source, plate)
    if not Config.Keys or not Config.Keys.enable then return false end
    plate = normPlate(plate)
    if plate == '' then return false end
    return (exports.ox_inventory:Search(source, 'count', Config.Keys.item, { plate = plate }) or 0) > 0
end

RegisterNetEvent('m3_garages:giveKey', function(slot, targetId)
    local src = source
    if not Config.Keys or not Config.Keys.enable then return end
    targetId = tonumber(targetId)
    if not targetId or targetId == src or not GetPlayerName(targetId) then return end

    local myPed, targetPed = GetPlayerPed(src), GetPlayerPed(targetId)
    if not myPed or not targetPed or #(GetEntityCoords(myPed) - GetEntityCoords(targetPed)) > 5.0 then
        return notify(src, 'Player is too far away.', 'error')
    end

    local item = exports.ox_inventory:GetSlot(src, slot)
    if not item or item.name ~= Config.Keys.item or not item.metadata or not item.metadata.plate then
        return notify(src, 'Invalid key.', 'error')
    end

    local meta = item.metadata
    if not exports.ox_inventory:RemoveItem(src, Config.Keys.item, 1, nil, slot) then
        return notify(src, 'Handover failed.', 'error')
    end
    if not exports.ox_inventory:AddItem(targetId, Config.Keys.item, 1, meta) then
        exports.ox_inventory:AddItem(src, Config.Keys.item, 1, meta)
        return notify(src, 'Player has no inventory space.', 'error')
    end

    notify(src, ('Key (%s) handed over.'):format(meta.label or meta.plate), 'success')
    notify(targetId, ('You received a key: %s'):format(meta.label or meta.plate), 'inform')
end)

RegisterNetEvent('m3_garages:toggleLock', function(netId)
    local src = source
    if not Config.Keys or not Config.Keys.enable then return end
    local ent = netId and NetworkGetEntityFromNetworkId(netId)
    if not ent or ent == 0 or not DoesEntityExist(ent) then return end

    local plate = normPlate(GetVehicleNumberPlateText(ent))
    if not hasVehicleKey(src, plate) then
        return notify(src, 'You do not have keys for this vehicle.', 'error')
    end

    local locked = not (Entity(ent).state.vehLocked)
    Entity(ent).state:set('vehLocked', locked, true)
    TriggerClientEvent('m3_garages:lockFeedback', src, netId, locked)
end)

local function removeVehicleEntity(entity)
    if not entity or entity == 0 or not DoesEntityExist(entity) then return end

    if exports.ox_core:GetVehicleFromEntity(entity) then
        exports.ox_core:CallVehicle(entity, 'delete')
    else
        DeleteEntity(entity)
    end
end

local function buildSummary(propsJson)
    local props = propsJson and json.decode(propsJson) or nil
    if not props then return { fuel = 100, engine = 100, body = 100, dirt = 0 } end
    return {
        fuel   = math.floor((props.fuelLevel or 100) + 0.5),
        engine = math.floor(((props.engineHealth or 1000) / 10) + 0.5),
        body   = math.floor(((props.bodyHealth or 1000) / 10) + 0.5),
        dirt   = math.floor(((props.dirtLevel or 0) / 15 * 100) + 0.5),
    }
end

local function generateVin()
    local chars = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789'
    local vin
    repeat
        vin = ''
        for _ = 1, 17 do
            local i = math.random(#chars)
            vin = vin .. chars:sub(i, i)
        end
    until not MySQL.scalar.await('SELECT 1 FROM `m3_garage_vehicles` WHERE `vin` = ?', { vin })
    return vin
end

local function generatePlate()
    local chars = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789'
    local plate
    repeat
        plate = ''
        for _ = 1, 8 do
            local i = math.random(#chars)
            plate = plate .. chars:sub(i, i)
        end
    until not MySQL.scalar.await('SELECT 1 FROM `m3_garage_vehicles` WHERE `plate` = ?', { plate })
    return plate
end

local function plateKey(p)
    return (tostring(p or ''):gsub('%s+', '')):upper()
end

local function getBlockedPlates()
    if not Config.PoliceBlocks then return {} end
    local rows = MySQL.query.await(
        'SELECT `plate` FROM `police_vehicle_blocks` WHERE `active` = 1 AND (`until` IS NULL OR `until` > NOW())')
    local set = {}
    for _, r in ipairs(rows or {}) do set[plateKey(r.plate)] = true end
    return set
end

local function isPlateBlocked(plate)
    if not Config.PoliceBlocks then return false end
    local r = MySQL.scalar.await(
        'SELECT 1 FROM `police_vehicle_blocks` WHERE TRIM(`plate`) = TRIM(?) AND `active` = 1 AND (`until` IS NULL OR `until` > NOW()) LIMIT 1',
        { plate })
    return r ~= nil
end

local function canUseVehicle(source, row, grade)
    if not row.groupname then return true end
    local ug = tonumber(row.use_grade)
    if not ug or ug <= 0 then return true end
    if grade == nil then grade = Bridge.GetGroupGrade(source, row.groupname) end
    return grade ~= nil and grade >= ug
end

local function transferMinGrade(row)
    local tg = tonumber(row.transfer_grade)
    if tg ~= nil then return tg end
    return Bridge.GetMaxGrade(row.groupname)
end

lib.callback.register('m3_garages:getVehicles', function(source, garageId)
    local garage = getGarage(garageId)
    if not garage then return {} end

    local charId = Bridge.GetCharId(source)
    if not charId then return {} end

    local activeGroup = Bridge.GetActiveGroup(source)

    local rows
    if activeGroup then
        rows = MySQL.query.await(
            'SELECT * FROM `m3_garage_vehicles` WHERE `garage` = ? AND `impound` = 0 AND `stored` = 1 AND (`owner` = ? OR `groupname` = ?)',
            { garageId, charId, activeGroup }
        )
    else
        rows = MySQL.query.await(
            'SELECT * FROM `m3_garage_vehicles` WHERE `garage` = ? AND `impound` = 0 AND `stored` = 1 AND `owner` = ?',
            { garageId, charId }
        )
    end

    local blocked = getBlockedPlates()
    local myGrade = activeGroup and Bridge.GetGroupGrade(source, activeGroup) or nil

    local result = {}
    for _, row in ipairs(rows or {}) do
        if canUseVehicle(source, row, row.groupname == activeGroup and myGrade or nil) then
            local summary = buildSummary(row.props)
            result[#result + 1] = {
                id      = row.id,
                plate   = row.plate,
                vin     = row.vin,
                model   = row.model,
                stored  = isTrue(row.stored),
                blocked = blocked[plateKey(row.plate)] == true,
                owner   = row.groupname and Bridge.GetGroupLabel(row.groupname) or Bridge.GetCharName(row.owner),
                isGroup = row.groupname ~= nil,
                fuel    = summary.fuel,
                engine  = summary.engine,
                body    = summary.body,
                dirt    = summary.dirt,
            }
        end
    end
    return result
end)

local function canAccess(source, row)
    local charId = Bridge.GetCharId(source)
    if not charId then return false end
    if row.owner and row.owner == charId then return true end
    if row.groupname then
        local active = Bridge.GetActiveGroup(source)
        if active and active == row.groupname then return true end
    end
    return false
end

local function getSpawnPoints(obj)
    if obj.spawnPoints then return obj.spawnPoints end
    if obj.spawn then return { obj.spawn } end
    return {}
end

local function isSpotFree(coords, radius)
    radius = radius or 2.5
    local target = vec3(coords.x, coords.y, coords.z)
    for _, veh in ipairs(GetAllVehicles()) do
        if DoesEntityExist(veh) and #(GetEntityCoords(veh) - target) < radius then
            return false
        end
    end
    return true
end

local function pickFreeSpawn(points)
    if #points == 0 then return nil end
    for _, p in ipairs(points) do
        if isSpotFree(p) then return p end
    end
    return points[#points]
end

local function spawnVehicleServer(model, vtype, spawn)
    local vehicle = CreateVehicleServerSetter(model, vtype or Config.DefaultVehicleType, spawn.x, spawn.y, spawn.z, spawn.w)

    local timeout = 0
    while not DoesEntityExist(vehicle) and timeout < 100 do
        Wait(10)
        timeout += 1
    end
    if not DoesEntityExist(vehicle) then return nil end

    return NetworkGetNetworkIdFromEntity(vehicle)
end

lib.callback.register('m3_garages:takeOut', function(source, vehicleId, garageId, spawnIndex, label)
    local garage = getGarage(garageId)
    if not garage then return false end

    local row = MySQL.single.await('SELECT * FROM `m3_garage_vehicles` WHERE `id` = ?', { vehicleId })
    if not row then return false, 'Vehicle does not exist' end
    if not canAccess(source, row) then return false, 'This vehicle is not yours' end
    if not canUseVehicle(source, row) then return false, 'Your rank is too low to use this vehicle' end
    if isTrue(row.impound) then return false, 'This vehicle is in the impound' end
    if row.garage ~= garageId then return false, 'This vehicle is in another garage' end
    if not isTrue(row.stored) then return false, 'Vehicle is already out' end
    if isPlateBlocked(row.plate) then return false, 'Vehicle is blocked by police' end

    local points = getSpawnPoints(garage)
    local spawn = (spawnIndex and points[spawnIndex]) or pickFreeSpawn(points)
    if not spawn then return false, 'Garage has no spawn position' end

    local netId = spawnVehicleServer(row.model, row.vtype, spawn)
    if not netId then return false, 'Failed to spawn the vehicle' end

    MySQL.update.await('UPDATE `m3_garage_vehicles` SET `stored` = 0 WHERE `id` = ?', { vehicleId })

    local props = json.decode(row.props or '{}')

    if Config.FuelStatebag and props.fuelLevel then
        local ent = NetworkGetEntityFromNetworkId(netId)
        if ent and ent ~= 0 then
            Entity(ent).state:set(Config.FuelStatebag, props.fuelLevel + 0.0, true)
        end
    end

    giveVehicleKey(source, row.plate, label)

    return true, { netId = netId, props = props }
end)

lib.callback.register('m3_garages:store', function(source, props, garageId, netId)
    local garage = getGarage(garageId)
    if not garage then return false end
    if not props or not props.plate then return false, 'Invalid vehicle data' end

    local plate = props.plate:gsub('%s+$', '')
    local row = MySQL.single.await('SELECT * FROM `m3_garage_vehicles` WHERE `plate` = ?', { plate })
    if not row then return false, 'This vehicle is not registered in the garage system' end
    if not canAccess(source, row) then return false, 'This vehicle is not yours' end
    if isTrue(row.stored) then return false, 'Vehicle is already in the garage' end

    MySQL.update.await(
        'UPDATE `m3_garage_vehicles` SET `stored` = 1, `garage` = ?, `props` = ? WHERE `id` = ?',
        { garageId, json.encode(props), row.id }
    )

    if netId then
        removeVehicleEntity(NetworkGetEntityFromNetworkId(netId))
    end

    removeVehicleKey(source, plate)

    return true
end)

local function getCharGroups(charId)
    return MySQL.query.await('SELECT name, grade FROM `character_groups` WHERE `charId` = ?', { charId }) or {}
end

lib.callback.register('m3_garages:getTransferCategories', function(source)
    local charId = Bridge.GetCharId(source)
    if not charId then return {} end

    local activeGroup = Bridge.GetActiveGroup(source)
    return {
        hasGroup   = activeGroup ~= nil,
        groupName  = activeGroup,
        groupLabel = activeGroup and Bridge.GetGroupLabel(activeGroup) or nil,
    }
end)

lib.callback.register('m3_garages:getPlayerGroups', function(source)
    local charId = Bridge.GetCharId(source)
    if not charId then return {} end

    local result = {}
    for _, row in ipairs(getCharGroups(charId)) do
        result[#result + 1] = { name = row.name, label = Bridge.GetGroupLabel(row.name) }
    end
    return result
end)

lib.callback.register('m3_garages:getAllVehicles', function(source)
    local charId = Bridge.GetCharId(source)
    if not charId then return {} end

    local activeGroup = Bridge.GetActiveGroup(source)

    local rows
    if activeGroup then
        rows = MySQL.query.await(
            'SELECT * FROM `m3_garage_vehicles` WHERE `owner` = ? OR `groupname` = ?',
            { charId, activeGroup })
    else
        rows = MySQL.query.await('SELECT * FROM `m3_garage_vehicles` WHERE `owner` = ?', { charId })
    end

    local blocked = getBlockedPlates()
    local myGrade = activeGroup and Bridge.GetGroupGrade(source, activeGroup) or nil

    local result = {}
    for _, row in ipairs(rows or {}) do
        if canUseVehicle(source, row, row.groupname == activeGroup and myGrade or nil) then
            local status = isTrue(row.impound) and 'impound' or (isTrue(row.stored) and 'garage' or 'out')
            local g = getGarage(row.garage)
            result[#result + 1] = {
                id          = row.id,
                plate       = row.plate,
                vin         = row.vin,
                model       = row.model,
                vtype       = row.vtype,
                owner       = row.groupname and Bridge.GetGroupLabel(row.groupname) or Bridge.GetCharName(row.owner),
                isGroup     = row.groupname ~= nil,
                status      = status,
                blocked     = blocked[row.plate] == true,
                garage      = row.garage,
                garageLabel = g and g.label or row.garage,
                garageCoords = (g and g.npc) and { x = g.npc.coords.x + 0.0, y = g.npc.coords.y + 0.0 } or nil,
            }
        end
    end
    return result
end)

lib.callback.register('m3_garages:getTransferVehicles', function(source, category)
    local charId = Bridge.GetCharId(source)
    if not charId then return {} end

    if category == 'group' then
        local activeGroup = Bridge.GetActiveGroup(source)
        if not activeGroup then return {} end
        local rows = MySQL.query.await(
            'SELECT id, plate, vin, model, use_grade, transfer_grade FROM `m3_garage_vehicles` WHERE `groupname` = ?',
            { activeGroup }) or {}

        local myGrade = Bridge.GetGroupGrade(source, activeGroup) or 0
        local maxGrade = Bridge.GetMaxGrade(activeGroup)
        local canManage = myGrade >= maxGrade

        local result = {}
        for _, row in ipairs(rows) do
            local tmin = row.transfer_grade ~= nil and tonumber(row.transfer_grade) or maxGrade
            if myGrade >= tmin then
                result[#result + 1] = {
                    id = row.id, plate = row.plate, vin = row.vin, model = row.model,
                    isGroup = true,
                    canManage = canManage,
                    useGrade = row.use_grade,
                    transferGrade = row.transfer_grade,
                }
            end
        end
        return result
    end

    local rows = MySQL.query.await('SELECT id, plate, vin, model FROM `m3_garage_vehicles` WHERE `owner` = ?', { charId }) or {}
    local result = {}
    for _, row in ipairs(rows) do
        result[#result + 1] = { id = row.id, plate = row.plate, vin = row.vin, model = row.model, isGroup = false }
    end
    return result
end)

lib.callback.register('m3_garages:getGroupGrades', function(source)
    local activeGroup = Bridge.GetActiveGroup(source)
    if not activeGroup then return { grades = {} } end
    local myGrade = Bridge.GetGroupGrade(source, activeGroup) or 0
    local maxGrade = Bridge.GetMaxGrade(activeGroup)
    return {
        grades = Bridge.GetGroupGrades(activeGroup),
        myGrade = myGrade,
        maxGrade = maxGrade,
        canManage = myGrade >= maxGrade,
    }
end)

lib.callback.register('m3_garages:setVehicleAccess', function(source, vehicleId, kind, grade)
    local activeGroup = Bridge.GetActiveGroup(source)
    if not activeGroup then return false, 'You are not in any company' end

    local row = MySQL.single.await('SELECT id, groupname FROM `m3_garage_vehicles` WHERE `id` = ?', { vehicleId })
    if not row or row.groupname ~= activeGroup then return false, 'Invalid vehicle' end

    local myGrade = Bridge.GetGroupGrade(source, activeGroup) or 0
    if myGrade < Bridge.GetMaxGrade(activeGroup) then
        return false, 'Only the highest rank can change access'
    end

    grade = tonumber(grade)
    if kind == 'use' then
        MySQL.update.await('UPDATE `m3_garage_vehicles` SET `use_grade` = ? WHERE `id` = ?', { grade, vehicleId })
    elseif kind == 'transfer' then
        MySQL.update.await('UPDATE `m3_garage_vehicles` SET `transfer_grade` = ? WHERE `id` = ?', { grade, vehicleId })
    else
        return false, 'Invalid type'
    end
    return true
end)

lib.callback.register('m3_garages:transfer', function(source, vehicleId, targetType, targetValue)
    local charId = Bridge.GetCharId(source)
    if not charId then return false end

    local row = MySQL.single.await('SELECT * FROM `m3_garage_vehicles` WHERE `id` = ?', { vehicleId })
    if not row then return false, 'Vehicle does not exist' end
    if not canAccess(source, row) then return false, 'You cannot transfer this vehicle' end

    if row.groupname then
        local myGrade = Bridge.GetGroupGrade(source, row.groupname) or -1
        if myGrade < transferMinGrade(row) then
            return false, 'Your rank is too low to transfer this vehicle'
        end
    end

    local updateSql, params, targetSrc
    if targetType == 'person' then
        targetSrc = tonumber(targetValue)
        if not targetSrc then return false, 'Invalid player ID' end
        local targetChar = Bridge.GetCharId(targetSrc)
        if not targetChar then return false, 'Player is not online' end

        updateSql = 'UPDATE `m3_garage_vehicles` SET `owner` = ?, `ownername` = ?, `groupname` = NULL WHERE `id` = ?'
        params = { targetChar, Bridge.GetName(targetSrc), vehicleId }

    elseif targetType == 'group' then
        if not targetValue or targetValue == '' then return false, 'Missing company' end

        local member = false
        for _, g in ipairs(getCharGroups(charId)) do
            if g.name == targetValue then member = true break end
        end
        if not member then return false, 'You are not a member of this company' end

        updateSql = 'UPDATE `m3_garage_vehicles` SET `groupname` = ?, `owner` = NULL, `ownername` = NULL WHERE `id` = ?'
        params = { targetValue, vehicleId }
    else
        return false, 'Unknown transfer type'
    end

    local fee = Config.TransferFee or 0
    if fee > 0 then
        local money = exports.ox_inventory:Search(source, 'count', Config.MoneyItem) or 0
        if money < fee then
            return false, ('Not enough money to transfer (need $%d)'):format(fee)
        end
        if not exports.ox_inventory:RemoveItem(source, Config.MoneyItem, fee) then
            return false, 'Payment failed'
        end
    end

    MySQL.update.await(updateSql, params)

    if targetSrc then
        notify(targetSrc, ('Vehicle %s was transferred to you'):format(row.plate), 'success')
    end
    return true, { fee = fee }
end)

local function addVehicleToGarage(data)
    if type(data) ~= 'table' or not data.model then
        return nil, 'Missing model'
    end
    if not data.owner and not data.group then
        return nil, 'Provide owner (charId) or group'
    end

    local model = data.model
    if type(model) == 'string' then model = joaat(model) end

    local garageId = data.garage or Config.Garages[1].id
    if not getGarage(garageId) then return nil, 'Invalid garage: ' .. tostring(garageId) end

    local plate = data.plate and tostring(data.plate):gsub('%s+$', '')
    if not plate or plate == '' then
        plate = generatePlate()
    elseif MySQL.scalar.await('SELECT 1 FROM `m3_garage_vehicles` WHERE `plate` = ?', { plate }) then
        return nil, 'Plate already exists: ' .. plate
    end

    local vin = data.vin
    if not vin or MySQL.scalar.await('SELECT 1 FROM `m3_garage_vehicles` WHERE `vin` = ?', { vin }) then
        vin = generateVin()
    end

    local props = data.props or {}
    props.plate = plate
    props.model = model

    local stored = data.stored
    if stored == nil then stored = true end

    local ownername = data.owner and Bridge.GetCharName(data.owner) or nil

    local id = MySQL.insert.await(
        'INSERT INTO `m3_garage_vehicles` (plate, vin, model, vtype, owner, ownername, groupname, garage, stored, props) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)',
        { plate, vin, model, data.vtype or Config.DefaultVehicleType, data.owner, ownername, data.group, garageId, stored and 1 or 0, json.encode(props) }
    )

    return { id = id, plate = plate, vin = vin }
end

exports('AddVehicle', function(data)
    return addVehicleToGarage(data)
end)

RegisterCommand('addtogarage', function(source, args)
    if source == 0 then return end
    if not IsPlayerAceAllowed(source, Config.AdminAce) then
        notify(source, 'You do not have permission.', 'error')
        return
    end

    local garageId = args[1] or Config.Garages[1].id
    if not getGarage(garageId) then
        notify(source, 'Invalid garage: ' .. garageId, 'error')
        return
    end

    TriggerClientEvent('m3_garages:collectVehicle', source, garageId)
end, false)

RegisterNetEvent('m3_garages:saveCollected', function(garageId, props, netId)
    local source = source
    if not IsPlayerAceAllowed(source, Config.AdminAce) then return end
    if not props or not props.plate then
        notify(source, 'You are not in a vehicle.', 'error')
        return
    end

    local charId = Bridge.GetCharId(source)
    if not charId then return end

    local entity = netId and NetworkGetEntityFromNetworkId(netId)
    if not entity or entity == 0 or not DoesEntityExist(entity) then
        notify(source, 'You are not in a vehicle.', 'error')
        return
    end

    local plate = props.plate:gsub('%s+$', '')
    if MySQL.scalar.await('SELECT 1 FROM `m3_garage_vehicles` WHERE `plate` = ?', { plate }) then
        notify(source, 'A vehicle with this plate is already in the system.', 'error')
        return
    end

    local vtype = GetVehicleType(entity)
    local oxveh = exports.ox_core:GetVehicleFromEntity(entity)

    local result, err = addVehicleToGarage({
        model  = props.model,
        plate  = plate,
        vin    = oxveh and oxveh.vin or nil,
        owner  = charId,
        garage = garageId,
        vtype  = (vtype ~= '' and vtype) or nil,
        props  = props,
        stored = false,
    })

    if not result then
        notify(source, err or 'Failed to add vehicle', 'error')
        return
    end

    notify(source, ('Vehicle %s registered to garage (%s). It stays with you.'):format(result.plate, garageId), 'success')
end)

local function isTowGroup(group)
    if not group then return false end
    for _, g in ipairs(Config.TowGroups) do
        if g == group then return true end
    end
    return false
end

local function getImpounds()
    return Config.Impounds or (Config.Impound and { Config.Impound }) or {}
end

lib.callback.register('m3_garages:isTowAllowed', function(source)
    return isTowGroup(Bridge.GetActiveGroup(source))
end)

lib.callback.register('m3_garages:tow', function(source, netId)
    if not isTowGroup(Bridge.GetActiveGroup(source)) then
        return false, 'You do not have permission'
    end

    local entity = NetworkGetEntityFromNetworkId(netId)
    if not entity or entity == 0 or not DoesEntityExist(entity) then
        return false, 'Vehicle does not exist'
    end

    local plate = GetVehicleNumberPlateText(entity)
    if plate then plate = plate:gsub('%s+$', '') end

    if plate and plate ~= '' then
        local row = MySQL.single.await('SELECT id FROM `m3_garage_vehicles` WHERE `plate` = ?', { plate })
        if row then
            MySQL.update.await('UPDATE `m3_garage_vehicles` SET `impound` = 1, `stored` = 1 WHERE `id` = ?', { row.id })
        end
    end

    removeVehicleEntity(entity)
    notify(source, 'Vehicle towed to the impound.', 'success')
    return true
end)

lib.callback.register('m3_garages:getImpound', function(source)
    local charId = Bridge.GetCharId(source)
    if not charId then return {} end

    local activeGroup = Bridge.GetActiveGroup(source)

    local rows
    if activeGroup then
        rows = MySQL.query.await(
            'SELECT * FROM `m3_garage_vehicles` WHERE `impound` = 1 AND (`owner` = ? OR `groupname` = ?)',
            { charId, activeGroup })
    else
        rows = MySQL.query.await(
            'SELECT * FROM `m3_garage_vehicles` WHERE `impound` = 1 AND `owner` = ?', { charId })
    end

    local result = {}
    for _, row in ipairs(rows or {}) do
        local summary = buildSummary(row.props)
        result[#result + 1] = {
            id      = row.id,
            plate   = row.plate,
            vin     = row.vin,
            model   = row.model,
            owner   = row.groupname and Bridge.GetGroupLabel(row.groupname) or Bridge.GetCharName(row.owner),
            isGroup = row.groupname ~= nil,
            fuel    = summary.fuel,
            engine  = summary.engine,
            body    = summary.body,
            dirt    = summary.dirt,
            fee     = Config.ImpoundFee,
        }
    end
    return result
end)

lib.callback.register('m3_garages:impoundRetrieve', function(source, vehicleId, impoundIndex, spawnIndex, label)
    local impound = getImpounds()[impoundIndex]
    if not impound then return false, 'Invalid impound' end

    local row = MySQL.single.await('SELECT * FROM `m3_garage_vehicles` WHERE `id` = ?', { vehicleId })
    if not row then return false, 'Vehicle does not exist' end
    if not isTrue(row.impound) then return false, 'Vehicle is not in the impound' end
    if not canAccess(source, row) then return false, 'This vehicle is not yours' end
    if isPlateBlocked(row.plate) then return false, 'Vehicle is blocked by police' end

    local fee = Config.ImpoundFee
    local money = exports.ox_inventory:Search(source, 'count', Config.MoneyItem) or 0
    if money < fee then
        return false, ('Not enough money (need $%d)'):format(fee)
    end

    local points = getSpawnPoints(impound)
    local spawn = (spawnIndex and points[spawnIndex]) or pickFreeSpawn(points)
    if not spawn then return false, 'Impound has no spawn position' end

    local netId = spawnVehicleServer(row.model, row.vtype, spawn)
    if not netId then return false, 'Failed to spawn the vehicle' end

    if not exports.ox_inventory:RemoveItem(source, Config.MoneyItem, fee) then
        local ent = NetworkGetEntityFromNetworkId(netId)
        if ent and ent ~= 0 then DeleteEntity(ent) end
        return false, 'Payment failed'
    end

    MySQL.update.await('UPDATE `m3_garage_vehicles` SET `impound` = 0, `stored` = 0 WHERE `id` = ?', { vehicleId })

    local props = json.decode(row.props or '{}')
    if Config.FuelStatebag and props.fuelLevel then
        local ent = NetworkGetEntityFromNetworkId(netId)
        if ent and ent ~= 0 then
            Entity(ent).state:set(Config.FuelStatebag, props.fuelLevel + 0.0, true)
        end
    end

    giveVehicleKey(source, row.plate, label)

    return true, { netId = netId, props = props, fee = fee }
end)

AddEventHandler('onResourceStart', function(res)
    if res ~= GetCurrentResourceName() then return end
    MySQL.update.await(
        'UPDATE `m3_garage_vehicles` SET `impound` = 1, `stored` = 1 WHERE `stored` = 0 AND `impound` = 0')
end)
