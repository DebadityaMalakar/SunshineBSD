-- gfx-sunshine.lua — SunshineBSD boot-loader brand and mascot.
-- One job: the two graphics the loader menu draws — the small text
-- wordmark ("brand") and the larger ASCII-art picture ("logo", upstream
-- default: the red FreeBSD orb).
--
-- Both live in one file because of how the loader resolves them: for
-- loader_brand="sunshine" and loader_logo="sunshine", drawer.lua's
-- getBranddef/getLogodef both call processFile("sunshine"), which
-- try_includes *only* 'gfx-sunshine' — never 'brand-sunshine' — and
-- registers whichever of the returned table's "brand"/"logo" keys are
-- present in a single pass. A separate brand-sunshine.lua is dead code:
-- once gfx-sunshine.lua resolves successfully (even registering only
-- the logo), drawer.lua's legacy try_include('brand-' .. name) fallback
-- never runs, and the brand silently reverts to stock FreeBSD. Confirmed
-- by booting a build with the two split apart: the mascot came through
-- correctly but the wordmark did not.
--
-- Installed as /boot/lua/gfx-sunshine.lua and selected with
-- loader_brand="sunshine" and loader_logo="sunshine" in loader.conf.
-- The mascot is the same sunflower as flesk's src/flesk/lib/logo.lua,
-- redrawn in golden/yellow ANSI to match the loader's inline-color
-- convention (see gfx-orb.lua upstream). SunshineBSD is a FreeBSD
-- derivative; see the repository documentation for attribution.

local GOLD = "\027[93m"
local RESET = "\027[0m"

return {
	brand = {
		graphic = {
		    GOLD .. [[ ____                      _      _               ____   ____   ____  ]] .. RESET,
		    GOLD .. [[/ ___|  _   _  _ __   ___ | |__  (_) _ __    ___ | __ ) / ___| |  _ \ ]] .. RESET,
		    GOLD .. [[\___ \ | | | || '_ \ / __|| '_ \ | || '_ \  / _ \|  _ \ \___ \ | | | |]] .. RESET,
		    GOLD .. [[ ___) || |_| || | | |\__ \| | | || || | | ||  __/| |_) | ___) || |_| |]] .. RESET,
		    GOLD .. [[|____/  \__,_||_| |_||___/|_| |_||_||_| |_| \___||____/ |____/ |____/ ]] .. RESET,
		},
	},
	logo = {
		graphic = {
		    "\027[93m     \\  |  /   \027[0m",
		    "\027[93m  `.  \\ | /  .' \027[0m",
		    "\027[93m   `\\  ...  /'  \027[0m",
		    "\027[33m -==  (@@@)  ==-\027[0m",
		    "\027[93m   ./  '''  \\.  \027[0m",
		    "\027[93m  .'  / | \\  `. \027[0m",
		    "\027[93m     /  |  \\    \027[0m",
		    "\027[33m    __  |  __   \027[0m",
		    "\027[33m    \\_\\_|_/_/   \027[0m",
		},
		shift = {x = 6, y = 3},
	},
}
