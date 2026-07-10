# m3_garages

A complete **garage system for ox_core** — NPC garages, personal & company vehicles, company grade permissions, a transfer office, a police impound/tow system, vehicle keys, and a developer export to register vehicles from your own scripts (dealerships, car shops, admin tools, etc.).

Everything is server-authoritative and stored in one database table.

---

## Features

- **NPC garages** (ox_target) with a clean `ox_lib` menu listing the player's vehicles (fuel / engine / body / dirt shown per vehicle)
- **Store by key** — drive into a garage's store zone and press a key (default `G`) to park
- **Personal & company vehicles** — a vehicle belongs to a person (`owner`) or a company (`groupname`, shown with the group label). Company vehicles are visible to members with that group set active (on-duty)
- **Company grade permissions** — the highest-rank member can set, per company vehicle, which grade can **use** it and which grade can **transfer** it (grade names come from `ox_group_grades`). Members without access don't see the vehicle anywhere
- **Transfer office** — transfer a vehicle to a nearby player or to one of your companies, with an optional fee
- **Police impound / tow** — authorized groups can tow vehicles; owners retrieve them from any impound for a fee. Multiple impounds supported (shared pool)
- **Vehicle keys** — take a car out and receive a key named after the car; lock/unlock the nearest car via keybind or item use; hand keys to other players; parking removes the key (never required to park)
- **Free-spot spawning** — take-out picks the first free exit (checks vehicles **and** objects); if all are blocked the player is told instead of spawning inside another car
- **Fuel & damage persistence** — saved via `ox_lib` properties + a configurable fuel statebag so fuel scripts don't overwrite it
- **Unique plate & VIN** per vehicle
- **Developer export** to register vehicles from any resource (see below)
- Optional **m3_police** integration (block a vehicle so it can't be taken out)

---

## Preview

- TODO

---

## Dependencies

- [ox_core](https://github.com/communityox/ox_core)
- [ox_lib](https://github.com/communityox/ox_lib)
- [ox_target](https://github.com/communityox/ox_target)
- [ox_inventory](https://github.com/communityox/ox_inventory)
- [oxmysql](https://github.com/communityox/oxmysql)

---

## Installation

1. Import `sql/m3_garages.sql` into your database.
2. Drop `m3_garages` into your `resources` folder.
3. Add the **vehicle key item** to `ox_inventory/data/items.lua`.
4. Grant the admin ACE for `/addtogarage` in `server.cfg`:
   ```cfg
   add_ace group.admin m3garages.admin allow
   ```
5. Ensure it **after** its dependencies in `server.cfg`:
   ```cfg
   ensure ox_lib
   ensure oxmysql
   ensure ox_core
   ensure ox_target
   ensure ox_inventory
   ensure m3_garages
   ```
6. Configure garages, impounds and the transfer office in `config.lua`, then restart.

---

## Configuration

Everything is in `config.lua`. Highlights:

| Option | Description |
| --- | --- |
| `Config.AdminAce` | ACE required for `/addtogarage`. |
| `Config.StoreKey` | Key to park. |
| `Config.FuelStatebag` | Statebag your fuel script uses (`'fuel'` for ox_fuel/LegacyFuel), or `false`. |
| `Config.PoliceBlocks` | Enable m3_police blocking. Set `false` if you don't run m3_police. |
| `Config.Keys` | Vehicle key item, lock key and lock radius. |
| `Config.MoneyItem` / `Config.ImpoundFee` / `Config.TransferFee` | Payment item and fees. |
| `Config.TowGroups` / `Config.TowDuration` | Groups allowed to tow and tow progress time. |
| `Config.Garages` / `Config.Impounds` / `Config.TransferPoints` | Locations (NPC + spawn/store points). |

---

## Usage

- Interact with a **garage NPC** → open your vehicle list → select a car to take it out.
- Drive into a garage store zone and press **`G`** to park.
- Interact with the **transfer NPC** → choose personal/company → pick a vehicle → transfer to a person or company.
- Police (or `Config.TowGroups`) can target any vehicle → **Tow vehicle**; owners retrieve it at an impound NPC.
- **`/addtogarage`** (admin) — registers the vehicle you are currently sitting in to your character.

### Vehicle keys

- On take-out the player receives a key.
- **Use** the key (or press the lock key, default `K`) to lock/unlock the nearest car, if the player holds a key for it.

Add the item to `ox_inventory/data/items.lua`:

```lua
['vehiclekey'] = {
    label = 'Vehicle key',
    weight = 0,
    stack = false,
    close = true,
    consume = 0,
    client = { export = 'm3_garages.useKey' },
    },
},
```

---

## Developer API — add a vehicle to a garage

Use this to register a vehicle into a player's (or company's) garage from **any resource** — car dealerships, car shops, reward systems, admin menus, etc. This is the only supported way to inject a vehicle into the system (random/unregistered vehicles cannot be parked).

**Server-side export:**

```lua
local result, err = exports.m3_garages:AddVehicle(data)
```

**`data` fields:**

| Field | Type | Required | Description |
| --- | --- | --- | --- |
| `model` | `string \| number` | ✅ | Model name (`'sultan'`) or hash. |
| `owner` | `number` | owner **or** group | ox_core `charId` of the personal owner. |
| `group` | `string` | owner **or** group | ox_core group name for a company vehicle. |
| `plate` | `string` | ➖ | Custom plate. Auto-generated & unique if omitted. |
| `vin` | `string` | ➖ | Custom VIN. Auto-generated & unique if omitted. |
| `garage` | `string` | ➖ | Garage id (default: first garage in config). |
| `vtype` | `string` | ➖ | `automobile` / `bike` / `boat` / `heli` / `plane` … (default `automobile`). |
| `props` | `table` | ➖ | `ox_lib` vehicle properties (mods/colors). Plate/model are enforced automatically. |
| `stored` | `boolean` | ➖ | `true` (default) = ready in the garage; `false` = registered but stays out. |

**Returns:** `{ id = number, plate = string, vin = string }` on success, or `nil, errorMessage` on failure.

### Example — dealership / car shop

```lua
-- server side, after the player pays
local charId = exports.ox_core:GetPlayer(source)?.charId

local result, err = exports.m3_garages:AddVehicle({
    model  = 'sultan',
    owner  = charId,
    garage = 'main',       -- optional
    stored = true,         -- goes straight into the garage
    -- vtype = 'automobile',
    -- plate = 'MYSHOP01',
    -- props = { color1 = 12, color2 = 0 },
})

if not result then
    print('AddVehicle failed:', err)
    return
end

-- result.plate / result.vin / result.id are now registered
```

### Example — company (fleet) vehicle

```lua
exports.m3_garages:AddVehicle({
    model = 'police',
    group = 'police',      -- company vehicle instead of owner
    garage = 'main',
})
```

> After registration the vehicle appears in the owner's (or active company members') garage list and can be taken out normally. To spawn it into the world immediately instead, register it with `stored = false` and spawn/handle the entity yourself.

---

## Support

Found a bug or have a request? Open an issue or reply in the release thread.

## License

Released under the MIT License — free to use and modify.
