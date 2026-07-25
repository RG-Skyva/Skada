local _, Skada = ...
local Private = Skada.Private

Skada:RegisterModule("Raid Fail Damage", function(L, P, _, _, M, O)
	local mode_lady = Skada:NewModule("Lady Deathwhisper Ghost Damage")
	local mode_lady_event = mode_lady:NewModule("Trigger List")
	local mode_lady_event_target = mode_lady_event:NewModule("Target List")
	local mode_lady_timeline = Skada:NewModule("Lady Deathwhisper Ghost Damage Timeline")
	local mode_sindragosa_p2 = Skada:NewModule("Sindragosa P2 Backlash Damage")
	local mode_sindragosa_p2_event = mode_sindragosa_p2:NewModule("Trigger List")
	local mode_sindragosa_p2_event_target = mode_sindragosa_p2_event:NewModule("Target List")
	local mode_sindragosa_all = Skada:NewModule("Sindragosa P1+P2 Backlash Damage")
	local mode_sindragosa_all_event = mode_sindragosa_all:NewModule("Trigger List")
	local mode_sindragosa_all_event_target = mode_sindragosa_all_event:NewModule("Target List")
	local mode_sindragosa_all_timeline = Skada:NewModule("Sindragosa P1+P2 Backlash Damage Timeline")
	local mode_council = Skada:NewModule("Blood Prince Council Knockbacks")
	local mode_council_target = mode_council:NewModule("Target List")

	local pairs, max, floor, date, format = pairs, math.max, math.floor, date, string.format
	local tsort = table.sort
	local wipe, GetTime = wipe, GetTime
	local classfmt = Skada.classcolors.format
	local GetCreatureId = Skada.GetCreatureId

	local TRIGGER_WINDOW = 3
	local VENGEFUL_SHADE_ID = 38222
	local SINDRAGOSA_ID = 36853
	local SINDRAGOSA_P2_HEALTH = 35
	local SINDRAGOSA_HEALTH_INTERVAL = 0.25
	local INSTABILITY_AURA = 69766
	local lady_explosions = {[72011] = true, [72012] = true}
	local sindragosa_explosions = {
		[69770] = true,
		[71044] = true,
		[71045] = true,
		[71046] = true
	}
	local council_knockbacks = {[72815] = true, [72038] = true, [72816] = true, [72817] = true}

	local lady_triggers = {}
	local sindragosa_triggers = {}
	local sindragosa_all_triggers = {}
	local latest_lady_trigger
	local latest_sindragosa_trigger
	local latest_sindragosa_all_trigger
	local sindragosa_guid
	local sindragosa_p2 = false
	local next_sindragosa_health_check = 0
	local combat_start_time
	local combat_registered = false
	local lady_mode_added = false
	local sindragosa_modes_added = false
	local council_mode_added = false

	local lady = {
		mode = mode_lady,
		eventmode = mode_lady_event,
		eventtargetmode = mode_lady_event_target,
		timelinemode = mode_lady_timeline,
		name = "Lady Deathwhisper Ghost Damage",
		timelinename = "Lady Deathwhisper Ghost Damage Timeline",
		damage = "ladyghostdamage",
		count = "ladyghosttriggers",
		events = "ladyghostevents",
		encountertime = true,
		include_trigger = true
	}

	local sindragosa = {
		mode = mode_sindragosa_p2,
		eventmode = mode_sindragosa_p2_event,
		eventtargetmode = mode_sindragosa_p2_event_target,
		name = "Sindragosa P2 Backlash Damage",
		damage = "sindragosabacklashdamage",
		count = "sindragosabacklashtriggers",
		events = "sindragosabacklashevents",
		encountertime = true,
		include_trigger = true
	}

	local sindragosa_all = {
		mode = mode_sindragosa_all,
		eventmode = mode_sindragosa_all_event,
		eventtargetmode = mode_sindragosa_all_event_target,
		timelinemode = mode_sindragosa_all_timeline,
		name = "Sindragosa P1+P2 Backlash Damage",
		timelinename = "Sindragosa P1+P2 Backlash Damage Timeline",
		damage = "sindragosaallbacklashdamage",
		count = "sindragosaallbacklashtriggers",
		events = "sindragosaallbacklashevents",
		encountertime = true,
		include_trigger = true
	}

	local function trigger_is_active(trigger, curtime)
		return trigger and trigger.expires and trigger.expires >= curtime
	end

	local function find_trigger(triggers, latest, sourceGUID, curtime)
		local trigger = sourceGUID and triggers[sourceGUID]
		if trigger_is_active(trigger, curtime) then
			return trigger
		elseif trigger_is_active(latest, curtime) then
			return latest
		end
	end

	local function log_trigger(set, trigger, config)
		local actor = Skada:GetActor(set, trigger.name, trigger.id, trigger.flags)
		if not actor then return end

		actor[config.count] = (actor[config.count] or 0) + 1
		set[config.count] = (set[config.count] or 0) + 1

		-- Detailed trigger records are optional for the total segment, just like
		-- the other detailed Skada drill-down data.
		if set == Skada.total and not P.totalidc then return end

		actor[config.events] = actor[config.events] or {}
		local event = {
			timestamp = trigger.timestamp,
			encountertime = trigger.encountertime,
			damage = 0,
			count = 0,
			targets = {}
		}
		actor[config.events][#actor[config.events] + 1] = event
		trigger.records = trigger.records or {}
		trigger.records[set] = trigger.records[set] or {}
		trigger.records[set][config.events] = event
	end

	local function log_damage(set, trigger, targetName, targetGUID, targetFlags, amount, config)
		if not amount or amount <= 0 then return end

		local actor = Skada:GetActor(set, trigger.name, trigger.id, trigger.flags)
		if not actor then return end

		actor[config.damage] = (actor[config.damage] or 0) + amount
		set[config.damage] = (set[config.damage] or 0) + amount

		local records = trigger.records and trigger.records[set]
		local event = records and records[config.events]
		if not event or not targetName then return end

		event.damage = event.damage + amount
		event.count = event.count + 1
		local target = event.targets[targetName]
		if not target then
			local targetActor = Skada:GetActor(set, targetName, targetGUID, targetFlags)
			target = {
				id = targetGUID or targetName,
				class = targetActor and targetActor.class,
				role = targetActor and targetActor.role,
				spec = targetActor and targetActor.spec,
				enemy = targetActor and targetActor.enemy,
				amount = 0,
				count = 0
			}
			event.targets[targetName] = target
		end

		target.amount = target.amount + amount
		target.count = target.count + 1
	end

	local function damage_amount(t)
		if t.event == "SPELL_DAMAGE" then
			return max(0, (t.amount or 0) + (t.absorbed or 0))
		elseif t.event == "SPELL_MISSED" and t.misstype == "ABSORB" then
			return max(0, t.absorbed or t.amount or 0)
		end
		return 0
	end

	local function is_valid_explosion_target(trigger, t, include_trigger)
		if not trigger or not t.dstName or not t:DestInGroup(true) then return false end
		if include_trigger then return true end
		if trigger.id and t.dstGUID then
			return trigger.id ~= t.dstGUID
		end
		return trigger.name ~= t.dstName
	end

	local function log_council_knockback(set, t, amount)
		local actor = Skada:GetActor(set, t.srcName, t.srcGUID, t.srcFlags)
		if not actor then return end

		actor.councilknockbacks = (actor.councilknockbacks or 0) + 1
		actor.councilknockbackdamage = (actor.councilknockbackdamage or 0) + amount
		set.councilknockbacks = (set.councilknockbacks or 0) + 1
		set.councilknockbackdamage = (set.councilknockbackdamage or 0) + amount

		if set == Skada.total and not P.totalidc then return end

		actor.councilknockbacktargets = actor.councilknockbacktargets or {}
		local target = actor.councilknockbacktargets[t.dstName]
		if not target then
			local targetActor = Skada:GetActor(set, t.dstName, t.dstGUID, t.dstFlags)
			target = {
				id = t.dstGUID or t.dstName,
				class = targetActor and targetActor.class,
				role = targetActor and targetActor.role,
				spec = targetActor and targetActor.spec,
				enemy = targetActor and targetActor.enemy,
				amount = 0,
				count = 0
			}
			actor.councilknockbacktargets[t.dstName] = target
		end

		target.amount = target.amount + amount
		target.count = target.count + 1
	end

	local function handle_council_knockback(t)
		if not council_knockbacks[t.spellid] or not t.srcName or not t.dstName then return end
		if not t:SourceInGroup(true) or not t:DestInGroup(true) then return end
		if (t.srcGUID and t.dstGUID and t.srcGUID == t.dstGUID) or t.srcName == t.dstName then return end

		local amount = max(0, (t.amount or 0) + (t.absorbed or 0))
		Skada:DispatchSets(log_council_knockback, t, amount)
	end

	local function handle_lady_trigger(t, curtime)
		if GetCreatureId(t.srcGUID) ~= VENGEFUL_SHADE_ID then return end
		if t.event == "SWING_MISSED" and t.misstype ~= "ABSORB" and t.misstype ~= "BLOCK" then return end
		if not t.dstName or not t:DestInGroup(true) then return end

		local trigger = {
			name = t.dstName,
			id = t.dstGUID,
			flags = t.dstFlags,
			timestamp = time(),
			encountertime = combat_start_time and max(0, curtime - combat_start_time) or nil,
			expires = curtime + TRIGGER_WINDOW
		}
		if t.srcGUID then lady_triggers[t.srcGUID] = trigger end
		latest_lady_trigger = trigger
		Skada:DispatchSets(log_trigger, trigger, lady)
	end

	local function handle_sindragosa_trigger(t, curtime)
		if t.spellid ~= INSTABILITY_AURA or not t.dstName or not t:DestInGroup(true) then return end

		local trigger = {
			name = t.dstName,
			id = t.dstGUID,
			flags = t.dstFlags,
			timestamp = time(),
			encountertime = combat_start_time and max(0, curtime - combat_start_time) or nil,
			expires = curtime + TRIGGER_WINDOW
		}

		-- Full-fight mode records every Backlash trigger independently of the phase.
		if t.dstGUID then sindragosa_all_triggers[t.dstGUID] = trigger end
		latest_sindragosa_all_trigger = trigger
		Skada:DispatchSets(log_trigger, trigger, sindragosa_all)

		-- Keep the existing category restricted to phase 2 (35% and below).
		if not sindragosa_p2 then return end
		if t.dstGUID then sindragosa_triggers[t.dstGUID] = trigger end
		latest_sindragosa_trigger = trigger
		Skada:DispatchSets(log_trigger, trigger, sindragosa)
	end

	local function update_sindragosa_phase(t, curtime, force)
		if sindragosa_p2 then return end

		if GetCreatureId(t.srcGUID) == SINDRAGOSA_ID then
			sindragosa_guid = t.srcGUID
		elseif GetCreatureId(t.dstGUID) == SINDRAGOSA_ID then
			sindragosa_guid = t.dstGUID
		end
		if not sindragosa_guid then return end
		if not force and curtime < next_sindragosa_health_check then return end
		next_sindragosa_health_check = curtime + SINDRAGOSA_HEALTH_INTERVAL

		-- Prefer the dedicated boss units, then fall back to raid targets via
		-- UnitHealthInfo. Once the 35% transition is seen it stays active until
		-- combat ends, so temporary target changes cannot disable the phase.
		local percent
		for index = 1, 5 do
			local unit = "boss" .. index
			if UnitExists(unit) and UnitGUID(unit) == sindragosa_guid then
				local health, maxhealth = UnitHealth(unit), UnitHealthMax(unit)
				if health and maxhealth and maxhealth > 0 then
					percent = 100 * health / maxhealth
				end
				break
			end
		end
		if not percent then
			percent = Skada.UnitHealthInfo(nil, sindragosa_guid)
		end

		if percent and percent <= SINDRAGOSA_P2_HEALTH then
			sindragosa_p2 = true
		end
	end

	local function handle_explosion(t, explosions, triggers, latest, config, curtime)
		if not explosions[t.spellid] then return end

		local trigger = find_trigger(triggers, latest, t.srcGUID, curtime)
		if not is_valid_explosion_target(trigger, t, config.include_trigger) then return end

		local amount = damage_amount(t)
		if amount > 0 then
			Skada:DispatchSets(log_damage, trigger, t.dstName, t.dstGUID, t.dstFlags, amount, config)
		end
	end

	local function combat_event(t)
		local curtime = GetTime()
		if M.sindragosaenabled ~= false then
			update_sindragosa_phase(t, curtime, t.event == "SPELL_AURA_REMOVED" and t.spellid == INSTABILITY_AURA)
		end

		if t.event == "SWING_DAMAGE" or t.event == "SWING_MISSED" then
			if M.ladyenabled ~= false then handle_lady_trigger(t, curtime) end
		elseif t.event == "SPELL_AURA_REMOVED" then
			if M.sindragosaenabled ~= false then handle_sindragosa_trigger(t, curtime) end
		elseif t.event == "SPELL_DAMAGE" or t.event == "SPELL_MISSED" then
			if t.event == "SPELL_DAMAGE" and M.councilenabled ~= false then
				handle_council_knockback(t)
			end
			if M.ladyenabled ~= false then
				handle_explosion(t, lady_explosions, lady_triggers, latest_lady_trigger, lady, curtime)
			end
			if M.sindragosaenabled ~= false then
				handle_explosion(t, sindragosa_explosions, sindragosa_all_triggers, latest_sindragosa_all_trigger, sindragosa_all, curtime)
				handle_explosion(t, sindragosa_explosions, sindragosa_triggers, latest_sindragosa_trigger, sindragosa, curtime)
			end
		end
	end

	local function format_value(d, total, count, cols, metadata, subview)
		d.valuetext = Skada:FormatValueCols(
			cols.Damage and Skada:FormatNumber(d.value),
			cols.Count and Skada:FormatNumber(count),
			cols[subview and "sPercent" or "Percent"] and Skada:FormatPercent(d.value, total)
		)

		if metadata and d.value > metadata.maxvalue then
			metadata.maxvalue = d.value
		end
	end

	local function format_encounter_time(seconds)
		seconds = floor(max(0, seconds or 0))
		return format("%d:%02d", floor(seconds / 60), seconds % 60)
	end

	local function setup_mode(config)
		local mode = config.mode
		local eventmode = config.eventmode
		local eventtargetmode = config.eventtargetmode
		local timelinemode = config.timelinemode

		function eventmode:Enter(win, id, label, class)
			win.actorid, win.actorname, win.actorclass = id, label, class
			win.title = format("%s - %s", L[config.name], classfmt(class, label))
		end

		function eventmode:Update(win, set)
			win.title = format("%s - %s", L[config.name], classfmt(win.actorclass, win.actorname))
			local actor = set and set:GetActor(win.actorname, win.actorid)
			local events = actor and actor[config.events]
			local total = actor and actor[config.damage]
			if not events then return end

			if win.metadata then win.metadata.maxvalue = 0 end
			for index = 1, #events do
				local event = events[index]
				local d = win:nr(index)
				d.id = index
				if config.encountertime then
					local elapsed = event.encountertime
					if elapsed == nil and event.timestamp and set.starttime then
						elapsed = max(0, event.timestamp - set.starttime)
					end
					d.label = format_encounter_time(elapsed)
				else
					d.label = format("#%d - %s", index, date("%H:%M:%S", event.timestamp))
				end
				d.value = event.damage or 0
				format_value(d, total or 0, event.count or 0, config.cols, win.metadata, true)
			end
		end

		function eventtargetmode:Enter(win, id, label)
			win.eventindex, win.eventname = id, label
			win.title = format("%s - %s", classfmt(win.actorclass, win.actorname), label)
		end

		function eventtargetmode:Update(win, set)
			win.title = format("%s - %s", classfmt(win.actorclass, win.actorname), win.eventname or "")
			local actor = set and set:GetActor(win.actorname, win.actorid)
			local events = actor and actor[config.events]
			local event = events and events[win.eventindex]
			local targets = event and event.targets
			local total = event and event.damage
			if not targets or not total or total <= 0 then return end

			if win.metadata then win.metadata.maxvalue = 0 end
			local nr = 0
			for targetName, target in pairs(targets) do
				if target.amount and target.amount > 0 then
					nr = nr + 1
					local d = win:actor(nr, target, target.enemy, targetName)
					d.value = target.amount
					format_value(d, total, target.count, config.cols, win.metadata, true)
				end
			end
		end

		if timelinemode then
		function timelinemode:Update(win, set)
			win.title = L[config.timelinename]
			if not set then return end

			local timeline = {}
			for actorName, actor in pairs(set.actors) do
				local events = actor[config.events]
				if events then
					for eventIndex = 1, #events do
						timeline[#timeline + 1] = {
							name = actorName,
							class = actor.class,
							event = events[eventIndex],
							index = eventIndex
						}
					end
				end
			end
			if #timeline == 0 then return end

			tsort(timeline, function(a, b)
				local aevent, bevent = a.event, b.event
				local atime = aevent.encountertime or aevent.timestamp or 0
				local btime = bevent.encountertime or bevent.timestamp or 0
				if atime == btime then
					if a.name == b.name then return a.index < b.index end
					return a.name < b.name
				end
				return atime < btime
			end)

			if win.metadata then win.metadata.maxvalue = 0 end
			for index = 1, #timeline do
				local entry = timeline[index]
				local event = entry.event
				local elapsed = event.encountertime
				if elapsed == nil and event.timestamp and set.starttime then
					elapsed = max(0, event.timestamp - set.starttime)
				end

				local d = win:nr(index)
				d.id = index
				d.label = format("[%s] %s", format_encounter_time(elapsed), classfmt(entry.class, entry.name))
				d.value = event.damage or 0
				format_value(d, set[config.damage] or 0, event.count or 0, config.timelinecols, win.metadata, true)
			end
		end

		function timelinemode:GetSetSummary(set)
			return set and set[config.damage]
		end
		end

		function mode:Update(win, set)
			win.title = L[config.name]
			local totalDamage = set and set[config.damage] or 0
			local totalTriggers = set and set[config.count] or 0
			if totalDamage <= 0 and totalTriggers <= 0 then return end

			if win.metadata then win.metadata.maxvalue = 0 end
			local nr = 0
			for actorName, actor in pairs(set.actors) do
				local damage = actor[config.damage] or 0
				local triggers = actor[config.count] or 0
				if win:show_actor(actor, set, true) and (damage > 0 or triggers > 0) then
					nr = nr + 1
					local d = win:actor(nr, actor, actor.enemy, actorName)
					d.value = damage
					format_value(d, totalDamage, triggers, config.cols, win.metadata)
				end
			end
		end

		function mode:GetSetSummary(set)
			return set and set[config.damage]
		end

		function mode:AddToTooltip(set, tooltip)
			local amount = set and set[config.damage]
			if amount and amount > 0 then
				tooltip:AddDoubleLine(L[config.name], Skada:FormatNumber(amount), 1, 1, 1)
			end
		end

		eventtargetmode.metadata = {showspots = true}
		eventmode.metadata = {showspots = true, ordersort = true, click1 = eventtargetmode}
		eventmode.nototal = true
		if timelinemode then
			timelinemode.metadata = {
				ordersort = true,
				columns = {Damage = true, Count = false, Percent = false, sPercent = false},
				icon = [[Interface\ICONS\inv_misc_pocketwatch_01]]
			}
			config.timelinecols = timelinemode.metadata.columns
		end
		mode.metadata = {
			showspots = true,
			filterclass = true,
			click1 = eventmode,
			columns = {Damage = true, Count = true, Percent = false, sPercent = false},
			icon = [[Interface\ICONS\spell_shadow_deathsembrace]]
		}
		config.cols = mode.metadata.columns
	end

	local council_cols
	local function format_council_value(d, total, count, amount, metadata)
		d.valuetext = Skada:FormatValueCols(
			council_cols.Count and Skada:FormatNumber(count),
			council_cols.Damage and Skada:FormatNumber(amount),
			council_cols.Percent and Skada:FormatPercent(count, total)
		)

		if metadata and d.value > metadata.maxvalue then
			metadata.maxvalue = d.value
		end
	end

	function mode_council_target:Enter(win, id, label, class)
		win.actorid, win.actorname, win.actorclass = id, label, class
		win.title = L["%s's targets"]:format(classfmt(class, label))
	end

	function mode_council_target:Update(win, set)
		win.title = L["%s's targets"]:format(classfmt(win.actorclass, win.actorname))
		local actor = set and set:GetActor(win.actorname, win.actorid)
		local targets = actor and actor.councilknockbacktargets
		local total = actor and actor.councilknockbacks
		if not targets or not total or total <= 0 then return end

		if win.metadata then win.metadata.maxvalue = 0 end
		local nr = 0
		for targetName, target in pairs(targets) do
			nr = nr + 1
			local d = win:actor(nr, target, target.enemy, targetName)
			d.value = target.count
			format_council_value(d, total, target.count, target.amount, win.metadata)
		end
	end

	function mode_council:Update(win, set)
		win.title = L["Blood Prince Council Knockbacks"]
		local total = set and set.councilknockbacks
		if not total or total <= 0 then return end

		if win.metadata then win.metadata.maxvalue = 0 end
		local nr = 0
		for actorName, actor in pairs(set.actors) do
			if win:show_actor(actor, set, true) and actor.councilknockbacks and actor.councilknockbacks > 0 then
				nr = nr + 1
				local d = win:actor(nr, actor, actor.enemy, actorName)
				d.value = actor.councilknockbacks
				format_council_value(d, total, actor.councilknockbacks, actor.councilknockbackdamage or 0, win.metadata)
			end
		end
	end

	function mode_council:GetSetSummary(set)
		return set and set.councilknockbacks
	end

	function mode_council:AddToTooltip(set, tooltip)
		if set.councilknockbacks and set.councilknockbacks > 0 then
			tooltip:AddDoubleLine(L["Blood Prince Council Knockbacks"], set.councilknockbacks, 1, 1, 1)
		end
	end

	local function update_combat_registration()
		local enabled = M.ladyenabled ~= false or M.sindragosaenabled ~= false or M.councilenabled ~= false
		if enabled and not combat_registered then
			Skada:RegisterForCL(
				combat_event,
				nil,
				"SWING_DAMAGE",
				"SWING_MISSED",
				"SPELL_AURA_REMOVED",
				"SPELL_DAMAGE",
				"SPELL_MISSED"
			)
			combat_registered = true
		elseif not enabled and combat_registered then
			Skada:UnregisterFromCL(combat_event)
			combat_registered = false
		end
	end

	local function update_raidfail_modes()
		local lady_enabled = M.ladyenabled ~= false
		if lady_enabled and not lady_mode_added then
			Skada:AddMode(mode_lady, "Fails")
			Skada:AddMode(mode_lady_timeline, "Fails")
			lady_mode_added = true
		elseif not lady_enabled and lady_mode_added then
			Skada:RemoveMode(mode_lady_timeline)
			Skada:RemoveMode(mode_lady)
			lady_mode_added = false
		end

		local sindragosa_enabled = M.sindragosaenabled ~= false
		if sindragosa_enabled and not sindragosa_modes_added then
			Skada:AddMode(mode_sindragosa_all, "Fails")
			Skada:AddMode(mode_sindragosa_p2, "Fails")
			Skada:AddMode(mode_sindragosa_all_timeline, "Fails")
			sindragosa_modes_added = true
		elseif not sindragosa_enabled and sindragosa_modes_added then
			Skada:RemoveMode(mode_sindragosa_all_timeline)
			Skada:RemoveMode(mode_sindragosa_p2)
			Skada:RemoveMode(mode_sindragosa_all)
			sindragosa_modes_added = false
		end

		local council_enabled = M.councilenabled ~= false
		if council_enabled and not council_mode_added then
			Skada:AddMode(mode_council, "Fails")
			council_mode_added = true
		elseif not council_enabled and council_mode_added then
			Skada:RemoveMode(mode_council)
			council_mode_added = false
		end

		update_combat_registration()
	end

	local function set_encounter_enabled(key, value)
		M[key] = value
		if key == "ladyenabled" and not value then
			wipe(lady_triggers)
			latest_lady_trigger = nil
		elseif key == "sindragosaenabled" and not value then
			wipe(sindragosa_triggers)
			wipe(sindragosa_all_triggers)
			latest_sindragosa_trigger = nil
			latest_sindragosa_all_trigger = nil
			sindragosa_guid = nil
			sindragosa_p2 = false
			next_sindragosa_health_check = 0
		end
		update_raidfail_modes()
		Skada:ApplySettings()
	end

	function mode_lady:OnInitialize()
		if M.ladyenabled == nil then M.ladyenabled = true end
		if M.sindragosaenabled == nil then M.sindragosaenabled = true end
		if M.councilenabled == nil then M.councilenabled = true end

		local rgskyva = O.modules.args.rgskyva.args
		rgskyva.ladyenabled = {
			type = "toggle",
			name = L["Lady Deathwhisper"],
			desc = L["Enable encounter fail module"],
			order = 10,
			width = "double",
			get = function() return M.ladyenabled ~= false end,
			set = function(_, value) set_encounter_enabled("ladyenabled", value) end
		}
		rgskyva.sindragosaenabled = {
			type = "toggle",
			name = L["Sindragosa"],
			desc = L["Enable encounter fail module"],
			order = 20,
			width = "double",
			get = function() return M.sindragosaenabled ~= false end,
			set = function(_, value) set_encounter_enabled("sindragosaenabled", value) end
		}
		rgskyva.councilenabled = {
			type = "toggle",
			name = L["Blood Prince Council"],
			desc = L["Enable encounter fail module"],
			order = 40,
			width = "double",
			get = function() return M.councilenabled ~= false end,
			set = function(_, value) set_encounter_enabled("councilenabled", value) end
		}
	end

	function mode_lady:OnEnable()
		setup_mode(lady)
		setup_mode(sindragosa)
		setup_mode(sindragosa_all)
		mode_council_target.metadata = {showspots = true}
		mode_council_target.nototal = true
		mode_council.metadata = {
			showspots = true,
			filterclass = true,
			click1 = mode_council_target,
			columns = {Count = true, Damage = true, Percent = false},
			icon = [[Interface\ICONS\spell_shadow_psychicscream]]
		}
		council_cols = mode_council.metadata.columns

		Skada.RegisterMessage(self, "COMBAT_PLAYER_LEAVE", "CombatLeave")
		Skada.RegisterMessage(self, "COMBAT_PLAYER_ENTER", "CombatEnter")
		update_raidfail_modes()
	end

	function mode_lady:OnDisable()
		if combat_registered then
			Skada:UnregisterFromCL(combat_event)
			combat_registered = false
		end
		Skada.UnregisterAllMessages(self)
		if council_mode_added then Skada:RemoveMode(mode_council) end
		if sindragosa_modes_added then
			Skada:RemoveMode(mode_sindragosa_all_timeline)
			Skada:RemoveMode(mode_sindragosa_p2)
			Skada:RemoveMode(mode_sindragosa_all)
		end
		if lady_mode_added then
			Skada:RemoveMode(mode_lady_timeline)
			Skada:RemoveMode(mode_lady)
		end
		council_mode_added = false
		sindragosa_modes_added = false
		lady_mode_added = false
	end

	function mode_lady:CombatLeave()
		wipe(lady_triggers)
		wipe(sindragosa_triggers)
		wipe(sindragosa_all_triggers)
		latest_lady_trigger = nil
		latest_sindragosa_trigger = nil
		latest_sindragosa_all_trigger = nil
		sindragosa_guid = nil
		sindragosa_p2 = false
		next_sindragosa_health_check = 0
		combat_start_time = nil
	end

	function mode_lady:CombatEnter()
		combat_start_time = GetTime()
		sindragosa_guid = nil
		sindragosa_p2 = false
		next_sindragosa_health_check = 0
	end
end)
