-- Runs the tests in tests/spec against the addon loaded into the WoW stand-in (tests/wowmock.lua).
--
--   lua tests/run.lua [--junit path] [spec name ...]
--
-- Needs Lua 5.1 or LuaJIT, like the game. Every test gets a fresh game: the stand-in, then every
-- Lua file the TOC loads, in TOC order. Results go to the console; with --junit also to a JUnit
-- file, and on GitHub Actions to the job summary, with failures annotated on their lines.

local ROOT = (arg and arg[0] or ""):match("^(.*)[/\\]tests[/\\][^/\\]+$") or "."
local ADDON_NAME = "SimplePetTarget"

local junitPath
local only = {}
do
	local i = 1
	while arg and arg[i] do
		if arg[i] == "--junit" then
			junitPath = arg[i + 1]
			i = i + 1
		else
			only[arg[i]] = true
		end
		i = i + 1
	end
end

local function path(rel) return ROOT .. "/" .. rel:gsub("\\", "/") end

local function readFile(rel)
	local f = io.open(path(rel), "rb")
	if not f then return nil end
	local s = f:read("*a")
	f:close()
	return s
end

---------------------------------------------------------------------------------------------------
-- The TOC's load order
---------------------------------------------------------------------------------------------------

-- The files the client loads for the TOC, in order, following XML Script and Include tags.
-- Returns them with any problems found (missing files).
local function TocFiles()
	local files, problems = {}, {}
	local function addXml(rel)
		local xml = readFile(rel)
		if not xml then
			problems[#problems + 1] = "missing file " .. rel
			return
		end
		files[#files + 1] = rel
		local dir = rel:match("^(.*)[/\\]") or ""
		xml = xml:gsub("<!%-%-.-%-%->", "")
		for tag, file in xml:gmatch("<(%a+)%s+file%s*=%s*[\"']([^\"']+)[\"']") do
			local child = (dir ~= "" and dir .. "/" or "") .. file:gsub("\\", "/")
			if tag == "Script" then
				if readFile(child) then files[#files + 1] = child else problems[#problems + 1] = "missing file " .. child .. " (from " .. rel .. ")" end
			elseif tag == "Include" then
				addXml(child)
			end
		end
	end
	local toc = readFile(ADDON_NAME .. ".toc")
	if not toc then
		return files, { "missing " .. ADDON_NAME .. ".toc" }
	end
	for line in toc:gmatch("[^\r\n]+") do
		line = line:match("^%s*(.-)%s*$")
		if line ~= "" and not line:match("^#") then
			local rel = line:gsub("\\", "/")
			if rel:match("%.xml$") then
				addXml(rel)
			elseif readFile(rel) then
				files[#files + 1] = rel
			else
				problems[#problems + 1] = "missing file " .. rel
			end
		end
	end
	return files, problems
end

---------------------------------------------------------------------------------------------------
-- A fresh game for each test
---------------------------------------------------------------------------------------------------

local BASE = {}
for k, v in pairs(_G) do BASE[k] = v end

-- Chunk names are relative to the repository, so errors point at files GitHub can annotate.
local function loadInto(env, rel, ...)
	local src = readFile(rel)
	if not src then error("missing file " .. rel, 0) end
	local chunk, err = loadstring(src, "@" .. rel)
	if not chunk then error(err, 0) end
	setfenv(chunk, env)
	return chunk(...)
end

-- setup(G), if given, runs after the stand-in loads and before the addon does.
local function NewGame(setup)
	local env = setmetatable({}, { __index = BASE })
	env._G = env
	loadInto(env, "tests/wowmock.lua")
	if setup then setup(env) end
	local ns = {}
	for _, rel in ipairs((TocFiles())) do
		if rel:match("%.lua$") then
			loadInto(env, rel, ADDON_NAME, ns)
		end
	end
	env.NS = ns
	return env
end

---------------------------------------------------------------------------------------------------
-- Tests and assertions
---------------------------------------------------------------------------------------------------

local tests = {}
local currentSpec, currentGroup

local api = {}
function api.describe(name, fn)
	local saved = currentGroup
	currentGroup = saved and (saved .. " › " .. name) or name
	fn()
	currentGroup = saved
end
function api.it(name, fn)
	tests[#tests + 1] = { spec = currentSpec, group = currentGroup or currentSpec, name = name, fn = fn }
end

local function fmt(v)
	if type(v) == "string" then return string.format("%q", v) end
	return tostring(v)
end
function api.eq(actual, expected, what)
	if actual ~= expected then
		error((what and what .. ": " or "") .. "expected " .. fmt(expected) .. ", got " .. fmt(actual), 2)
	end
end
function api.ok(value, what)
	if not value then error((what or "expected a true value") .. ", got " .. fmt(value), 2) end
end
function api.no(value, what)
	if value then error((what or "expected a false value") .. ", got " .. fmt(value), 2) end
end
function api.fails(fn, pattern, what)
	local ok, err = pcall(fn)
	if ok then error((what or "expected an error") .. ", but there was none", 2) end
	if pattern and not tostring(err):find(pattern) then
		error((what or "error") .. ": expected one matching " .. fmt(pattern) .. ", got " .. fmt(tostring(err)), 2)
	end
end
-- Everything the stand-in recorded as going wrong: Lua errors, protected calls refused in combat,
-- and rule breaks such as touching locked aura buttons. "" when there were none.
function api.Problems(G)
	local list = {}
	for _, kind in ipairs({ "ERRORS", "BLOCKED", "VIOLATIONS" }) do
		for _, e in ipairs(G[kind]) do list[#list + 1] = kind .. ": " .. e end
	end
	return table.concat(list, "\n")
end
-- A font string's text, read through any secret.
function api.Text(fontString)
	local v = rawget(fontString, "__text")
	if type(v) == "table" then v = rawget(v, "__value") end
	return v
end
-- A fresh game, logged in, with the pet out.
function api.Start(setup)
	local G = NewGame(setup)
	G.Login()
	G.SetPet(true)
	G.Tick()
	return G
end
api.NewGame = NewGame
api.TocFiles = TocFiles
api.readFile = readFile

local function loadSpecs()
	local names = {}
	local listing = io.popen((package.config:sub(1, 1) == "\\" and 'dir /b "' .. path("tests/spec"):gsub("/", "\\") .. '"' or 'ls "' .. path("tests/spec") .. '"'))
	for name in listing:lines() do
		if name:match("%.lua$") then names[#names + 1] = name end
	end
	listing:close()
	table.sort(names)
	for _, name in ipairs(names) do
		local spec = name:gsub("%.lua$", "")
		if not next(only) or only[spec] then
			currentSpec = spec
			local env = setmetatable({}, { __index = function(_, k) if api[k] ~= nil then return api[k] end return BASE[k] end })
			loadInto(env, "tests/spec/" .. name)
		end
	end
end

---------------------------------------------------------------------------------------------------
-- Running and reporting
---------------------------------------------------------------------------------------------------

local function where(trace)
	local file, line = trace:match("(tests/spec/[%w_%-]+%.lua):(%d+):")
	return file, tonumber(line)
end

local function run()
	loadSpecs()
	local passed, failed = 0, 0
	local clock = os.clock
	print(string.format("Running %d tests\n", #tests))
	local lastGroup
	for _, t in ipairs(tests) do
		if t.group ~= lastGroup then
			print(t.group)
			lastGroup = t.group
		end
		local start = clock()
		local ok, err = xpcall(function() t.fn() end, function(e)
			return { message = tostring(e), trace = debug.traceback(tostring(e), 2) }
		end)
		t.time = clock() - start
		if ok then
			passed = passed + 1
			print("  ok      " .. t.name)
		else
			failed = failed + 1
			t.failure = err
			t.file, t.line = where(err.message)
			if not t.file then t.file, t.line = where(err.trace) end
			print("  FAILED  " .. t.name)
			print("          " .. err.message:gsub("\n", "\n          "))
		end
	end
	print(string.format("\n%d passed, %d failed", passed, failed))
	return passed, failed
end

local function xmlEscape(s)
	return (tostring(s):gsub("&", "&amp;"):gsub("<", "&lt;"):gsub(">", "&gt;"):gsub('"', "&quot;"))
end

local function writeJUnit(file, passed, failed)
	local out = assert(io.open(file, "w"))
	local total = 0
	for _, t in ipairs(tests) do total = total + t.time end
	out:write('<?xml version="1.0" encoding="UTF-8"?>\n')
	out:write(string.format('<testsuites name="Simple Pet Target" tests="%d" failures="%d" time="%.3f">\n', passed + failed, failed, total))
	local bySpec, order = {}, {}
	for _, t in ipairs(tests) do
		if not bySpec[t.spec] then bySpec[t.spec] = {}; order[#order + 1] = t.spec end
		table.insert(bySpec[t.spec], t)
	end
	for _, spec in ipairs(order) do
		local list, fails = bySpec[spec], 0
		for _, t in ipairs(list) do if t.failure then fails = fails + 1 end end
		out:write(string.format('  <testsuite name="%s" tests="%d" failures="%d">\n', xmlEscape(spec), #list, fails))
		for _, t in ipairs(list) do
			out:write(string.format('    <testcase classname="%s" name="%s" time="%.3f"', xmlEscape(t.group), xmlEscape(t.name), t.time))
			if t.failure then
				out:write(string.format('>\n      <failure message="%s">%s</failure>\n    </testcase>\n', xmlEscape(t.failure.message), xmlEscape(t.failure.trace)))
			else
				out:write("/>\n")
			end
		end
		out:write("  </testsuite>\n")
	end
	out:write("</testsuites>\n")
	out:close()
end

-- GitHub Actions: a table of every test in the job summary, and an annotation on each failure.
local function writeGitHub(passed, failed)
	local summaryPath = os.getenv("GITHUB_STEP_SUMMARY")
	if os.getenv("GITHUB_ACTIONS") ~= "true" then return end
	for _, t in ipairs(tests) do
		if t.failure then
			local msg = (t.group .. " › " .. t.name .. ": " .. t.failure.message):gsub("%%", "%%25"):gsub("\r", "%%0D"):gsub("\n", "%%0A")
			if t.file then
				print(string.format("::error file=%s,line=%d,title=Test failed::%s", t.file, t.line or 1, msg))
			else
				print("::error title=Test failed::" .. msg)
			end
		end
	end
	if not summaryPath then return end
	local out = assert(io.open(summaryPath, "a"))
	out:write(string.format("## WoW API tests: %s %d passed, %d failed\n\n", failed == 0 and "✅" or "❌", passed, failed))
	out:write("| | Area | Test |\n|---|---|---|\n")
	for _, t in ipairs(tests) do
		local name = t.name:gsub("|", "\\|")
		if t.failure then
			name = name .. "<br>`" .. t.failure.message:gsub("\n", " "):gsub("|", "\\|"):gsub("`", "'") .. "`"
		end
		out:write(string.format("| %s | %s | %s |\n", t.failure and "❌" or "✅", t.group:gsub("|", "\\|"), name))
	end
	out:write("\n")
	out:close()
end

local passed, failed = run()
if junitPath then writeJUnit(junitPath, passed, failed) end
writeGitHub(passed, failed)
os.exit(failed == 0 and #tests > 0 and 0 or 1)
