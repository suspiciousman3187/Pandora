_addon.name     = 'Pandora'
_addon.author   = 'A Man In Black'
_addon.version  = '1.0'
_addon.commands = {'pandora', 'pd'}

local packets = require('packets')
local res     = require('resources')

local ODYSSEY_ZONE_IDS = { [298] = true, [279] = true }

local POKE_MAX_RETRY   = 10
local POKE_RETRY_INT   = 2.0
local POKE_HARD_TIMEOUT = 25
local SCAN_TIMEOUT     = 2.0
local LOOT_DELAY       = 3.0

local STATE_IDLE  = 'IDLE'
local STATE_SPOOF = 'SPOOF'
local STATE_POKE  = 'POKE'

local state            = STATE_IDLE
local spoof_count      = 0
local spoof_x, spoof_y, spoof_z = 0, 0, 0
local target_id        = 0
local target_index     = 0
local target_name      = '?'
local poke_time        = 0
local poke_retry_count = 0
local warp_t0          = 0

local loot_queue = {}
local loot_count = 0
local loot_wave  = 0
local LOOT_WAVES = {}
local loot_party_mode = false

local loot_scan = {
    active        = false,
    indices       = {},
    pos           = 0,
    found         = {},
    callback      = nil,
    last_req_idx  = 0,
    last_req_time = 0,
}

local SORTIE_CHEST_IDS = {

    [21000193] = 'Chest A1', [21000194] = 'Chest B1', [21000195] = 'Chest C1', [21000196] = 'Chest D1',
    [21000197] = 'Chest A2', [21000198] = 'Chest B2', [21000199] = 'Chest C2', [21000200] = 'Chest D2',
    [21000201] = 'Chest A5', [21000202] = 'Chest B5', [21000203] = 'Chest C5', [21000204] = 'Chest D5',
    [21000205] = 'Chest A3', [21000206] = 'Chest B3', [21000207] = 'Chest C3', [21000208] = 'Chest D3',
    [21000209] = 'Chest A4', [21000210] = 'Chest B4', [21000211] = 'Chest C4', [21000212] = 'Chest D4',
    [21000213] = 'Chest E',  [21000214] = 'Chest F',  [21000215] = 'Chest G',  [21000216] = 'Chest H',
    [21000217] = 'Chest ?',

    [21000218] = 'Casket A1', [21000219] = 'Casket A2', [21000220] = 'Coffer A',
    [21000221] = 'Casket B1', [21000222] = 'Casket B2', [21000223] = 'Coffer B',
    [21000224] = 'Casket C1', [21000225] = 'Casket C2', [21000226] = 'Coffer C',
    [21000227] = 'Casket D1', [21000228] = 'Casket D2', [21000229] = 'Coffer D',
    [21000230] = 'Aurum Ground',

    [21000231] = 'Casket E1', [21000232] = 'Casket E2', [21000233] = 'Coffer E',
    [21000234] = 'Casket F1', [21000235] = 'Casket F2', [21000236] = 'Coffer F',
    [21000237] = 'Casket G1', [21000238] = 'Casket G2', [21000239] = 'Coffer G',

    [21000240] = 'Casket H1', [21000241] = 'Casket H2', [21000242] = 'Coffer H',
    [21000243] = 'Aurum Basement',
}

local sortie_ao_enabled = false
local SORTIE_AO_RANGE    = 50
local SORTIE_AO_SETTLE   = 2.0
local SORTIE_AO_RETRY_COOLDOWN = 2.0
local SORTIE_AO_SUCCESS_GAP    = 0.3
local SORTIE_AO_SPOOF_TIMEOUT  = 5.0
local sortie_opened     = {}
local sortie_first_seen = {}
local sortie_unknown    = {}
local sortie_cooldown_until = 0
local sortie_spoof_started  = 0

local AO_IDLE  = 'AO_IDLE'
local AO_SPOOF = 'AO_SPOOF'
local ao_state       = AO_IDLE
local ao_spoof_count = 0
local ao_spoof_x, ao_spoof_y, ao_spoof_z = 0, 0, 0
local ao_target_id    = 0
local ao_target_idx   = 0
local ao_target_label = '?'

local function floor_table(base, floors)
    local t = {}
    for f = 1, floors do
        local b = base + (f - 1) * 3
        t[f] = { b, b + 1, b + 2 }
    end
    return t
end

