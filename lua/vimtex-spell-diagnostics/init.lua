local M = {}

-- default configuration
local default_config = {
	enabled = true,
	severity = {
		bad = vim.diagnostic.severity.ERROR,
		caps = vim.diagnostic.severity.WARN,
		rare = vim.diagnostic.severity.HINT,
		loc = vim.diagnostic.severity.INFO,
	},
	debounce_time = 500,
	check_on = {
		"BufReadPost",
		"BufWritePost",
		"InsertLeave",
	},
}

local config = {}
local namespace = vim.api.nvim_create_namespace("vimtex_spell_diagnostics")
local debounce_timer = nil

-- check if a word should be spell-checked based on the syntax at the pos
local function should_spellcheck_position(lnum, col)
	local synstack = vim.fn.synstack(lnum, col)

	if #synstack == 0 then
		return true -- plain text
	end

	-- get the innermost syntax group
	local innermost = synstack[#synstack]
	local innermost_name = vim.fn.synIDattr(innermost, "name")

	-- skip math regions entirely
	if innermost_name:match("^texMath") or innermost_name:match("^texDisplayMath") then
		return false
	end

	-- skip comments
	if innermost_name:match("^texComment") then
		return false
	end

	-- check if we're in a spellable region or text content
	for i = #synstack, 1, -1 do
		local syn = synstack[i]
		local synname = vim.fn.synIDattr(syn, "name")

		-- explicitly spellable regions
		if
			vim.fn.synIDattr(syn, "spell") == "1"
			or synname:match("^texPartArgTitle")
			or synname:match("^texTitle")
			or synname:match("^texSection")
			or synname:match("^texChapterTitle")
			or synname:match("^texAuthorTitle")
			or synname:match("^texDocType")
			or synname:match("^texDocTypeArgs")
			or synname:match("^texArg") -- command arguments
		then
			return true
		end

		-- skip only specific non-text elements
		if
			synname:match("^texStatement")
			or synname:match("^texBeginEnd")
			or synname:match("^texDelimiter")
			or synname:match("^texInputFile")
			or synname:match("^texSpecialChar")
		then
			return false
		end
	end

	-- if we're inside a command but not in a skippable region, check it
	-- this handles text inside \flashcard{...}{...} etc
	return true
end

-- check if position is at a latex command name (not its arguments)
local function is_command_name(line, col)
	-- check if preceded by backslash
	if col > 1 and line:sub(col - 1, col - 1) == "\\" then
		return true
	end

	-- check if we're part of a command name (after the backslash)
	local start = col
	while start > 1 and line:sub(start - 1, start - 1):match("[%a@]") do
		start = start - 1
	end
	if start > 1 and line:sub(start - 1, start - 1) == "\\" then
		return true
	end

	return false
end

-- collect the spelling issues in current buffer
local function collect_spelling_issues(bufnr)
	bufnr = bufnr or vim.api.nvim_get_current_buf()

	-- only check if spell is enabled
	if not vim.wo.spell then
		return {}
	end

	local diags = {}
	local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)

	-- iterate over all the lines and words
	for lnum, line in ipairs(lines) do
		for col = 1, #line do
			local char = line:sub(col, col)

			-- only check at word boundaries
			if col == 1 or not line:sub(col - 1, col - 1):match("[%a']") then
				if char:match("[%a]") then
					-- skip latex command names (but not their arguments)
					if is_command_name(line, col) then
						goto continue
					end

					-- find word extent
					local word_end = col
					while word_end <= #line and line:sub(word_end, word_end):match("[%a']") do
						word_end = word_end + 1
					end
					local word = line:sub(col, word_end - 1)

					-- check if position should be spell-checked
					if should_spellcheck_position(lnum, col) and #word > 0 then
						local res = vim.fn.spellbadword(word)
						local bad, kind = res[1], res[2]

						if bad ~= "" and bad == word then
							-- default to bad
							if kind == "" or kind == nil then
								kind = "bad"
							end

							-- map severity
							local sev = config.severity.bad
							if kind == "bad" then
								sev = config.severity.bad or vim.diagnostic.severity.WARN
							elseif kind == "local" then
								sev = config.severity.loc or vim.diagnostic.severity.INFO
							elseif kind == "caps" then
								sev = config.severity.caps or vim.diagnostic.severity.WARN
							elseif kind == "rare" then
								sev = config.severity.rare or vim.diagnostic.severity.HINT
							end
							table.insert(diags, {
								lnum = lnum - 1,
								col = col - 1,
								end_lnum = lnum - 1,
								end_col = word_end - 1,
								severity = sev,
								message = string.format("Spelling: %s (%s)", bad, kind),
								source = "vimtex-spell",
							})
						end
					end
					::continue::
				end
			end
		end
	end

	return diags
