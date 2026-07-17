-- build.lua — the compile pipeline orchestrator.
-- One job: wire loader → schema → generators → fs into a staging tree.
-- All content is computed BEFORE any file is written, so an invalid
-- configuration never produces partial output.

local loader = require("loader")
local schema = require("schema")
local fs = require("fs")
local gen_rcconf = require("gen_rcconf")
local gen_zoneinfo = require("gen_zoneinfo")
local gen_meta = require("gen_meta")
local gen_runit = require("gen_runit")

local M = {}

M.MANIFEST_NAME = "MANIFEST"

-- Loads and validates only. Returns the normalized config and the list of
-- source files, or nil plus an array of errors.
function M.check(confdir)
    local loaded, lerr = loader.load_dir(confdir)
    if not loaded then return nil, { lerr } end
    local cfg, errors = schema.validate(loaded.values)
    if not cfg then return nil, errors end
    return cfg, loaded.sources
end

local function parent_dir(path)
    return path:match("^(.*)/[^/]+$")
end

-- Compiles confdir into a staging tree under outdir.
-- Returns the sorted array of files written (relative paths), or
-- nil plus an array of errors.
function M.build(confdir, outdir)
    if type(outdir) ~= "string" or #outdir == 0 then
        return nil, { "build: outdir must be a non-empty string" }
    end
    local cfg, errors = M.check(confdir)
    if not cfg then return nil, errors end

    -- Compute everything first (no I/O yet).
    local ok, files_or_err = pcall(function()
        local runit = gen_runit.generate(cfg)
        local files = {
            { path = "etc/rc.conf", content = gen_rcconf.generate(cfg), exec = false },
            { path = "etc/sunshine.conf", content = gen_meta.generate(cfg), exec = false },
            { path = "var/db/zoneinfo", content = gen_zoneinfo.generate(cfg), exec = false },
        }
        for i = 1, #runit.files do
            files[#files + 1] = runit.files[i]
        end
        table.sort(files, function(a, b) return a.path < b.path end)
        return { files = files, logdirs = runit.logdirs }
    end)
    if not ok then return nil, { tostring(files_or_err) } end
    local plan = files_or_err

    -- Now write, checking every step.
    local mkok, mkerr = fs.mkdir_p(outdir)
    if not mkok then return nil, { mkerr } end

    local written = {}
    for i = 1, #plan.files do
        local entry = plan.files[i]
        local target = outdir .. "/" .. entry.path
        local parent = parent_dir(target)
        if parent then
            local pok, perr = fs.mkdir_p(parent)
            if not pok then return nil, { perr } end
        end
        local wok, werr = fs.write_file(target, entry.content)
        if not wok then return nil, { werr } end
        if entry.exec then
            local xok, xerr = fs.make_executable(target)
            if not xok then return nil, { xerr } end
        end
        written[#written + 1] = entry.path
    end

    for i = 1, #plan.logdirs do
        local dok, derr = fs.mkdir_p(outdir .. "/" .. plan.logdirs[i])
        if not dok then return nil, { derr } end
    end

    local manifest = table.concat(written, "\n") .. "\n"
    local mok, merr = fs.write_file(outdir .. "/" .. M.MANIFEST_NAME, manifest)
    if not mok then return nil, { merr } end

    return written
end

return M
