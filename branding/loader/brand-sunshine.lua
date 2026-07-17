-- brand-sunshine.lua — SunshineBSD boot-loader brand.
-- One job: the banner text drawn at the top of the loader menu.
--
-- Installed as /boot/lua/brand-sunshine.lua and selected with
-- loader_brand="sunshine" in loader.conf; the loader's drawer module
-- loads brand-<name>.lua on demand. SunshineBSD is a FreeBSD
-- derivative; see the repository documentation for attribution.

local drawer = require("drawer")

drawer.addBrand("sunshine", {
	graphic = {
		[[ ____                      _      _               ____   ____   ____  ]],
		[[/ ___|  _   _  _ __   ___ | |__  (_) _ __    ___ | __ ) / ___| |  _ \ ]],
		[[\___ \ | | | || '_ \ / __|| '_ \ | || '_ \  / _ \|  _ \ \___ \ | | | |]],
		[[ ___) || |_| || | | |\__ \| | | || || | | ||  __/| |_) | ___) || |_| |]],
		[[|____/  \__,_||_| |_||___/|_| |_||_||_| |_| \___||____/ |____/ |____/ ]],
	},
})

return true
