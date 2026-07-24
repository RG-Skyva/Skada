local _, Skada = ...
local Private = Skada.Private

-- Counts every Sunder Armor application, dose and refresh. Unlike the regular
-- Sunder Effective Counter, no refresh-delay filter is applied here.
Skada:RegisterModule("Sunder Total Counter", function(L, P, _, C)
	local mode = Skada:NewModule("Sunder Total Counter")
	local mode_target = mode:NewModule("Target List")
	local mode_target_source = mode_target:NewModule("Source List")
	local get_actor_sunder_sources
	local get_actor_sunder_targets

	local pairs, format, GetTime, wipe = pairs, string.format, GetTime, wipe
	local clear, new = Private.clearTable, Private.newTable
	local classfmt = Skada.classcolors.format
	local spellnames = Skada.spellnames
	local mode_cols
	local spell_sunder, spell_devastate
	local last_sunder_cast
	local sunder_casts = {}
	local CAST_WINDOW = 1

	local function format_valuetext(d, total, metadata, subview)
		d.valuetext = Skada:FormatValueCols(
			mode_cols.Count and Skada:FormatNumber(d.value),
			mode_cols[subview and "sPercent" or "Percent"] and Skada:FormatPercent(d.value, total)
		)

		if metadata and d.value > metadata.maxvalue then
			metadata.maxvalue = d.value
		end
	end

	local function log_sunder(set, actorname, actorid, actorflags, dstName)
		local actor = Skada:GetActor(set, actorname, actorid, actorflags)
		if not actor then return end

		set.totalsunder = (set.totalsunder or 0) + 1
		actor.totalsunder = (actor.totalsunder or 0) + 1

		-- Keep detailed target data out of the compact total segment.
		if (set == Skada.total and not P.totalidc) or not dstName then return end

		actor.totalsundertargets = actor.totalsundertargets or {}
		actor.totalsundertargets[dstName] = (actor.totalsundertargets[dstName] or 0) + 1
	end

	local function sunder_applied(t)
		if t.spellname ~= spell_sunder and t.spellname ~= spell_devastate then return end

		-- Removal is not a Sunder application. All other registered aura events,
		-- including early refreshes, count without a time-based filter.
		-- On 3.3.5, dose and refresh aura events can keep reporting the owner of
		-- the existing aura instead of the warrior who performed the new cast.
		local curtime = Skada._Time or GetTime()
		local cast = t.dstGUID and sunder_casts[t.dstGUID]
		if cast and curtime - cast.time > CAST_WINDOW then
			cast = nil
		end
		if not cast and last_sunder_cast and
			(not t.dstGUID or not last_sunder_cast.target or last_sunder_cast.target == t.dstGUID) then
			cast = last_sunder_cast
		end
		if cast and curtime - cast.time <= CAST_WINDOW then
			Skada:DispatchSets(log_sunder, cast.name, cast.guid, cast.flags, t.dstName)
		else
			Skada:DispatchSets(log_sunder, t.srcName, t.srcGUID, t.srcFlags, t.dstName)
		end
	end

	local function sunder_cast(t)
		if t.spellname ~= spell_sunder and t.spellname ~= spell_devastate then return end

		local cast = {
			guid = t.srcGUID,
			name = t.srcName,
			flags = t.srcFlags,
			target = t.dstGUID,
			time = Skada._Time or GetTime()
		}
		last_sunder_cast = cast
		if t.dstGUID then
			sunder_casts[t.dstGUID] = cast
		end
	end

	local function double_check_sunder()
		spell_sunder = spell_sunder or spellnames[47467]
		spell_devastate = spell_devastate or spellnames[47498]
	end

	function mode_target_source:Enter(win, id, label, class)
		win.targetid, win.targetname, win.targetclass = id, label, class
		win.title = format(L["%s's sources"], classfmt(class, label))
	end

	function mode_target_source:Update(win, set)
		win.title = format(L["%s's sources"], classfmt(win.targetclass, win.targetname))
		if not set or not win.targetname then return end

		local sources, total = get_actor_sunder_sources(set, win.targetname)
		if not sources or total == 0 then
			return
		elseif win.metadata then
			win.metadata.maxvalue = 0
		end

		local nr = 0
		for sourcename, source in pairs(sources) do
			nr = nr + 1
			local d = win:actor(nr, source, source.enemy, sourcename)
			d.value = source.count
			format_valuetext(d, total, win.metadata, true)
		end
	end

	function mode_target:Enter(win, id, label, class)
		win.actorid, win.actorname, win.actorclass = id, label, class
		win.title = format(L["%s's targets"], classfmt(class, label))
	end

	function mode_target:Update(win, set)
		double_check_sunder()
		win.title = format(L["%s's targets"], classfmt(win.actorclass, win.actorname))
		if not set or not win.actorname then return end

		local targets, total, actor = get_actor_sunder_targets(set, win.actorname, win.actorid)
		if not targets or not actor or total == 0 then
			return
		elseif win.metadata then
			win.metadata.maxvalue = 0
		end

		local nr = 0
		for targetname, target in pairs(targets) do
			nr = nr + 1
			local d = win:actor(nr, target, target.enemy, targetname)
			d.value = target.count
			format_valuetext(d, total, win.metadata, true)
		end
	end

	function mode:Update(win, set)
		double_check_sunder()
		win.title = L["Sunder Total Counter"]
		if not set then return end

		local total = set.totalsunder
		if not total or total == 0 then
			return
		elseif win.metadata then
			win.metadata.maxvalue = 0
		end

		local nr = 0
		for actorname, actor in pairs(set.actors) do
			if actor and actor.totalsunder then
				nr = nr + 1
				local d = win:actor(nr, actor, actor.enemy, actorname)
				d.value = actor.totalsunder
				format_valuetext(d, total, win.metadata)
			end
		end
	end

	function mode_target:GetSetSummary(set, win)
		local actor = set and win and set:GetActor(win.actorname, win.actorid)
		return actor and actor.totalsunder
	end

	function mode:GetSetSummary(set)
		return set and set.totalsunder
	end

	function mode:AddToTooltip(set, tooltip)
		if set.totalsunder and set.totalsunder > 0 then
			tooltip:AddDoubleLine(L["Sunder Total Counter"], set.totalsunder, 1, 1, 1)
		end
	end

	function mode:OnEnable()
		mode_target_source.metadata = {showspots = true}
		mode_target.metadata = {click1 = mode_target_source}
		self.metadata = {
			showspots = true,
			click1 = mode_target,
			columns = {Count = true, Percent = false, sPercent = false},
			icon = [[Interface\ICONS\ability_warrior_sunder]]
		}
		mode_cols = self.metadata.columns
		mode_target.nototal = true

		Skada:RegisterForCL(
			sunder_applied,
			{src_is_interesting_nopets = true},
			"SPELL_AURA_APPLIED",
			"SPELL_AURA_APPLIED_DOSE",
			"SPELL_AURA_REFRESH"
		)
		Skada:RegisterForCL(
			sunder_cast,
			{src_is_interesting_nopets = true},
			"SPELL_CAST_SUCCESS"
		)
		Skada.RegisterMessage(self, "COMBAT_PLAYER_LEAVE", "CombatLeave")

		Skada:AddMode(self, "Buffs and Debuffs")
	end

	function mode:OnDisable()
		Skada:UnregisterFromCL(sunder_applied)
		Skada:UnregisterFromCL(sunder_cast)
		Skada.UnregisterAllMessages(self)
		Skada:RemoveMode(self)
	end

	function mode:CombatLeave()
		wipe(sunder_casts)
		last_sunder_cast = nil
	end

	function mode:OnInitialize()
		double_check_sunder()
	end

	get_actor_sunder_sources = function(set, name, tbl)
		if not set or not set.totalsunder or not name then return end
		tbl = clear(tbl or C)

		local total = 0
		for actorname, actor in pairs(set.actors) do
			local count = actor.totalsundertargets and actor.totalsundertargets[name]
			if count then
				local t = new()
				t.id = actor.id
				t.class = actor.class
				t.role = actor.role
				t.spec = actor.spec
				t.enemy = actor.enemy
				t.count = count
				tbl[actorname] = t
				total = total + count
			end
		end
		return tbl, total
	end

	get_actor_sunder_targets = function(set, name, id, tbl)
		local actor = set and set:GetActor(name, id)
		if not actor or not actor.totalsundertargets then return end

		local total = actor.totalsunder
		tbl = clear(tbl or C)
		for targetname, count in pairs(actor.totalsundertargets) do
			tbl[targetname] = new()
			tbl[targetname].count = count
			set:_fill_actor_table(tbl[targetname], targetname)
		end
		return tbl, total, actor
	end
end)
