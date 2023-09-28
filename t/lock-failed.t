use Test::Nginx::Socket::Lua 'no_plan';
use Cwd qw(cwd);

workers(1);

my $pwd = cwd();

our $HttpConfig = qq{
    lua_package_path "$pwd/deps/share/lua/5.1/?/init.lua;$pwd/deps/share/lua/5.1/?.lua;;$pwd/lib/?.lua;;";
    lua_shared_dict test_shm 8m;
    lua_shared_dict my_worker_events 8m;
};

no_shuffle();
run_tests();

__DATA__


=== TEST 1: acquire lock timeout
--- http_config eval
qq{
    $::HttpConfig

    server {
        listen 2116;
        location = /status {
            return 200;
        }
    }
}
--- config
    location = /t {
        content_by_lua_block {
            -- add a lock manually
            local resty_lock = require ("resty.lock")
            local shm_name = "test_shm"
            local name = "testing"
            local key = "lua-resty-healthcheck:" .. name ..  ":target_list_lock"
            local tl_lock, lock_err = resty_lock:new(shm_name, {
                exptime = 10,  -- timeout after which lock is released anyway
                timeout = 5,   -- max wait time to acquire lock
            })
            assert(tl_lock, "new lock failed")
            local elapsed, err = tl_lock:lock(key)
            assert(elapsed, "lock failed")

            -- acquire a lock in the new function
            local we = require "resty.worker.events"
            assert(we.configure{ shm = "my_worker_events", interval = 0.1 })
            local healthcheck = require("resty.healthcheck")
            local ok, err = healthcheck.new({
                name = name,
                shm_name = shm_name,
                type = "http",
                checks = {
                    active = {
                        http_path = "/status",
                        healthy  = {
                            interval = 0.1, -- we don't want active checks
                            successes = 1,
                        },
                        unhealthy  = {
                            interval = 0.1, -- we don't want active checks
                            tcp_failures = 3,
                            http_failures = 3,
                        }
                    }
                }
            })
            assert(ok == nil, "lock success")
            ngx.log(ngx.ERR, err)
        }
    }
--- request
GET /t
--- error_log
failed acquiring lock for 'lua-resty-healthcheck:testing:target_list_lock', timeout
--- timeout: 10
