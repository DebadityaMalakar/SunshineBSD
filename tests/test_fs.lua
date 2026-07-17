-- test_fs.lua — tests fs.lua and nothing else.
-- Uses tests/tmp/fs as scratch space.

package.path = "src/sunconfig/lib/?.lua;tests/?.lua;" .. package.path
local T = require("helpers")
local fs = require("fs")

local BASE = "tests/tmp/fs"
assert(fs.remove_tree(BASE))

T.suite("fs")

-- mkdir_p / exists / is_dir --------------------------------------------

T.case("mkdir_p creates nested directories", function()
    T.ok(fs.mkdir_p(BASE .. "/a/b/c"))
    T.eq(fs.is_dir(BASE .. "/a/b/c"), true)
    T.eq(fs.exists(BASE .. "/a/b/c"), true)
end)

T.case("mkdir_p on an existing directory succeeds", function()
    T.ok(fs.mkdir_p(BASE .. "/a/b/c"))
end)

T.case("exists is false for missing paths", function()
    T.eq(fs.exists(BASE .. "/missing"), false)
end)

T.case("is_dir is false for regular files", function()
    T.ok(fs.write_file(BASE .. "/plain.txt", "hi"))
    T.eq(fs.is_dir(BASE .. "/plain.txt"), false)
    T.eq(fs.exists(BASE .. "/plain.txt"), true)
end)

T.case("mkdir_p refuses when the path is an existing file", function()
    local ok, err = fs.mkdir_p(BASE .. "/plain.txt")
    T.not_ok(ok)
    T.match(err, "not a directory")
end)

T.case("path checks reject bad arguments", function()
    T.not_ok((fs.mkdir_p(nil)))
    T.not_ok((fs.mkdir_p("")))
    T.not_ok((fs.mkdir_p('bad"quote')))
    T.not_ok((fs.exists(123)))
end)

-- write_file / read_file -----------------------------------------------

T.case("write_file round-trips text", function()
    T.ok(fs.write_file(BASE .. "/t.txt", "line1\nline2\n"))
    T.eq(fs.read_file(BASE .. "/t.txt"), "line1\nline2\n")
end)

T.case("write_file round-trips binary bytes", function()
    local blob = "\0\1\2\255\254 binary \n\r\t"
    T.ok(fs.write_file(BASE .. "/bin.dat", blob))
    T.eq(fs.read_file(BASE .. "/bin.dat"), blob)
end)

T.case("write_file round-trips empty content", function()
    T.ok(fs.write_file(BASE .. "/empty", ""))
    T.eq(fs.read_file(BASE .. "/empty"), "")
end)

T.case("write_file overwrites previous content", function()
    T.ok(fs.write_file(BASE .. "/t.txt", "new"))
    T.eq(fs.read_file(BASE .. "/t.txt"), "new")
end)

T.case("write_file rejects non-string content", function()
    local ok, err = fs.write_file(BASE .. "/t.txt", { 1 })
    T.not_ok(ok)
    T.match(err, "content must be a string")
end)

T.case("write_file rejects oversized content", function()
    local ok, err = fs.write_file(BASE .. "/big", string.rep("a", fs.MAX_FILE_SIZE + 1))
    T.not_ok(ok)
    T.match(err, "exceeds")
end)

T.case("write_file into a missing directory fails", function()
    local ok, err = fs.write_file(BASE .. "/no/such/dir/f", "x")
    T.not_ok(ok)
    T.match(err, "cannot open")
end)

T.case("read_file on a missing file fails", function()
    local ok, err = fs.read_file(BASE .. "/missing.txt")
    T.not_ok(ok)
    T.match(err, "cannot open")
end)

-- make_executable ------------------------------------------------------

T.case("make_executable succeeds on an existing file", function()
    T.ok(fs.write_file(BASE .. "/script.sh", "#!/bin/sh\nexit 0\n"))
    T.ok(fs.make_executable(BASE .. "/script.sh"))
end)

T.case("make_executable fails on a missing file", function()
    local ok, err = fs.make_executable(BASE .. "/nope.sh")
    T.not_ok(ok)
    T.match(err, "does not exist")
end)

-- list_dir -------------------------------------------------------------

T.case("list_dir returns sorted entries", function()
    T.ok(fs.mkdir_p(BASE .. "/ls"))
    T.ok(fs.write_file(BASE .. "/ls/b.lua", "b"))
    T.ok(fs.write_file(BASE .. "/ls/a.lua", "a"))
    T.ok(fs.write_file(BASE .. "/ls/notes.txt", "n"))
    local entries = assert(fs.list_dir(BASE .. "/ls"))
    T.deep(entries, { "a.lua", "b.lua", "notes.txt" })
end)

T.case("list_dir on a missing directory fails", function()
    local ok, err = fs.list_dir(BASE .. "/nodir")
    T.not_ok(ok)
    T.match(err, "not a directory")
end)

-- remove_tree ----------------------------------------------------------

T.case("remove_tree removes a populated tree", function()
    T.ok(fs.mkdir_p(BASE .. "/gone/deep"))
    T.ok(fs.write_file(BASE .. "/gone/deep/f", "x"))
    T.ok(fs.remove_tree(BASE .. "/gone"))
    T.eq(fs.exists(BASE .. "/gone"), false)
end)

T.case("remove_tree of a missing path is a no-op success", function()
    T.ok(fs.remove_tree(BASE .. "/never-existed"))
end)

T.case("remove_tree refuses roots and short paths", function()
    local ok1, err1 = fs.remove_tree("/")
    T.not_ok(ok1)
    T.match(err1, "refusing")
    local ok2, err2 = fs.remove_tree("C:\\")
    T.not_ok(ok2)
    T.match(err2, "refusing")
    local ok3, err3 = fs.remove_tree("ab")
    T.not_ok(ok3)
    T.match(err3, "refusing")
end)

T.case("remove_tree refuses regular files", function()
    T.ok(fs.write_file(BASE .. "/afile", "x"))
    local ok, err = fs.remove_tree(BASE .. "/afile")
    T.not_ok(ok)
    T.match(err, "not a directory")
end)

T.finish()
