-- MapScout: the search engine.
-- Engine.Search(query) scores the indexed entries of the enabled providers
-- against a parsed query (Search/Query.lua) and returns the best ones.
--
-- Each typed word must match a word of the entry's name or keywords:
--   exact word > word starts with it > word contains it   (name beats keywords)
-- plus bonuses when the whole name is the text or starts with it, and the
-- entry's weight. A text that is one of the player's aliases puts its result first.
-- Typos: only when the normal match finds few results, words of 4+ letters
-- may differ by one letter (two from 8 letters): swapped, missing, extra or wrong.
-- Narrowing: when the text only grows ("ven" -> "vent") and nothing changed in
-- the index, only the previous matches are checked again.
-- Ties keep a stable order: shorter name, then alphabetical, then key.

local _, ns = ...
local L = ns.L

local Engine = {}
ns.Engine = Engine

Engine.DEFAULT_MAX = 50
Engine.FUZZY_WHEN_FEWER_THAN = 5 -- typo pass only when the normal one finds fewer

local LEVEL = { exact = 40, prefix = 30, contains = 15 }
local KEYWORD_PENALTY = 5
local FUZZY_LEVEL = 8
local BONUS_SAME_NAME, BONUS_NAME_PREFIX, BONUS_NAME_CONTAINS = 200, 100, 30
local WEIGHT_POINTS = 20
local ALIAS_SCORE = 100000

-- Typo distance ----------------------------------------------------------------

-- Edit distance between two words (insert, delete, change, swap two letters),
-- giving up as soon as it is over max. Returns the distance or max + 1.
function Engine.Distance(a, b, max)
	local la, lb = #a, #b
	if math.abs(la - lb) > max then
		return max + 1
	end
	local previous, current, beforePrevious = {}, {}, {}
	for j = 0, lb do
		previous[j] = j
	end
	for i = 1, la do
		current[0] = i
		local rowMin = i
		local ca = a:byte(i)
		for j = 1, lb do
			local cb = b:byte(j)
			local cost = (ca == cb) and 0 or 1
			local value = math.min(previous[j] + 1, current[j - 1] + 1, previous[j - 1] + cost)
			if i > 1 and j > 1 and ca == b:byte(j - 1) and a:byte(i - 1) == cb then
				value = math.min(value, beforePrevious[j - 2] + 1)
			end
			current[j] = value
			if value < rowMin then
				rowMin = value
			end
		end
		if rowMin > max then
			return max + 1
		end
		beforePrevious, previous, current = previous, current, beforePrevious
	end
	return previous[lb]
end

local function allowedTypos(word)
	if word:find("^%d+$") then
		return 0 -- a typo in a number means nothing (and numbers rarely repeat)
	elseif #word >= 8 then
		return 2
	elseif #word >= 4 then
		return 1
	end
	return 0
end

-- Matching -------------------------------------------------------------------

-- Best level of one typed word against a list of words (0: no match).
-- Hot path: plain loops and one find per word, no new strings.
local EXACT, PREFIX, CONTAINS = LEVEL.exact, LEVEL.prefix, LEVEL.contains
local find = string.find

local function wordLevel(word, words)
	local best = 0
	for i = 1, #words do
		local candidate = words[i]
		if candidate == word then
			return EXACT
		end
		if best < PREFIX then
			local at = find(candidate, word, 1, true)
			if at == 1 then
				best = PREFIX
			elseif at then
				best = CONTAINS
			end
		end
	end
	return best
end

-- Words repeat a lot across entries ("de", "banco"...): during one search,
-- each pair of words is compared only once. Reset by Engine.Search.
local closeCache = {}

local function isDigit(byte)
	return byte >= 48 and byte <= 57
end

