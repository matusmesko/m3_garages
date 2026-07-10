Bridge = {}

local function getPlayer(source)
    return exports.ox_core:GetPlayer(source)
end

function Bridge.GetCharId(source)
    local player = getPlayer(source)
    if not player then return nil end
    return player.charId
end

function Bridge.GetName(source)
    local player = getPlayer(source)
    if not player then return 'Unknown' end

    local name = player.get and player.get('name')
    if name and name ~= '' then return name end

    local first = (player.get and player.get('firstName')) or player.firstName
    local last  = (player.get and player.get('lastName')) or player.lastName
    if first or last then
        return (('%s %s'):format(first or '', last or '')):gsub('^%s+', ''):gsub('%s+$', '')
    end

    return Bridge.GetCharName(player.charId)
end

function Bridge.GetCharName(charId)
    if not charId then return 'Unknown' end
    local row = MySQL.single.await('SELECT fullName FROM `characters` WHERE `charId` = ?', { charId })
    return (row and row.fullName) or ('#' .. charId)
end

function Bridge.GetGroups(source)
    local player = getPlayer(source)
    if not player then return {} end

    if player.getGroups then
        return player.getGroups() or {}
    end
    if player.get then
        return player.get('groups') or {}
    end
    return {}
end

function Bridge.GetActiveGroup(source)
    local charId = Bridge.GetCharId(source)
    if not charId then return nil end

    local row = MySQL.single.await(
        'SELECT name FROM `character_groups` WHERE `charId` = ? AND `isActive` = 1 LIMIT 1', { charId })
    return row and row.name or nil
end

function Bridge.HasGroup(source, groupName)
    return Bridge.GetGroups(source)[groupName] ~= nil
end

function Bridge.GetGroupGrade(source, groupName)
    if not groupName then return nil end
    local charId = Bridge.GetCharId(source)
    if not charId then return nil end
    return MySQL.scalar.await(
        'SELECT `grade` FROM `character_groups` WHERE `charId` = ? AND `name` = ? LIMIT 1',
        { charId, groupName })
end

function Bridge.GetGroupGrades(groupName)
    if not groupName then return {} end
    return MySQL.query.await(
        'SELECT `grade`, `label` FROM `ox_group_grades` WHERE `group` = ? ORDER BY `grade` ASC', { groupName }) or {}
end

function Bridge.GetMaxGrade(groupName)
    if not groupName then return 0 end
    return MySQL.scalar.await('SELECT MAX(`grade`) FROM `ox_group_grades` WHERE `group` = ?', { groupName }) or 0
end

local groupLabelCache = {}
function Bridge.GetGroupLabel(name)
    if not name then return nil end
    if groupLabelCache[name] ~= nil then return groupLabelCache[name] end

    local row = MySQL.single.await('SELECT label FROM `ox_groups` WHERE `name` = ?', { name })
    local label = (row and row.label) or name
    groupLabelCache[name] = label
    return label
end

return Bridge