local SHEOL = {
    a = {
        name = 'Sheol A', floors = 7,
        chests      = floor_table(588, 7),
        coffers     = floor_table(609, 7),
        strongboxes = floor_table(630, 7),
    },
    b = {
        name = 'Sheol B', floors = 6,
        chests      = floor_table(688, 6),
        coffers     = floor_table(706, 6),
        strongboxes = floor_table(724, 6),
    },
    c = {
        name = 'Sheol C', floors = 4,
        chests      = floor_table(578, 4),
        coffers     = floor_table(590, 4),
        strongboxes = floor_table(602, 4),
    },
}

local function get_waves(sheol, floor)
    local s = SHEOL[sheol]
    return {
        { name = s.name..' Chests F'..floor,      indices = s.chests[floor]      or {} },
        { name = s.name..' Coffers F'..floor,     indices = s.coffers[floor]     or {} },
        { name = s.name..' Strongboxes F'..floor, indices = s.strongboxes[floor] or {} },
    }
end

local function chat(msg)
    windower.add_to_chat(207, '[Pandora] ' .. msg)
end

local function err(msg)
    windower.add_to_chat(167, '[Pandora] ' .. msg)
end

local function reset()
    state            = STATE_IDLE
    spoof_count      = 0
    target_id        = 0
    target_index     = 0
    target_name      = '?'
    poke_time        = 0
    poke_retry_count = 0
end

local function stop_loot(reason)
    reset()
    loot_queue       = {}
    loot_count       = 0
    loot_wave        = 0
    loot_party_mode  = false
    loot_scan.active = false
    loot_scan.callback = nil
    if reason then chat(reason) end
end

local function in_odyssey()
    return ODYSSEY_ZONE_IDS[windower.ffxi.get_info().zone] == true
end

local function in_sortie()
    local zid = windower.ffxi.get_info().zone
    local zn = (res.zones[zid] and res.zones[zid].en) or ''
    return zn:lower():find("ra'kaznar") ~= nil
end

local function sortie_ao_reset()
    ao_state            = AO_IDLE
    ao_spoof_count      = 0
    sortie_opened       = {}
    sortie_first_seen   = {}
    sortie_unknown      = {}
    sortie_cooldown_until = 0
    sortie_spoof_started  = 0
end

local function settings_path()
    local p = windower.ffxi.get_player()
    if not p or not p.name or p.name == '' then return nil end
    return windower.addon_path .. 'data/' .. p.name .. '_settings.lua'
end

local function save_settings()
    local path = settings_path()
    if not path then return end
    local f = io.open(path, 'w')
    if not f then return end
    f:write(('return {\n  sortie_ao_enabled = %s,\n  sortie_ao_range = %d,\n}\n'):format(
        tostring(sortie_ao_enabled), SORTIE_AO_RANGE))
    f:close()
end

local function load_settings()
    local path = settings_path()
    if not path then return end
    local f = io.open(path, 'r')
    if not f then return end
    f:close()
    local ok, data = pcall(dofile, path)
    if not ok or type(data) ~= 'table' then return end
    if type(data.sortie_ao_enabled) == 'boolean' then
        sortie_ao_enabled = data.sortie_ao_enabled
    end
    if type(data.sortie_ao_range) == 'number' and data.sortie_ao_range > 0 and data.sortie_ao_range <= 100 then
        SORTIE_AO_RANGE = data.sortie_ao_range
    end
    chat(('Loaded settings for %s: sortie=%s range=%dy'):format(
        windower.ffxi.get_player().name, tostring(sortie_ao_enabled), SORTIE_AO_RANGE))
end

local function begin_open(index, npc_id, npc_x, npc_y, npc_z, name)
    target_index = index
    target_id    = npc_id
    target_name  = name or '?'
    spoof_x, spoof_y, spoof_z = npc_x, npc_y, npc_z
    spoof_count      = 0
    poke_time        = 0
    poke_retry_count = 0
    warp_t0          = os.clock()
    state            = STATE_SPOOF
end