local function isClose(word, candidate, max)
	-- a word with letters is never a typo of a number (and numbers rarely repeat)
	if isDigit(candidate:byte(1)) and not isDigit(word:byte(1)) then
		return false
	end
	local known = closeCache[word]
	if not known then
		known = {}
		closeCache[word] = known
	end
	local close = known[candidate]
	if close == nil then
		-- the whole word, or its start (a typo while still typing it)
		close = Engine.Distance(word, candidate, max) <= max
			or (#candidate > #word and Engine.Distance(word, candidate:sub(1, #word), max) <= max)
		known[candidate] = close
	end
	return close
end

local function fuzzyLevel(word, words)
	local max = allowedTypos(word)
	if max == 0 then
		return 0
	end
	for i = 1, #words do
		if isClose(word, words[i], max) then
			return FUZZY_LEVEL
		end
	end
	return 0
end

-- Score of an item for the typed words, or nil if some word doesn't match.
local function score(item, query, fuzzy)
	local total = 0
	local words = query.words
	local keywordWords = item.keywordWords
	for w = 1, #words do
		local word = words[w]
		local level = wordLevel(word, item.nameWords)
		if level < EXACT and #keywordWords > 0 then
			local keywordLevel = wordLevel(word, keywordWords) - KEYWORD_PENALTY
			if keywordLevel > level then
				level = keywordLevel
			end
		end
		if level == 0 and fuzzy then
			level = math.max(fuzzyLevel(word, item.nameWords), fuzzyLevel(word, item.keywordWords))
		end
		if level == 0 then
			return nil
		end
		total = total + level
	end
	local text = query.text
	if item.name == text then
		total = total + BONUS_SAME_NAME
	elseif find(item.name, text, 1, true) == 1 then
		total = total + BONUS_NAME_PREFIX
	elseif #query.words > 1 and item.name:find(text, 1, true) then
		total = total + BONUS_NAME_CONTAINS
	end
	return total + item.weight * WEIGHT_POINTS
end

-- Candidates -----------------------------------------------------------------

-- Items of the enabled providers, limited by the query's @ filters, without
-- the categories the player turned off.
local function candidates(query)
	local Registry = ns.Registry
	local wanted -- providerID -> true (whole provider) or { categoryID = true }
	if #query.filters > 0 then
		wanted = {}
		for _, filter in ipairs(query.filters) do
			if not filter.category then
				wanted[filter.provider] = true
			elseif wanted[filter.provider] ~= true then
				wanted[filter.provider] = wanted[filter.provider] or {}
				wanted[filter.provider][filter.category] = true
			end
		end
	end
	local items = {}
	for _, record in ipairs(Registry.List()) do
		local want = not wanted or wanted[record.id]
		if want and record.enabled then
			for _, item in ipairs(ns.Index.Items(record.id)) do
				local category = item.category
				if (want == true or category and want[category])
					and (not category or Registry.IsCategoryEnabled(record.id, category)) then
					items[#items + 1] = item
				end
			end
		end
	end
	return items
end

-- Search ---------------------------------------------------------------------

local last -- { text, filters, version, matched } of the previous search

local function filtersKey(query)
	local parts = {}
	for _, filter in ipairs(query.filters) do
		parts[#parts + 1] = filter.provider .. "." .. tostring(filter.category)
	end
	return table.concat(parts, ",")
end

-- Best results so far -----------------------------------------------------------
-- Only the best `max` results are kept while scoring, in a heap whose root is
-- the worst of them: most entries are rejected with one comparison, and no
-- table is created per match. Only those few are sorted at the end.

-- true if result a goes before result b
local function better(scoreA, itemA, scoreB, itemB)
	if scoreA ~= scoreB then
		return scoreA > scoreB
	end
	local nameA, nameB = itemA.name, itemB.name
	if #nameA ~= #nameB then
		return #nameA < #nameB
	end
	if nameA ~= nameB then
		return nameA < nameB
	end
	return itemA.key < itemB.key
end

local Top = {}
Top.__index = Top

local function newTop(max)
	return setmetatable({ max = max, n = 0, scores = {}, items = {}, fuzzy = {} }, Top)
end

-- Is slot i worse than slot j (the heap keeps the worst on top)?
function Top:worse(i, j)
	return better(self.scores[j], self.items[j], self.scores[i], self.items[i])
end

function Top:swap(i, j)
	local scores, items, fuzzy = self.scores, self.items, self.fuzzy
	scores[i], scores[j] = scores[j], scores[i]
	items[i], items[j] = items[j], items[i]
	fuzzy[i], fuzzy[j] = fuzzy[j], fuzzy[i]
end

function Top:siftDown(i)
	local n = self.n
	while true do
		local left, worst = i * 2, i
		if left <= n and self:worse(left, worst) then
			worst = left
		end
		if left + 1 <= n and self:worse(left + 1, worst) then
			worst = left + 1
		end
		if worst == i then
			return
		end
		self:swap(i, worst)
		i = worst
	end
end

function Top:add(item, points, fuzzy)
	if self.max <= 0 then
		return
	end
	if self.n < self.max then
		local i = self.n + 1
		self.n = i
		self.scores[i], self.items[i], self.fuzzy[i] = points, item, fuzzy
		while i > 1 do
			local parent = math.floor(i / 2)
			if not self:worse(i, parent) then
				break
			end
			self:swap(i, parent)
			i = parent
		end
	elseif better(points, item, self.scores[1], self.items[1]) then
		self.scores[1], self.items[1], self.fuzzy[1] = points, item, fuzzy
		self:siftDown(1)
	end
end

-- Raises the score of an item already kept; false if it isn't there
function Top:boost(item, points)
	for i = 1, self.n do
		if self.items[i] == item then
			self.scores[i] = self.scores[i] + points
			return true
		end
	end
	return false
end

-- The kept results as { item, score, fuzzy }, best first
function Top:results()
	local results = {}
	for i = 1, self.n do
		results[i] = { item = self.items[i], score = self.scores[i], fuzzy = self.fuzzy[i] or nil }
	end
	table.sort(results, function(a, b)
		return better(a.score, a.item, b.score, b.item)
	end)
	return results
end

-- Searches the index.
--   opts.max: how many results (default: the player's option, or 50).
--   opts.zoneMapID: the open map. Results in it (or inside it) are kept apart
--     and come first, so they are never pushed out of the list by the rest.
-- When @ categories find nothing, their whole providers are searched instead
-- and stats.widened lists the categories that were widened.
-- Returns the results (best first; this zone's first) and some numbers for
-- /ms debug bench. Each result: { item, score, fuzzy, inZone }; result.item.entry
-- is the provider's entry (copy it before handing it to another addon).
function Engine.Search(query, opts)
	opts = opts or {}
	local max = opts.max or (ns.db and ns.db.options.maxResults) or Engine.DEFAULT_MAX
	local stats = { candidates = 0, narrowed = false, fuzzy = false, inZone = 0 }
	local zoneMapID = opts.zoneMapID
	local zoneTop, otherTop = newTop(max), newTop(max)
	local inZone = {} -- item -> true/false, worked out once per search
	local function topFor(item)
		if not zoneMapID then
			return otherTop
		end
		local inside = inZone[item]
		if inside == nil then
			inside = ns.IsMapInside(item.entry.mapID, zoneMapID)
			inZone[item] = inside
		end
		return inside and zoneTop or otherTop
	end
	local top = {
		add = function(_, item, points, fuzzy)
			topFor(item):add(item, points, fuzzy)
		end,
		boost = function(_, item, points)
			return topFor(item):boost(item, points)
		end,
	}

	if query.text == "" then
		-- Only @ filters: everything they select, best weight first
		if #query.filters > 0 then
			local pool = candidates(query)
			for i = 1, #pool do
				top:add(pool[i], pool[i].weight * WEIGHT_POINTS)
			end
			stats.candidates = #pool
		end
		last = nil
	else
		local key = filtersKey(query)
		local pool
		if last and last.version == ns.Index.version and last.filters == key
			and find(query.text, last.text, 1, true) == 1 then
			pool = last.matched
			stats.narrowed = true
		else
			pool = candidates(query)
		end
		stats.candidates = #pool

		local matched = {}
		for i = 1, #pool do
			local item = pool[i]
			local points = score(item, query, false)
			if points then
				matched[#matched + 1] = item
				top:add(item, points)
			end
		end
		last = { text = query.text, filters = key, version = ns.Index.version, matched = matched }

		if #matched < Engine.FUZZY_WHEN_FEWER_THAN then
			stats.fuzzy = true
			closeCache = {}
			local already = {}
			for i = 1, #matched do
				already[matched[i]] = true
			end
			local all = stats.narrowed and candidates(query) or pool
			for i = 1, #all do
				local item = all[i]
				if not already[item] then
					local points = score(item, query, true)
					if points then
						top:add(item, points, true)
					end
				end
			end
		end

		-- The player's alias for this exact text goes first, even if its name
		-- doesn't match the text ("ah" -> an auction house)
		local alias = ns.db and ns.db.aliases[query.text]
		if alias then
			local item
			for _, candidate in ipairs(candidates(query)) do
				if candidate.key == alias then
					item = candidate
					break
				end
			end
			if item and not top:boost(item, ALIAS_SCORE) then
				top:add(item, ALIAS_SCORE)
			end
		end
	end

	local results = zoneTop:results()
	-- Nothing in the chosen categories ("@zone eastern kingdoms", a continent):
	-- search their whole providers instead, and say so (stats.widened)
	if #results == 0 and otherTop.n == 0 and query.text ~= "" and not opts.noWiden then
		local narrowed, providers, whole = {}, {}, {}
		for _, filter in ipairs(query.filters) do
			if filter.category then
				narrowed[#narrowed + 1] = filter
			end
			if not providers[filter.provider] then
				providers[filter.provider] = true
				whole[#whole + 1] = { provider = filter.provider }
			end
		end
		if #narrowed > 0 then
			local wider = {}
			for k, v in pairs(query) do
				wider[k] = v
			end
			wider.filters = whole
			local widerResults, widerStats = Engine.Search(wider, {
				max = opts.max, zoneMapID = opts.zoneMapID, noWiden = true,
			})
			widerStats.widened = narrowed
			return widerResults, widerStats
		end
	end
	for _, result in ipairs(results) do
		result.inZone = true
	end
	stats.inZone = #results
	for _, result in ipairs(otherTop:results()) do
		if #results >= max then
			break
		end
		results[#results + 1] = result
	end
	stats.results = #results
	return results, stats
end

-- Forgets the previous search (no narrowing on the next one)
function Engine.Reset()
	last = nil
end

-- /ms debug search and bench ----------------------------------------------------

ns.RegisterDebug("search", function(text)
	local results = Engine.Search(ns.Query.Parse(text), { max = 10 })
	ns.Print(L.DEBUG_SEARCH_TITLE:format(text, #results))
	for i, result in ipairs(results) do
		local entry = result.item.entry
		DEFAULT_CHAT_FRAME:AddMessage(L.DEBUG_SEARCH_LINE:format(i, entry.name, result.item.provider,
			result.score, result.fuzzy and " ~" or ""))
	end
end, L.DEBUG_SEARCH)

ns.RegisterDebug("bench", function(text)
	local query = ns.Query.Parse(text)
	-- build the index first, so it is measured on its own
	local start = debugprofilestop()
	for _, record in ipairs(ns.Registry.List()) do
		ns.Index.Items(record.id)
	end
	local build = debugprofilestop() - start
	Engine.Reset()
	start = debugprofilestop()
	local results, stats = Engine.Search(query)
	local full = debugprofilestop() - start
	-- the same text again, one letter at a time, as when typing
	Engine.Reset()
	local typing, slowest = 0, 0
	for i = 1, #query.raw do
		local partial = ns.Query.Parse(query.raw:sub(1, i))
		local t = debugprofilestop()
		Engine.Search(partial)
		t = debugprofilestop() - t
		typing = typing + t
		if t > slowest then
			slowest = t
		end
	end
	local built, items = ns.Index.Stats()
	ns.Print(L.DEBUG_BENCH_RESULT:format(text, full, stats.candidates, #results, stats.fuzzy and L.YES or L.NO,
		#query.raw, typing, slowest, built, items, build))
end, L.DEBUG_BENCH)
