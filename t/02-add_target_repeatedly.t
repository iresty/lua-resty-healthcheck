use Test::Nginx::Socket::Lua;
use Cwd qw(cwd);

workers(1);

plan tests => repeat_each() * (blocks() * 3);

my $pwd = cwd();
$ENV{TEST_NGINX_SERVROOT} = server_root();

our $HttpConfig = qq{
    lua_package_path "$pwd/lib/?.lua;;";
    lua_shared_dict test_shm 8m;

    server {
        server_name my_worker_events;
        listen unix:$ENV{TEST_NGINX_SERVROOT}/worker_events.sock;
        access_log off;
        location / {
            content_by_lua_block {
                require("resty.events.compat").run()
            }
        }
    }
};

run_tests();

__DATA__

=== TEST 1: calling add_target() repeatedly does not exhaust timers
--- http_config eval
qq{
    $::HttpConfig

    server {
        listen 2113;
        location = /status {
            return 200;
        }
    }
    lua_max_pending_timers 100;

    init_worker_by_lua_block {
        local we = require "resty.events.compat"
        assert(we.configure({
            unique_timeout = 5,
            broker_id = 0,
            listening = "unix:$ENV{TEST_NGINX_SERVROOT}/worker_events.sock"
        }))
        assert(we.configured())

        --error("erreur")
        local resty_lock = require ("resty.lock")
        local healthcheck = require("resty.healthcheck")
        local checker = healthcheck.new({
            name = "testing",
            shm_name = "test_shm",
            checks = {
                active = {
                    http_path = "/status",
                    healthy  = {
                        interval = 0.1,
                        successes = 1,
                    },
                    unhealthy  = {
                        interval = 0.1,
                        tcp_failures = 1,
                        http_failures = 1,
                    }
                }
            }
        })

        -- lock the key, so adding targets will fallback on timers
        local lock = assert(resty_lock:new(checker.shm_name, {
            exptime = 10,  -- timeout after which lock is released anyway
            timeout = 5,   -- max wait time to acquire lock
        }))
        assert(lock:lock(checker.TARGET_LIST_LOCK))

        local addr = {
            127, 0, 0, 1
        }
        -- add 10000 check, exhausting timers...
        for i = 0, 150 do
            addr[4] = addr[4] + 1
            if addr[4] > 255 then
                addr[4] = 1
                addr[3] = addr[3] + 1
                if addr[3] > 255 then
                    addr[3] = 1
                    addr[2] = addr[2] + 1
                    if addr[2] > 255 then
                        addr[2] = 1
                        addr[1] = addr[1] + 1
                    end
                end
            end
            local ok, err = assert(checker:add_target(table.concat(addr, "."), 2113, nil, true))
        end
    }

}

--- config
    location = /t {
        content_by_lua_block {
            ngx.say(true)
            ngx.exit(200)
        }
    }

--- request
GET /t
--- response_body
true
--- no_error_log
too many pending timers
