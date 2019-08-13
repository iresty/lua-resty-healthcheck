use Test::Nginx::Socket::Lua 'no_plan';
use Cwd qw(cwd);

workers(1);
log_level('info');
no_long_string();


my $pwd = cwd();

our $HttpConfig = qq{
    lua_package_path "$pwd/lib/?.lua;;";
    lua_shared_dict test_shm 8m;
    lua_shared_dict my_worker_events 8m;
};

run_tests();

__DATA__

=== TEST 1: bad function
--- http_config eval: $::HttpConfig
--- config
    location = /t {
        content_by_lua_block {
            local we = require "resty.worker.events"
            assert(we.configure{ shm = "my_worker_events", interval = 0.1 })

            local healthcheck = require("resty.healthcheck")
            local ck, err = healthcheck.new({
                name = "testing",
                shm_name = "test_shm",
                can_destroy = "xxxx"
            })
        }
    }
--- request
GET /t
--- error_code: 500
--- error_log
required option 'can_destroy' should be function



=== TEST 2: valid function
--- http_config eval: $::HttpConfig
--- config
    location = /t {
        content_by_lua_block {
            local we = require "resty.worker.events"
            assert(we.configure{ shm = "my_worker_events", interval = 0.1 })

            local flag = false
            local function can_destroy()
                return flag
            end

            -- can_destroy = can_destroy,
            local healthcheck = require("resty.healthcheck")
            local checker = healthcheck.new({
                name = "testing",
                shm_name = "test_shm",
                can_destroy = can_destroy,
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

            local ok, err = checker:add_target("127.0.0.1", 11111)
            ngx.say(ok)
            ngx.sleep(0.2) -- wait twice the interval
            checker:set_target_status("127.0.0.1", 11111, nil, true)
            ngx.sleep(0.2) -- wait twice the interval

            flag = true
            checker:set_target_status("127.0.0.1", 11111, nil, true)
            ngx.sleep(0.2) -- wait twice the interval
        }
    }
--- request
GET /t
--- response_body
true
--- grep_error_log eval
qr{unhealthy TCP increment \(\d/\d\)}
--- grep_error_log_out
unhealthy TCP increment (1/2)
unhealthy TCP increment (2/2)
unhealthy TCP increment (1/2)
unhealthy TCP increment (2/2)
