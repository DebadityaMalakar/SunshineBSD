-- test_util.lua — tests util.lua and nothing else.

package.path = "src/sunconfig/lib/?.lua;tests/?.lua;" .. package.path
local T = require("helpers")
local util = require("util")

T.suite("util")

T.case("is_windows returns a boolean", function()
    T.eq(type(util.is_windows()), "boolean")
end)

-- sorted_keys ----------------------------------------------------------

T.case("sorted_keys sorts string keys", function()
    T.deep(util.sorted_keys({ b = 1, a = 2, c = 3 }), { "a", "b", "c" })
end)

T.case("sorted_keys of empty table is empty", function()
    T.deep(util.sorted_keys({}), {})
end)

T.case("sorted_keys rejects non-tables", function()
    local ok, err = pcall(util.sorted_keys, "nope")
    T.not_ok(ok)
    T.match(tostring(err), "expected table")
end)

T.case("sorted_keys rejects non-string keys", function()
    local ok, err = pcall(util.sorted_keys, { [1] = "x" })
    T.not_ok(ok)
    T.match(tostring(err), "non%-string key")
end)

-- is_nonempty_string ---------------------------------------------------

T.case("is_nonempty_string accepts strings with content", function()
    T.ok(util.is_nonempty_string("x"))
end)

T.case("is_nonempty_string rejects empty string, nil, numbers", function()
    T.not_ok(util.is_nonempty_string(""))
    T.not_ok(util.is_nonempty_string(nil))
    T.not_ok(util.is_nonempty_string(5))
end)

-- valid_hostname -------------------------------------------------------

T.case("valid_hostname accepts simple and dotted names", function()
    T.ok(util.valid_hostname("sunshine"))
    T.ok(util.valid_hostname("a"))
    T.ok(util.valid_hostname("web-01.example.org"))
    T.ok(util.valid_hostname("9front"))
end)

T.case("valid_hostname accepts a 63-char label", function()
    T.ok(util.valid_hostname(string.rep("a", 63)))
end)

T.case("valid_hostname rejects a 64-char label", function()
    T.not_ok(util.valid_hostname(string.rep("a", 64)))
end)

T.case("valid_hostname rejects total length over 253", function()
    local label = string.rep("a", 63)
    local long = label .. "." .. label .. "." .. label .. "." .. label
    T.not_ok(util.valid_hostname(long))
end)

T.case("valid_hostname rejects empty and empty labels", function()
    T.not_ok(util.valid_hostname(""))
    T.not_ok(util.valid_hostname(".a"))
    T.not_ok(util.valid_hostname("a."))
    T.not_ok(util.valid_hostname("a..b"))
end)

T.case("valid_hostname rejects bad characters and hyphen edges", function()
    T.not_ok(util.valid_hostname("-host"))
    T.not_ok(util.valid_hostname("host-"))
    T.not_ok(util.valid_hostname("host_name"))
    T.not_ok(util.valid_hostname("host!"))
    T.not_ok(util.valid_hostname("hos t"))
end)

T.case("valid_hostname rejects non-strings with a reason", function()
    local ok, why = util.valid_hostname(42)
    T.not_ok(ok)
    T.match(why, "must be a string")
end)

-- valid_timezone -------------------------------------------------------

T.case("valid_timezone accepts common zones", function()
    T.ok(util.valid_timezone("UTC"))
    T.ok(util.valid_timezone("Asia/Kolkata"))
    T.ok(util.valid_timezone("America/Argentina/Buenos_Aires"))
    T.ok(util.valid_timezone("Etc/GMT+5"))
end)

T.case("valid_timezone rejects malformed zones", function()
    T.not_ok(util.valid_timezone(""))
    T.not_ok(util.valid_timezone("/Kolkata"))
    T.not_ok(util.valid_timezone("Asia/"))
    T.not_ok(util.valid_timezone("Asia//Kolkata"))
    T.not_ok(util.valid_timezone("A/B/C/D"))
    T.not_ok(util.valid_timezone("Asia/Kol kata"))
    T.not_ok(util.valid_timezone("../etc"))
    T.not_ok(util.valid_timezone(nil))
end)

T.case("valid_timezone rejects overlong zones", function()
    T.not_ok(util.valid_timezone("Asia/" .. string.rep("K", 64)))
end)

-- valid_locale ---------------------------------------------------------

T.case("valid_locale accepts POSIX forms", function()
    T.ok(util.valid_locale("C"))
    T.ok(util.valid_locale("POSIX"))
    T.ok(util.valid_locale("en"))
    T.ok(util.valid_locale("en_US"))
    T.ok(util.valid_locale("en.UTF-8"))
    T.ok(util.valid_locale("en_US.UTF-8"))
end)

T.case("valid_locale rejects malformed locales", function()
    T.not_ok(util.valid_locale(""))
    T.not_ok(util.valid_locale("EN_us"))
    T.not_ok(util.valid_locale("en_us"))
    T.not_ok(util.valid_locale("en US"))
    T.not_ok(util.valid_locale("en_US.UTF-8" .. string.rep("x", 32)))
    T.not_ok(util.valid_locale(false))
end)

-- valid_service_name ---------------------------------------------------

T.case("valid_service_name accepts lowercase names", function()
    T.ok(util.valid_service_name("sshd"))
    T.ok(util.valid_service_name("a"))
    T.ok(util.valid_service_name("net_0"))
    T.ok(util.valid_service_name("x-y"))
end)

T.case("valid_service_name rejects bad names", function()
    T.not_ok(util.valid_service_name(""))
    T.not_ok(util.valid_service_name("Sshd"))
    T.not_ok(util.valid_service_name("0sd"))
    T.not_ok(util.valid_service_name("a b"))
    T.not_ok(util.valid_service_name("_x"))
    T.not_ok(util.valid_service_name(string.rep("a", 33)))
    T.not_ok(util.valid_service_name(nil))
end)

-- valid_command --------------------------------------------------------

T.case("valid_command accepts absolute foreground commands", function()
    T.ok(util.valid_command("/usr/sbin/sshd -D -e"))
    T.ok(util.valid_command("/usr/local/bin/dbus-daemon --system --nofork"))
    T.ok(util.valid_command("/x"))
end)

T.case("valid_command rejects relative and empty commands", function()
    T.not_ok(util.valid_command(""))
    T.not_ok(util.valid_command("sshd"))
    T.not_ok(util.valid_command("./sshd"))
end)

T.case("valid_command rejects shell metacharacters", function()
    T.not_ok(util.valid_command("/bin/sh; rm -rf /"))
    T.not_ok(util.valid_command("/bin/echo $(pwd)"))
    T.not_ok(util.valid_command("/bin/a|b"))
    T.not_ok(util.valid_command("/bin/a > /tmp/x"))
    T.not_ok(util.valid_command("/bin/a\n/bin/b"))
    T.not_ok(util.valid_command('/bin/a "q"'))
end)

T.case("valid_command rejects overlong and non-string commands", function()
    T.not_ok(util.valid_command("/" .. string.rep("a", 600)))
    T.not_ok(util.valid_command(9))
end)

-- path_join ------------------------------------------------------------

T.case("path_join joins with slashes", function()
    T.eq(util.path_join("a", "b", "c"), "a/b/c")
end)

T.case("path_join collapses doubled slashes", function()
    T.eq(util.path_join("a/", "b"), "a/b")
end)

T.case("path_join rejects empty or missing segments", function()
    T.not_ok(pcall(util.path_join))
    T.not_ok(pcall(util.path_join, "a", ""))
    T.not_ok(pcall(util.path_join, "a", nil))
end)

T.finish()
