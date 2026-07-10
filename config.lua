Config = {}

-- ACE permission required for /addtogarage.
Config.AdminAce = 'm3garages.admin'

Config.StoreKey = 'G'

-- Statebag key your fuel script reads (ox_fuel / LegacyFuel use 'fuel').
Config.FuelStatebag = 'ox_fuel'

-- If you are using m3_police then you can use feature for blocking vehicles by pd,
-- set this to true to prevent players from storing vehicles that are blocked.
Config.PoliceBlocks = true

Config.DefaultVehicleType = 'automobile'

Config.Keys = {
    enable     = true,
    item       = 'vehiclekey',
    lockKey    = 'K',
    lockRadius = 5.0,
}


Config.MoneyItem  = 'money'
Config.ImpoundFee = 500

Config.ImpoundBlipName = 'Impound'

Config.TransferFee = 250

Config.TowGroups = { 'police' }

Config.TowDuration = 6000

Config.Impounds = {
    {
        label = 'Impound - Mission Row',
        npc = {
            model = `csb_trafficwarden`,
            coords = vec4(409.8, -1622.5, 29.3, 230.0),
            scenario = 'WORLD_HUMAN_CLIPBOARD',
        },
        spawn = vec4(402.8622, -1631.9872, 29.2919, 316.8068),
        blip = { enable = true, sprite = 68, color = 5, scale = 0.8 },
    },
    {
        label = 'Impound - Sandy Shores',
        npc = {
            model = `csb_trafficwarden`,
            coords = vec4(1736.0, 3710.0, 34.2, 200.0),
            scenario = 'WORLD_HUMAN_CLIPBOARD',
        },
        spawnPoints = {
            vec4(1730.0, 3713.0, 34.2, 28.0),
            vec4(1733.0, 3715.0, 34.2, 28.0),
        },
        blip = { enable = true, sprite = 68, color = 5, scale = 0.8 },
    },
}


Config.Garages = {
    {
        id = '6520',
        label = 'Garage 6520',
        npc = {
            model = `csb_trafficwarden`,
            coords = vec4(215.8, -810.2, 30.7, 250.0),
            scenario = 'WORLD_HUMAN_CLIPBOARD',
        },
        spawnPoints = {
            vec4(222.0, -800.0, 30.5, 160.0),
            vec4(225.0, -802.0, 30.5, 160.0),
            vec4(228.0, -804.0, 30.5, 160.0),
        },
        storePoints = {
            vec4(222.0, -800.0, 30.5, 160.0),
            vec4(225.0, -802.0, 30.5, 160.0),
        },
        storeRadius = 6.0,
    },

    {
        id = '8239',
        label = 'Garage 8239',
        npc = {
            model = `csb_trafficwarden`,
            coords = vec4(-734.6374, -1315.8342, 5.0004, 45.9415),
            scenario = 'WORLD_HUMAN_CLIPBOARD',
        },
        spawnPoints = {
            vec4(-727.0486, -1326.3807, -0.4748, 245.6639),
            vec4(-732.5107, -1333.9607, -0.4738, 228.7296),
        },
        storePoints = {
            vec4(-727.0486, -1326.3807, -0.4748, 245.6639),
            vec4(-732.5107, -1333.9607, -0.4738, 228.7296),
        },
        storeRadius = 6.0,
    },

    {
        id = '10012',
        label = 'Garage 10012',
        npc = {
            model = `csb_trafficwarden`,
            coords = vec4(-991.6729, -2949.1997, 13.9451, 234.6126),
            scenario = 'WORLD_HUMAN_CLIPBOARD',
        },
        spawnPoints = {
            vec4(-965.9755, -2983.1831, 13.9451, 64.1007),
        },
        storePoints = {
            vec4(-965.9755, -2983.1831, 13.9451, 64.1007),
        },
        storeRadius = 10.0,
    },

    {
        id = '8090',
        label = 'Garage 8090',
        npc = {
            model = `csb_trafficwarden`,
            coords = vec4(-1096.0159, -847.7455, 5.2248, 32.4340),
            scenario = 'WORLD_HUMAN_CLIPBOARD',
        },
        spawnPoints = {
            vec4(-1102.2625, -835.9672, 5.0615, 221.3794),
            vec4(-1099.3698, -834.1326, 5.0615, 209.3479),
            vec4(-1096.6742, -831.7689, 5.0615, 206.7162),
        },
        storePoints = {
            vec4(-1102.2625, -835.9672, 5.0615, 221.3794),
            vec4(-1099.3698, -834.1326, 5.0615, 209.3479),
            vec4(-1096.6742, -831.7689, 5.0615, 206.7162),
        },
        storeRadius = 2.0,
    },
}

Config.TransferPoints = {
    {
        npc = {
            model = `csb_trafficwarden`,
            coords = vec4(-545.0, -204.0, 38.2, 200.0),
            scenario = 'WORLD_HUMAN_CLIPBOARD',
        },
        blip = { enable = true, sprite = 524, color = 5, scale = 0.7, label = 'Vehicle registration' },
    },
}
