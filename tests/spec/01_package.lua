-- The files the client and the CurseForge packager need.

describe("Package", function()
	it("TOC targets WoW Forever (Interface 16001)", function()
		local toc = readFile("SimplePetTarget.toc")
		eq(toc:match("## Interface:%s*(%d+)"), "16001", "Interface")
		eq(toc:match("## SavedVariables:%s*(%S+)"), "SimplePetTargetDB", "SavedVariables")
		ok(toc:match("## Version:%s*@project%-version@"), "Version is filled in by the packager")
	end)

	it("every file the TOC loads exists", function()
		local files, problems = TocFiles()
		eq(table.concat(problems, "; "), "", "problems")
		ok(#files > 3, "expected the TOC to load several files")
	end)

	it("every Lua file the TOC loads compiles", function()
		for _, rel in ipairs((TocFiles())) do
			if rel:match("%.lua$") then
				local src = readFile(rel)
				local chunk, err = loadstring(src, "@" .. rel)
				ok(chunk, err)
			end
		end
	end)

	it("the addon's code loads last, after LibEditMode and its XML", function()
		local files = TocFiles()
		eq(files[#files], "SimplePetTarget.lua", "last file")
		eq(files[1], "Libs/LibEditMode/namespaced.lua", "first file")
	end)

	it("the package leaves out tests, assets and the README", function()
		local pkgmeta = readFile(".pkgmeta")
		for _, ignored in ipairs({ "tests", "assets", "README.md", "CLAUDE.md", ".github", ".luacheckrc" }) do
			ok(pkgmeta:find("%- " .. ignored:gsub("%p", "%%%0") .. "%s"), ".pkgmeta ignores " .. ignored)
		end
	end)
	it("the XML templates define every key the Lua uses", function()
		local xml = readFile("SimplePetTarget.xml")
		local debuffStart = xml:find('name="SimplePetTargetDebuffTemplate"', 1, true)
		local frameStart = xml:find('name="SimplePetTargetFrameTemplate"', 1, true)
		ok(debuffStart and frameStart and debuffStart < frameStart, "both templates, the debuff one first")
		local debuff, frame = xml:sub(debuffStart, frameStart - 1), xml:sub(frameStart)
		local function count(block, key)
			return select(2, block:gsub('parentKey="' .. key .. '"', ""))
		end
		for _, key in ipairs({ "Icon", "Border", "Cooldown" }) do
			eq(count(debuff, key), 1, "debuff template " .. key)
		end
		for _, key in ipairs({ "Portrait", "PortraitRed", "Name", "HealthBar", "ManaBar", "DeadText", "UnconsciousText", "HealthBarMask", "ManaBarMask", "Spark" }) do
			eq(count(frame, key), 1, "frame template " .. key)
		end
		for _, key in ipairs({ "TextString", "LeftText", "RightText" }) do
			eq(count(frame, key), 2, "frame template " .. key .. ", one per bar")
		end
		ok(frame:match('^[^>]*virtual="true"'), "the frame template is virtual")
		ok(frame:match('^[^>]*inherits="[^"]*SecureUnitButtonTemplate'), "the frame template is a secure unit button")
	end)
end)
