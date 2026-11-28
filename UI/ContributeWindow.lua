-- MapScout contributions: the window to send what was saved (the copy window,
-- UI/CopyWindow.lua, with the export text, Core/ContributeExport.lua).
-- It shows how many new records of each kind there are, the text to copy and
-- the address of the page where to paste it. «I sent it» marks those records
-- as sent; closing the window does not. When the text would not fit in the
-- form (Export.LIMIT), it goes in parts: «I sent it» opens the next one.
-- Opened with /ms contribute, the options' button and a link in the chat
-- (Contribute.ShareLink, in the login line): a chat link of type "addon"
-- that the game hands to EventRegistry's "SetItemRef" (or SetItemRef's hook,
-- where there is no EventRegistry). Nothing of the game is changed: no taint.

local _, ns = ...
local L = ns.L

local Contribute = ns.Contribute
local Export = Contribute.Export

local LINK = "addon:MapScout:contribute"
local LINK_COLOR = "ff71d5ff" -- as the game's links

-- What the window says of each kind, one line each: "· 3 NPCs"
local function countLines(counts)
	local lines = {}
	for _, kind in ipairs(Contribute.KINDS) do
		local n = counts[kind] or 0
		if n == 1 then
			lines[#lines + 1] = "· " .. L["CONTRIBUTE_KIND_" .. kind .. "_ONE"]
		elseif n > 1 then
			lines[#lines + 1] = "· " .. L["CONTRIBUTE_KIND_" .. kind]:format(n)
		end
	end
	return table.concat(lines, "\n")
end

-- What the copy window is given (nil when nothing is new)
function Contribute.ShareSpec()
	local text, n, counts, picked, left = Export.Collect(Export.LIMIT)
	if not text then
		return nil
	end
	local total = n + left
	local intro = (total == 1 and L.CONTRIBUTE_WINDOW_NEW_ONE or L.CONTRIBUTE_WINDOW_NEW:format(total)) .. "\n"
	if left > 0 then
		intro = intro .. L.CONTRIBUTE_WINDOW_PART .. "\n"
	end
	intro = intro .. countLines(counts) .. "\n\n" .. L.CONTRIBUTE_WINDOW_STEPS:format(ns.KeyName("CTRL"))
	return {
		title = L.CONTRIBUTE_WINDOW_TITLE,
		intro = intro,
		text = Export.Wrap(text),
		addressLabel = L.CONTRIBUTE_WINDOW_ADDRESS,
		address = L.CONTRIBUTE_FORM_URL,
		confirm = {
			label = L.CONTRIBUTE_WINDOW_SENT,
			onClick = function()
				local marked = Export.MarkSent(picked)
				ns.Print(marked == 1 and L.CONTRIBUTE_SENT_ONE or L.CONTRIBUTE_SENT)
				if left > 0 then
					Contribute.Share() -- the next part
				end
			end,
		},
	}
end

-- Opens the window; with nothing new, says so in the chat instead
function Contribute.Share()
	local spec = Contribute.ShareSpec()
	if spec then
		ns.CopyWindow.Open(spec)
	elseif Contribute.Count() > 0 then
		ns.Print(L.CONTRIBUTE_NOTHING_NEW)
	else
		ns.Print(L.CONTRIBUTE_NOTHING_SAVED)
	end
end

-- The chat link that opens the window: "Share them now!"
function Contribute.ShareLink(n)
	local text = n == 1 and L.CONTRIBUTE_SHARE_ONE or L.CONTRIBUTE_SHARE
	return ("|c%s|H%s|h%s|h|r"):format(LINK_COLOR, LINK, text)
end

local function onLink(link)
	if link == LINK then
		Contribute.Share()
		return true
	end
	return false
end
Contribute.OnLink = onLink

if EventRegistry and EventRegistry.RegisterCallback then
	EventRegistry:RegisterCallback("SetItemRef", function(_, link)
		onLink(link)
	end, Contribute)
elseif hooksecurefunc then
	hooksecurefunc("SetItemRef", onLink)
end
