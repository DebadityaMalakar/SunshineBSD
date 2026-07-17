-- logo.lua — the SunshineBSD ASCII sunflower.
-- One job: provide the logo as an array of { text, color } lines.

local M = {}

-- Colors are names, not escape codes; render.lua owns the palette.
M.COLOR_NAMES = { yellow = true, brown = true, green = true }

local ART = {
    { text = [[     \  |  /]],     color = "yellow" },
    { text = [[  `.  \ | /  .']],  color = "yellow" },
    { text = [[   `\  ...  /']],   color = "yellow" },
    { text = [[ -==  (@@@)  ==-]], color = "brown"  },
    { text = [[   ./  '''  \.]],   color = "yellow" },
    { text = [[  .'  / | \  `.]],  color = "yellow" },
    { text = [[     /  |  \]],     color = "yellow" },
    { text = [[    __  |  __]],    color = "green"  },
    { text = [[    \_\_|_/_/]],    color = "green"  },
}

M.WIDTH = 0
for i = 1, #ART do
    if #ART[i].text > M.WIDTH then M.WIDTH = #ART[i].text end
end

-- get(): a fresh copy, every line padded to exactly M.WIDTH, so callers
-- can neither mutate the logo nor see ragged widths.
function M.get()
    local lines = {}
    for i = 1, #ART do
        local text = ART[i].text
        lines[i] = {
            text = text .. string.rep(" ", M.WIDTH - #text),
            color = ART[i].color,
        }
    end
    return lines
end

return M
