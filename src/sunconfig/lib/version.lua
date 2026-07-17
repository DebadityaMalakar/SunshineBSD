-- version.lua — the single place the sunconfig version is defined.

local M = {}

M.VERSION = "0.1.0"
M.NAME = "SunshineBSD sunconfig"

function M.line()
    return M.NAME .. " " .. M.VERSION
end

return M
