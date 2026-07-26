local _, Skada = ...
local Private = Skada.Private

Skada:RegisterModule("Demo Shout Uptime", function(L, P)
	local mode = Skada:NewModule("Demo Shout Uptime")
	local mode_source = mode:NewModule("Source List")

	local pairs, format, min, max = pairs, string.format, math.min, math.max
	local GetTime = GetTime
	local classfmt = Skada.classcolors.format
	local mode_cols

	-- All player and non-player ranks supplied for the tracked attack-power
	-- reduction effects. Entries that cannot be caused by players are harmless:
	-- applications are accepted only when their source is a group player.
	local tracked_spells = {
		-- Demoralizing Roar
		[10968] = true, [99] = true, [15727] = true, [15971] = true,
		[9898] = true, [48560] = true, [48559] = true, [27551] = true,
		[1735] = true, [26998] = true, [9490] = true, [9747] = true,
		[20753] = true,

		-- Vindication
		[67] = true, [36002] = true, [26016] = true, [26017] = true,
		[9452] = true,

		-- Demoralizing Shout
		[6190] = true, [29584] = true, [23511] = true, [11554] = true,
		[25202] = true, [11555] = true, [16244] = true, [11556] = true,
		[61044] = true, [47437] = true, [1160] = true, [27579] = true,
		[69565] = true, [62102] = true, [25203] = true, [13730] = true,
		[59613] = true, [19778] = true,

		-- Curse of Weakness
		[50511] = true, [27224] = true, [30909] = true, [17227] = true,
		[11707] = true, [21007] = true, [18267] = true, [12493] = true,
		[1108] = true, [8552] = true, [702] = true, [7646] = true,
		[11708] = true, [11980] = true, [12741] = true, [6205] = true,

		-- Improved Demoralizing Shout
		[12878] = true, [12879] = true, [12876] = true, [12324] = true,
		[12877] = true
	}

	local function current_time()
		return GetTime()
	end

	local function begin_interval(entry, curtime)
		entry.active = entry.active or 0
		if entry.active == 0 then
			entry.started = curtime
		end
		entry.active = entry.active + 1
	end

	local function end_interval(entry, curtime)
		if not entry or not entry.active or entry.active == 0 then return end

		entry.active = entry.active - 1
		if entry.active == 0 then
			if entry.started then
				entry.uptime = (entry.uptime or 0) + max(0, curtime - entry.started)
			end
			entry.started = nil
		end
	end

	local function get_uptime(entry, curtime)
		local uptime = entry and entry.uptime or 0
		if entry and entry.active and entry.active > 0 and entry.started then
			uptime = uptime + max(0, curtime - entry.started)
		end
		return uptime
	end

	local function get_data(set)
		if not set or (set == Skada.total and not P.totalidc) then return end
		set.demoshoutuptime = set.demoshoutuptime or {targets = {}}
		return set.demoshoutuptime
	end

	local function get_target(data, t)
		local key = t.dstGUID or t.dstName
		if not key or not t.dstName then return end

		local target = data.targets[key]
		if not target then
			target = {
				id = t.dstGUID or t.dstName,
				name = t.dstName,
				class = "ENEMY",
				enemy = true,
				uptime = 0,
				sources = {},
				auras = {}
			}
			data.targets[key] = target
		end
		target.sources = target.sources or {}
		target.auras = target.auras or {}
		return target
	end

	local function get_source(set, target, t)
		local key = t.srcGUID or t.srcName
		if not key or not t.srcName then return end

		local source = target.sources[key]
		if not source then
			local actor = Skada:GetActor(set, t.srcName, t.srcGUID, t.srcFlags)
			source = {
				id = t.srcGUID or t.srcName,
				name = t.srcName,
				class = actor and actor.class,
				role = actor and actor.role,
				spec = actor and actor.spec,
				enemy = actor and actor.enemy,
				uptime = 0
			}
			target.sources[key] = source
		end
		return source, key
	end

	local function close_aura(target, spellid, curtime)
		local aura = target and target.auras and target.auras[spellid]
		if not aura then return end

		end_interval(target, curtime)
		end_interval(target.sources[aura.source], curtime)
		target.auras[spellid] = nil
	end

	local function apply_aura(set, t, curtime)
		local data = get_data(set)
		if not data then return end

		local target = get_target(data, t)
		if not target then return end

		local source, sourcekey = get_source(set, target, t)
		if not source then return end

		local aura = target.auras[t.spellid]
		if aura and aura.source == sourcekey then
			return -- a normal refresh keeps the existing interval open.
		elseif aura then
			close_aura(target, t.spellid, curtime)
		end

		target.auras[t.spellid] = {source = sourcekey}
		begin_interval(target, curtime)
		begin_interval(source, curtime)
	end

	local function remove_aura(set, t, curtime)
		local data = set and set.demoshoutuptime
		local target = data and data.targets[t.dstGUID or t.dstName]
		if target then
			close_aura(target, t.spellid, curtime)
		end
	end

	local function handle_aura(t)
		if t.auratype ~= "DEBUFF" or not tracked_spells[t.spellid] then return end

		local curtime = current_time()
		if t.event == "SPELL_AURA_REMOVED" then
			Skada:DispatchSets(remove_aura, t, curtime)
		elseif t:SourceInGroup(true) then
			-- APPLIED, APPLIED_DOSE and REFRESH all ensure that an interval is open.
			-- A refresh received without its original application starts tracking now.
			Skada:DispatchSets(apply_aura, t, curtime)
		end
	end

	local function unit_died(t)
		if not t.dstGUID then return end
		local curtime = current_time()

		local function close_target(set)
			local data = set and set.demoshoutuptime
			local target = data and data.targets[t.dstGUID]
			if not target or not target.auras then return end

			for spellid in pairs(target.auras) do
				close_aura(target, spellid, curtime)
			end
		end

		Skada:DispatchSets(close_target)
	end

	local function format_valuetext(d, settime, metadata, subview)
		d.valuetext = Skada:FormatValueCols(
			mode_cols.Uptime and Skada:FormatTime(d.value),
			mode_cols[subview and "sPercent" or "Percent"] and Skada:FormatPercent(d.value, settime)
		)

		if metadata and d.value > metadata.maxvalue then
			metadata.maxvalue = d.value
		end
	end

	function mode_source:Enter(win, id, label, class)
		win.targetid, win.targetname, win.targetclass = id, label, class
		win.title = format("%s - %s", classfmt(class, label), L["Source List"])
	end

	function mode_source:Update(win, set)
		win.title = format("%s - %s", classfmt(win.targetclass, win.targetname), L["Source List"])
		local data = set and set.demoshoutuptime
		local target = data and data.targets[win.targetid]
		if not target then return end

		local settime = set:GetTime()
		local curtime = current_time()
		if win.metadata then win.metadata.maxvalue = 0 end

		local nr = 0
		for _, source in pairs(target.sources) do
			local uptime = min(get_uptime(source, curtime), settime)
			if uptime > 0 then
				nr = nr + 1
				local d = win:actor(nr, source, source.enemy, source.name)
				d.value = uptime
				format_valuetext(d, settime, win.metadata, true)
			end
		end
	end

	function mode:Update(win, set)
		win.title = L["Demo Shout Uptime"]
		local data = set and set.demoshoutuptime
		if not data or not data.targets then return end

		local settime = set:GetTime()
		local curtime = current_time()
		if win.metadata then win.metadata.maxvalue = 0 end

		local nr = 0
		for _, target in pairs(data.targets) do
			local uptime = min(get_uptime(target, curtime), settime)
			if uptime > 0 then
				nr = nr + 1
				local d = win:actor(nr, target, target.enemy, target.name)
				d.value = uptime
				format_valuetext(d, settime, win.metadata)
			end
		end
	end

	function mode:SetComplete(set)
		local data = set and set.demoshoutuptime
		if not data or not data.targets then return end

		local curtime = current_time()
		for key, target in pairs(data.targets) do
			for spellid in pairs(target.auras or {}) do
				close_aura(target, spellid, curtime)
			end

			target.active, target.started, target.auras = nil, nil, nil
			for sourcekey, source in pairs(target.sources or {}) do
				source.active, source.started = nil, nil
				if not source.uptime or source.uptime <= 0 then
					target.sources[sourcekey] = nil
				end
			end

			if not target.uptime or target.uptime <= 0 then
				data.targets[key] = nil
			end
		end
	end

	function mode:OnEnable()
		mode_source.metadata = {showspots = true}
		self.metadata = {
			showspots = true,
			click1 = mode_source,
			columns = {Uptime = true, Percent = true, sPercent = true},
			icon = [[Interface\ICONS\ability_warrior_warcry]]
		}
		mode_cols = self.metadata.columns

		Skada:RegisterForCL(
			handle_aura,
			nil,
			"SPELL_AURA_APPLIED",
			"SPELL_AURA_APPLIED_DOSE",
			"SPELL_AURA_REFRESH",
			"SPELL_AURA_REMOVED"
		)
		Skada:RegisterForCL(unit_died, nil, "UNIT_DIED", "UNIT_DESTROYED", "UNIT_DISSIPATES")
		Skada:AddMode(self, "Buffs and Debuffs")
	end

	function mode:OnDisable()
		Skada:UnregisterFromCL(handle_aura)
		Skada:UnregisterFromCL(unit_died)
		Skada:RemoveMode(self)
	end
end)
