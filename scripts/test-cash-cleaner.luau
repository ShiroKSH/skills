local fs = require("@lune/fs")
local luau = require("@lune/luau")
local root = "examples/cash-cleaner/"
local cleaner = luau.load(fs.readFile(root .. "CleanerState.luau"))()
local tests = luau.load(fs.readFile(root .. "CleanerStateTests.luau"))()
local result = tests(cleaner)
for _, name in ipairs(result.checks) do print("PASS " .. name) end
luau.compile(fs.readFile(root .. "Runtime.server.luau"))
luau.compile(fs.readFile(root .. "IntegrationTest.luau"))
print("Cash Cleaner checks passed", result.passed)