local function loot_scan_next()
    if not loot_scan.active then return end

    if loot_scan.last_req_idx > 0 then
        local npc = windower.ffxi.get_mob_by_index(loot_scan.last_req_idx)
        if npc and (npc.x ~= 0 or npc.y ~= 0 or npc.z ~= 0) then
            loot_scan.found[#loot_scan.found + 1] = { index = npc.index, npc = npc.id }
        end
    end
    loot_scan.pos = loot_scan.pos + 1
    if loot_scan.pos > #loot_scan.indices then
        loot_scan.active = false
        chat(('Scan complete: %d found of %d.'):format(#loot_scan.found, #loot_scan.indices))
        local cb = loot_scan.callback
        loot_scan.callback = nil
        if cb then cb(loot_scan.found) end
        return
    end
    local idx = loot_scan.indices[loot_scan.pos]
    local req = packets.new('outgoing', 0x016)
    req['Target Index'] = idx
    packets.inject(req)
    loot_scan.last_req_idx  = idx
    loot_scan.last_req_time = os.clock()
end

local function start_loot_scan(indices, callback)
    loot_scan.active        = true
    loot_scan.indices       = indices
    loot_scan.pos           = 0
    loot_scan.found         = {}
    loot_scan.callback      = callback
    loot_scan.last_req_idx  = 0
    loot_scan.last_req_time = 0
    loot_scan_next()
end

local start_loot_wave
local process_next_loot

start_loot_wave = function(wave_num)
    if wave_num > #LOOT_WAVES then
        chat(('Loot complete - opened %d container(s).'):format(loot_count))
        loot_wave  = 0
        loot_count = 0
        return
    end
    loot_wave = wave_num
    local wave = LOOT_WAVES[wave_num]
    chat(('Wave %d (%s): scanning %d indices...'):format(wave_num, wave.name, #wave.indices))
    start_loot_scan(wave.indices, function(found)
        if loot_wave == 0 then return end
        loot_queue = found
        if #loot_queue == 0 then
            chat(('Wave %d: none found - advancing.'):format(wave_num))
            start_loot_wave(wave_num + 1)
        else
            chat(('Wave %d: found %d - opening...'):format(wave_num, #loot_queue))
            process_next_loot()
        end
    end)
end

process_next_loot = function()
    if loot_wave == 0 then return end
    if #loot_queue == 0 then
        if loot_party_mode then
            chat(('My loot done - opened %d container(s).'):format(loot_count))
            loot_wave = 0
            loot_party_mode = false
            return
        end
        chat(('Wave %d done. Scanning for upgrades...'):format(loot_wave))
        start_loot_wave(loot_wave + 1)
        return
    end
    local entry = loot_queue[1]

    local req = packets.new('outgoing', 0x016)
    req['Target Index'] = entry.index
    packets.inject(req)
    coroutine.schedule(function()
        if loot_wave == 0 then return end
        local npc = windower.ffxi.get_mob_by_index(entry.index)
        table.remove(loot_queue, 1)
        if not npc or (npc.x == 0 and npc.y == 0 and npc.z == 0) then
            coroutine.schedule(process_next_loot, 0.5)
            return
        end
        chat(('Opening %s (index=%d) [%d left in wave]...'):format(
            npc.name or '?', entry.index, #loot_queue))
        begin_open(entry.index, npc.id, npc.x, npc.y, npc.z, npc.name)
    end, 2.0)
end

local function sortie_ao_start(mob)
    ao_target_id    = mob.id
    ao_target_idx   = mob.index
    ao_target_label = SORTIE_CHEST_IDS[mob.id] or '?'
    ao_spoof_x, ao_spoof_y, ao_spoof_z = mob.x, mob.y, mob.z
    ao_spoof_count       = 0
    ao_state             = AO_SPOOF
    sortie_spoof_started = os.clock()
    sortie_cooldown_until = sortie_spoof_started + SORTIE_AO_RETRY_COOLDOWN
    local req = packets.new('outgoing', 0x016)
    req['Target Index'] = mob.index
    packets.inject(req)
    chat(('Sortie: auto-opening %s (idx=%d)'):format(ao_target_label, mob.index))
end

local function find_nearby_sortie_chest()
    local me = windower.ffxi.get_mob_by_target('me')
    if not me then return nil end
    local mobs = windower.ffxi.get_mob_array()
    if not mobs then return nil end
    local now = os.clock()
    for _, mob in pairs(mobs) do
        if mob and mob.id and mob.x and (mob.x ~= 0 or mob.y ~= 0 or mob.z ~= 0) then
            local dx, dy, dz = mob.x - me.x, mob.y - me.y, mob.z - me.z
            local dist = math.sqrt(dx*dx + dy*dy + dz*dz)
            if dist <= SORTIE_AO_RANGE then
                if SORTIE_CHEST_IDS[mob.id] then
                    if not sortie_opened[mob.id] then
                        if not sortie_first_seen[mob.id] then sortie_first_seen[mob.id] = now end
                        if (now - sortie_first_seen[mob.id]) >= SORTIE_AO_SETTLE then
                            return mob
                        end
                    end
                elseif mob.id >= 21000180 and mob.id <= 21000260 and not sortie_unknown[mob.id] then

                    sortie_unknown[mob.id] = true
                    err(('Unmapped chest-range NPC: id=%d name=%s idx=%d -- add to SORTIE_CHEST_IDS'):format(
                        mob.id, mob.name or '?', mob.index or 0))
                end
            end
        end
    end
    return nil
end

windower.register_event('outgoing chunk', function(id, data, modified, injected, blocked)
    if id ~= 0x015 then return end

    if ao_state == AO_SPOOF then
        local p = packets.parse('outgoing', data)
        if not p then return end
        p['X'], p['Y'], p['Z'] = ao_spoof_x, ao_spoof_y, ao_spoof_z
        ao_spoof_count = ao_spoof_count + 1
        if ao_spoof_count >= 2 then
            local poke = packets.new('outgoing', 0x01A)
            poke['Target']       = ao_target_id
            poke['Target Index'] = ao_target_idx
            poke['Category']     = 0x00
            poke['Param']        = 0
            packets.inject(poke)
            sortie_opened[ao_target_id] = true
            ao_state = AO_IDLE
            ao_spoof_count = 0
            sortie_cooldown_until = os.clock() + SORTIE_AO_SUCCESS_GAP
            chat(('Sortie: poked %s.'):format(ao_target_label))
        end
        return packets.build(p)
    end

    if state == STATE_IDLE then return end
    local p = packets.parse('outgoing', data)
    if not p then return end
    p['X'] = spoof_x
    p['Y'] = spoof_y
    p['Z'] = spoof_z
    if state == STATE_SPOOF then
        spoof_count = spoof_count + 1
        if spoof_count >= 2 then
            state     = STATE_POKE
            poke_time = os.clock()

            local req = packets.new('outgoing', 0x016)
            req['Target Index'] = target_index
            packets.inject(req)
            local poke = packets.new('outgoing', 0x01A)
            poke['Target']       = target_id
            poke['Target Index'] = target_index
            poke['Category']     = 0x00
            poke['Param']        = 0
            packets.inject(poke)
        end
    end
    return packets.build(p)
end)

windower.register_event('incoming chunk', function(id, data, modified, injected, blocked)

    if id == 0x00E and loot_scan.active and loot_scan.last_req_idx > 0 then
        local p = packets.parse('incoming', data)
        if p and p['Index'] == loot_scan.last_req_idx then
            loot_scan_next()
        end
        return
    end

    if state ~= STATE_POKE then return end
    if id ~= 0x034 and id ~= 0x033 and id ~= 0x032 then return end

    local p = packets.parse('incoming', data)
    if not p then return end
    local mid = p['Menu ID']
    if not mid or mid == 0 then return end

    local zone     = windower.ffxi.get_info().zone
    local live_id  = target_id
    local live_idx = target_index
    reset()

    local out = packets.new('outgoing', 0x05B)
    out['Target']            = live_id
    out['Target Index']      = live_idx
    out['Zone']              = zone
    out['Menu ID']           = mid
    out['Option Index']      = 0
    out['_unknown1']         = 0
    out['Automated Message'] = false
    out['_unknown2']         = 0
    packets.inject(out)

    windower.packets.inject_incoming(0x052, string.char(0,0,0,0,0,0,0,0))
    windower.packets.inject_incoming(0x052, string.char(0,0,0,0,1,0,0,0))

    loot_count = loot_count + 1
    if loot_wave > 0 then
        coroutine.schedule(process_next_loot, LOOT_DELAY)
    end
    return true
end)

windower.register_event('incoming text', function(original)
    if loot_wave > 0 or loot_scan.active then
        if string.find(original, 'enough izzat') then
            stop_loot('Out of izzat - stopping loot.')
        end
    end
end)

windower.register_event('prerender', function()
    local now = os.clock()

    if sortie_ao_enabled and in_sortie() then
        if ao_state == AO_SPOOF then

            if (now - sortie_spoof_started) > SORTIE_AO_SPOOF_TIMEOUT then
                err(('Sortie: spoof timeout on %s; resetting.'):format(ao_target_label))
                ao_state = AO_IDLE
                ao_spoof_count = 0
                sortie_cooldown_until = now + SORTIE_AO_RETRY_COOLDOWN
            end
        elseif now >= sortie_cooldown_until then
            local target = find_nearby_sortie_chest()
            if target then sortie_ao_start(target) end
        end
    end

    if loot_scan.active and loot_scan.last_req_time > 0
       and (now - loot_scan.last_req_time) > SCAN_TIMEOUT then
        loot_scan_next()
    end

    if state == STATE_POKE and poke_time > 0 then
        local elapsed = now - warp_t0
        if elapsed > POKE_HARD_TIMEOUT then
            err(('Container (index=%d) did not respond - skipping.'):format(target_index))
            reset()
            if loot_wave > 0 then coroutine.schedule(process_next_loot, 0.5) end
        elseif (now - poke_time) > POKE_RETRY_INT and poke_retry_count < POKE_MAX_RETRY then
            poke_retry_count = poke_retry_count + 1
            poke_time = now
            local req = packets.new('outgoing', 0x016)
            req['Target Index'] = target_index
            packets.inject(req)
            local poke = packets.new('outgoing', 0x01A)
            poke['Target']       = target_id
            poke['Target Index'] = target_index
            poke['Category']     = 0x00
            poke['Param']        = 0
            packets.inject(poke)
        end
    end
end)

local function open_my_assignment(payload)
    if state ~= STATE_IDLE or loot_wave > 0 then return end
    if not in_odyssey() then return end
    local my_id = windower.ffxi.get_player().id
    local queue = {}
    for assignment in payload:gmatch('[^|]+') do
        local mid_str, idx_str = assignment:match('^(%d+):(%d+)$')
        if tonumber(mid_str) == my_id then
            queue[#queue + 1] = { index = tonumber(idx_str) }
        end
    end
    if #queue == 0 then return end
    chat(('My assignment: %d container(s).'):format(#queue))
    loot_queue      = queue
    loot_count      = 0
    loot_party_mode = true
    loot_wave       = 1
    process_next_loot()
end

windower.register_event('ipc message', function(msg)
    local subcmd, payload = msg:match('^pandora (%S+) ?(.*)')
    if not subcmd then return end
    if subcmd == 'openchest' then
        open_my_assignment(payload)
    elseif subcmd == 'stop' then
        stop_loot('Loot cancelled (party).')
    end
end)

local function start_party_loot(waves)
    local all_indices = {}
    for _, w in ipairs(waves) do
        for _, idx in ipairs(w.indices) do all_indices[#all_indices + 1] = idx end
    end
    local party = windower.ffxi.get_party()
    local members = {}
    for _, key in ipairs({'p0','p1','p2','p3','p4','p5'}) do
        if party[key] and party[key].mob and party[key].mob.id then
            members[#members + 1] = { name = party[key].name, mob_id = party[key].mob.id }
        end
    end
    if #members == 0 then
        local me = windower.ffxi.get_mob_by_target('me')
        if me then members[1] = { name = me.name, mob_id = me.id } end
    end
    if #members == 0 then
        err('No party members found.')
        return
    end
    local parts = {}
    for i, idx in ipairs(all_indices) do
        local m = members[((i - 1) % #members) + 1]
        chat(('  %s -> index %d'):format(m.name, idx))
        parts[#parts + 1] = m.mob_id .. ':' .. idx
    end
    local payload = table.concat(parts, '|')
    chat(('Party loot: distributing %d container(s) across %d member(s).'):format(#all_indices, #members))
    windower.send_ipc_message('pandora openchest ' .. payload)

    open_my_assignment(payload)
end

local function do_loot_command(sheol, args)
    if not in_odyssey() then
        err('You must be in Sheol (Walk of Echoes [P1]/[P2]) to loot.')
        return
    end
    if state ~= STATE_IDLE or loot_wave > 0 then
        err('Loot already in progress. Use //pd stop first.')
        return
    end
    local s = SHEOL[sheol]
    local floor = tonumber(args[1])
    if not floor or floor < 1 or floor > s.floors then
        err(('Usage: //pd %s <1-%d> [a|b|c] [solo]'):format(sheol, s.floors))
        return
    end
    local filter, is_party = nil, true
    for i = 2, #args do
        local a = args[i]:lower()
        if a == 'party' then is_party = true
        elseif a == 'solo' then is_party = false
        elseif a == 'a' or a == 'chest'  or a == 'chests'  then filter = 1
        elseif a == 'b' or a == 'coffer' or a == 'coffers' then filter = 2
        elseif a == 'c' or a == 'strongbox' or a == 'strongboxes' or a == 'aurum' then filter = 3
        end
    end
    local all = get_waves(sheol, floor)
    if filter then
        LOOT_WAVES = { all[filter] }
    else
        LOOT_WAVES = all
    end
    if is_party then
        start_party_loot(LOOT_WAVES)
    else
        loot_count = 0
        local names = {}
        for _, w in ipairs(LOOT_WAVES) do names[#names + 1] = w.name end
        chat(('Solo loot %s F%d: %s'):format(s.name, floor, table.concat(names, ' -> ')))
        start_loot_wave(1)
    end
end

windower.register_event('addon command', function(cmd, ...)
    cmd = cmd and cmd:lower() or 'help'
    local args = {...}

    if cmd == 'a' or cmd == 'b' or cmd == 'c' then
        do_loot_command(cmd, args)

    elseif cmd == 'stop' or cmd == 'cancel' then
        if state ~= STATE_IDLE or loot_wave > 0 or loot_scan.active then
            stop_loot('Loot cancelled.')
            windower.send_ipc_message('pandora stop')
        else
            chat('Nothing in progress.')
        end

    elseif cmd == 'delay' then
        local n = tonumber(args[1])
        if n and n >= 0.5 and n <= 30 then
            LOOT_DELAY = n
            chat(('Open delay = %.1fs'):format(n))
        else
            chat(('Open delay = %.1fs. Usage: //pd delay <0.5-30>'):format(LOOT_DELAY))
        end

    elseif cmd == 'sortie' or cmd == 'ao' then
        local sub = args[1] and args[1]:lower() or ''
        if sub == 'on' then
            sortie_ao_enabled = true
            chat(('Sortie auto-open ON. Opens any known chest within %dy.'):format(SORTIE_AO_RANGE))
            save_settings()
        elseif sub == 'off' then
            sortie_ao_enabled = false
            ao_state = AO_IDLE
            ao_spoof_count = 0
            chat('Sortie auto-open OFF.')
            save_settings()
        elseif sub == 'reset' then
            sortie_opened = {}
            sortie_first_seen = {}
            chat('Sortie auto-open: opened-chest history cleared.')
        elseif sub == 'range' then
            local r = tonumber(args[2])
            if r and r > 0 and r <= 100 then
                SORTIE_AO_RANGE = r
                chat(('Sortie auto-open range = %dy'):format(r))
                save_settings()
            else
                chat(('Sortie auto-open range = %dy. Usage: //pd sortie range <1-100>'):format(SORTIE_AO_RANGE))
            end
        else
            local n = 0
            for _ in pairs(sortie_opened) do n = n + 1 end
            chat(('Sortie auto-open: %s, range=%dy, opened=%d'):format(
                tostring(sortie_ao_enabled), SORTIE_AO_RANGE, n))
            chat('Usage: //pd sortie on|off|reset|range <n>')
        end

    elseif cmd == 'status' then
        chat(('Odyssey: state=%s wave=%d queued=%d scanning=%s zone_ok=%s'):format(
            state, loot_wave, #loot_queue, tostring(loot_scan.active), tostring(in_odyssey())))
        chat(('Sortie AO: %s  ao_state=%s  in_sortie=%s'):format(
            tostring(sortie_ao_enabled), ao_state, tostring(in_sortie())))

    else
        chat('Pandora - automatic chest opener. Commands:')
        chat('  //pd a <1-7> [a|b|c] [solo]  - loot Sheol A floor')
        chat('  //pd b <1-6> [a|b|c] [solo]  - loot Sheol B floor')
        chat('  //pd c <1-4> [a|b|c] [solo]  - loot Sheol C floor')
        chat('      a=chests  b=coffers  c=aurum strongboxes  (omit = all waves)')
        chat('      party is default; add "solo" to open alone')
        chat('  //pd sortie on|off  - ambient auto-open of nearby Sortie chests')
        chat('  //pd sortie range <n> / reset')
        chat('  //pd stop        - cancel loot')
        chat('  //pd delay <n>   - seconds between opens (default 3)')
    end
end)

windower.register_event('zone change', function()
    stop_loot()
    sortie_ao_reset()
end)

windower.register_event('load', function()
    load_settings()
end)

windower.register_event('login', function()
    load_settings()
end)

chat('Pandora v'.._addon.version..' loaded. //pd help for commands.')
load_settings()
