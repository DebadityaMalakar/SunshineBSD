-- render.lua — compose logo and info lines into terminal output.
-- One job: pure text layout. No I/O, no system queries.

local M = {}

M.GAP = "  "
M.MAX_LINES = 64
M.MAX_TITLE_LEN = 96

M.PALETTE = {
    yellow = "\27[93m",
    brown  = "\27[33m",
    green  = "\27[32m",
}
M.BOLD = "\27[1m"
M.RESET = "\27[0m"

local function fail(msg)
    error("flesk.render.compose: " .. msg, 3)
end

local function check_logo(logo)
    if type(logo) ~= "table" then fail("logo must be a table") end
    if #logo == 0 or #logo > M.MAX_LINES then
        fail("logo must have between 1 and " .. M.MAX_LINES .. " lines")
    end
    for i = 1, #logo do
        local line = logo[i]
        if type(line) ~= "table" or type(line.text) ~= "string" then
            fail("logo line " .. i .. " must be a table with a text string")
        end
        if not M.PALETTE[line.color] then
            fail("logo line " .. i .. " has unknown color " .. tostring(line.color))
        end
        if line.text:find("[\27\t\n]") then
            fail("logo line " .. i .. " contains control characters")
        end
    end
end

local function check_rows(rows)
    if type(rows) ~= "table" then fail("rows must be a table") end
    if #rows > M.MAX_LINES - 2 then
        fail("rows must have at most " .. (M.MAX_LINES - 2) .. " entries")
    end
    for i = 1, #rows do
        local row = rows[i]
        if type(row) ~= "table"
            or type(row.label) ~= "string" or #row.label == 0
            or type(row.value) ~= "string" or #row.value == 0 then
            fail("row " .. i .. " must have non-empty label and value strings")
        end
    end
end

-- compose(logo, title, rows, opts) -> array of output lines.
--   logo: array of { text, color } (see logo.lua)
--   title: e.g. "user@host"
--   rows: array of { label, value }
--   opts: { color = boolean }
function M.compose(logo, title, rows, opts)
    check_logo(logo)
    if type(title) ~= "string" or #title == 0 or #title > M.MAX_TITLE_LEN then
        fail("title must be a non-empty string (max " .. M.MAX_TITLE_LEN .. " chars)")
    end
    check_rows(rows)
    if type(opts) ~= "table" or type(opts.color) ~= "boolean" then
        fail("opts must be a table with a boolean color field")
    end

    local width = 0
    for i = 1, #logo do
        if #logo[i].text > width then width = #logo[i].text end
    end

    local right = {}
    if opts.color then
        right[1] = M.BOLD .. title .. M.RESET
    else
        right[1] = title
    end
    right[2] = string.rep("-", #title)
    for i = 1, #rows do
        local label = rows[i].label
        if opts.color then
            label = M.BOLD .. M.PALETTE.green .. label .. M.RESET
        end
        right[2 + i] = label .. ": " .. rows[i].value
    end

    local total = #logo
    if #right > total then total = #right end
    if total > M.MAX_LINES then fail("output exceeds " .. M.MAX_LINES .. " lines") end

    local blank = string.rep(" ", width)
    local out = {}
    for i = 1, total do
        local left = blank
        if logo[i] then
            local text = logo[i].text .. string.rep(" ", width - #logo[i].text)
            if opts.color then
                left = M.PALETTE[logo[i].color] .. text .. M.RESET
            else
                left = text
            end
        end
        local line = left .. M.GAP .. (right[i] or "")
        out[i] = (line:gsub("%s+$", ""))
    end
    return out
end

return M
