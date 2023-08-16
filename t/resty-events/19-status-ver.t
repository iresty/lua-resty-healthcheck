use Test::Nginx::Socket::Lua 'no_plan';
use Cwd qw(cwd);

workers(1);
master_on();

my $pwd = cwd();
$ENV{TEST_NGINX_SERVROOT} = server_root();

our $HttpConfig = qq{
    lua_package_path "$pwd/lib/?.lua;;";
    lua_shared_dict test_shm 8m;
    lua_shared_dict my_worker_events 8m;

    init_worker_by_lua_block {
        local we = require "resty.events.compat"
        assert(we.configure({
            unique_timeout = 5,
            broker_id = 0,
            listening = "unix:$ENV{TEST_NGINX_SERVROOT}/worker_events.sock"
        }))
        assert(we.configured())
        ngx.timer.at(0, function()
            local healthcheck = require("resty.healthcheck")
            local checker = healthcheck.new({
                name = "testing",
                shm_name = "test_shm",
                events_module = "resty.events",
                checks = {
                    active = {
                        healthy  = {
                            interval = 0.1
                        },
                        unhealthy  = {
                            interval = 0.1
                        }
                    }
                }
            })
            ngx.sleep(0)
            ngx.sleep(0.01)
            local ok, err = checker:add_target("127.0.0.1", 11111)
            if not ok then
                error(err)
            end
            ngx.sleep(0)
            ngx.sleep(0.01)
        end)
    }

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

=== TEST 1: add_target() adds an unhealthy target
--- http_config eval: $::HttpConfig
--- config
    location = /t {
        content_by_lua_block {
            ngx.say(true)
            ngx.sleep(0.3) -- wait twice the interval
        }
    }
--- request
GET /t
--- response_body
true
--- error_log
checking unhealthy targets: nothing to do
checking unhealthy targets: #1
from 'true' to 'false', ver: 2