end

-- diagnostics for buffer
local function update_diagnostics(bufnr)
	if not config.enabled then
		return
	end

	vim.schedule(function()
		if vim.api.nvim_buf_is_valid(bufnr) then
			local ok, diags = pcall(collect_spelling_issues, bufnr)
			if ok then
				vim.diagnostic.set(namespace, bufnr, diags, {})
			end
		end
	end)
end

-- debounced update
local function debounced_update(bufnr)
	if debounce_timer then
		vim.fn.timer_stop(debounce_timer)
	end
	debounce_timer = vim.defer_fn(function()
		update_diagnostics(bufnr)
		debounce_timer = nil
	end, config.debounce_time)
end

-- clear diagnostics for buffer
local function clear_diagnostics(bufnr)
	bufnr = bufnr or vim.api.nvim_get_current_buf()
	vim.diagnostic.set(namespace, bufnr, {}, {})
end

-- setup autocmds
local function setup_autocmds()
	local augroup = vim.api.nvim_create_augroup("VimtexSpellDiagnostics", { clear = true })

	vim.api.nvim_create_autocmd(config.check_on, {
		group = augroup,
		pattern = "*.tex",
		callback = function(args)
			debounced_update(args.buf)
		end,
	})

	-- clear on buffer unload
	vim.api.nvim_create_autocmd("BufUnload", {
		group = augroup,
		pattern = "*.tex",
		callback = function(args)
			clear_diagnostics(args.buf)
		end,
	})
end

function M.enable()
	config.enabled = true
	setup_autocmds()
	-- update all tex buffers
	for _, buf in ipairs(vim.api.nvim_list_bufs()) do
		if vim.bo[buf].filetype == "tex" then
			update_diagnostics(buf)
		end
	end
end

function M.disable()
	config.enabled = false
	-- clear all diagnostics
	for _, buf in ipairs(vim.api.nvim_list_bufs()) do
		if vim.bo[buf].filetype == "tex" then
			clear_diagnostics(buf)
		end
	end
	-- clear autocmds
	vim.api.nvim_create_augroup("VimtexSpellDiagnostics", { clear = true })
end

function M.toggle()
	if config.enabled then
		M.disable()
	else
		M.enable()
	end
end

-- refresh current buffer
function M.refresh(bufnr)
	bufnr = bufnr or vim.api.nvim_get_current_buf()
	if vim.bo[bufnr].filetype == "tex" then
		update_diagnostics(bufnr)
	end
end

-- setup function
function M.setup(user_config)
	config = vim.tbl_deep_extend("force", default_config, user_config or {})

	-- create user commands
	vim.api.nvim_create_user_command("VimtexSpellEnable", M.enable, {})
	vim.api.nvim_create_user_command("VimtexSpellDisable", M.disable, {})
	vim.api.nvim_create_user_command("VimtexSpellToggle", M.toggle, {})
	vim.api.nvim_create_user_command("VimtexSpellRefresh", function()
		M.refresh()
	end, {})

	if config.enabled then
		setup_autocmds()
	end
end

return M
