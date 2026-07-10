fx_version 'cerulean'
game 'gta5'

author 'm3sk1'
description 'm3_garages - garage system for ox_core'
version '1.0.0'

lua54 'yes'

shared_script '@ox_lib/init.lua'
shared_script 'config.lua'

client_script 'client/main.lua'

server_scripts {
    '@oxmysql/lib/MySQL.lua',
    'server/bridge.lua',
    'server/main.lua'
}

dependencies {
    'ox_lib',
    'ox_target',
    'oxmysql',
    'ox_core',
    'ox_inventory'
}
