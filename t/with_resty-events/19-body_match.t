use Test::Nginx::Socket::Lua;
use Cwd qw(cwd);

workers(1);

plan tests => repeat_each() * 9;

my $pwd = cwd();
$ENV{TEST_NGINX_SERVROOT} = server_root();

our $HttpConfig = qq{
    lua_package_path "$pwd/lib/?.lua;;";
    lua_shared_dict test_shm 8m;

    init_worker_by_lua_block {
        local we = require "resty.events.compat"
        assert(we.configure({
            unique_timeout = 5,
            broker_id = 0,
            listening = "unix:$ENV{TEST_NGINX_SERVROOT}/worker_events.sock"
        }))
        assert(we.configured())
    }

    server {
        server_name kong_worker_events;
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



=== TEST 1: test body_match_str success
--- http_config eval
qq{
    $::HttpConfig

    # ignore lua tcp socket read timed out
    lua_socket_log_errors off;

    server {
        listen 2114;
        location = /status {
            access_by_lua_block {
                ngx.sleep(0.2)
                ngx.header['content-length'] = '4'
                ngx.say("pass")
                ngx.satus = 200
                return
            }
        }
    }
}
--- config
    location = /t {
        content_by_lua_block {
            local healthcheck = require("resty.healthcheck")
            local checker = healthcheck.new({
                test = true,
                name = "testing",
                shm_name = "test_shm",
                events_module = "resty.events",
                type = "http",
                checks = {
                    active = {
                        http_path = "/status",
                        healthy  = {
                            interval = 0.1,
                        },
                        unhealthy  = {
                            interval = 0.1,
                        },
                        body_match_str = 'pass'
                    },
                }
            })
            ngx.sleep(1) -- active healthchecks might take up to 1s to start
            local ok, err = checker:add_target("127.0.0.1", 2114, nil, true)
            ngx.sleep(1) -- wait for the check interval
            ngx.say(checker:get_target_status("127.0.0.1", 2114))
        }
    }
--- request
GET /t
--- response_body
true
--- no_error_log
[error]



=== TEST 2: test body_match_str failed
--- http_config eval
qq{
    $::HttpConfig

    # ignore lua tcp socket read timed out
    lua_socket_log_errors off;

    server {
        listen 2114;
        location = /status {
            access_by_lua_block {
                ngx.sleep(0.2)
                ngx.header['content-length'] = '4'
                ngx.say("pass")
                ngx.satus = 200
                return
            }
        }
    }
}
--- config
    location = /t {
        content_by_lua_block {
            local healthcheck = require("resty.healthcheck")
            local checker = healthcheck.new({
                test = true,
                name = "testing",
                shm_name = "test_shm",
                events_module = "resty.events",
                type = "http",
                checks = {
                    active = {
                        http_path = "/status",
                        healthy  = {
                            interval = 0.1,
                        },
                        unhealthy  = {
                            interval = 0.1,
                        },
                        body_match_str = 'fail'
                    },
                }
            })
            ngx.sleep(1) -- active healthchecks might take up to 1s to start
            local ok, err = checker:add_target("127.0.0.1", 2114, nil, true)
            ngx.sleep(1) -- wait for the check interval
            ngx.say(checker:get_target_status("127.0.0.1", 2114))
        }
    }
--- request
GET /t
--- response_body
false
--- no_error_log
[error]



=== TEST 3: test body_match_str empty
--- http_config eval
qq{
    $::HttpConfig

    # ignore lua tcp socket read timed out
    lua_socket_log_errors off;

    server {
        listen 2114;
        location = /status {
            access_by_lua_block {
                ngx.sleep(0.2)
                ngx.header['content-length'] = '4'
                ngx.say("pass")
                ngx.satus = 200
                return
            }
        }
    }
}
--- config
    location = /t {
        content_by_lua_block {
            local healthcheck = require("resty.healthcheck")
            local checker = healthcheck.new({
                test = true,
                name = "testing",
                shm_name = "test_shm",
                events_module = "resty.events",
                type = "http",
                checks = {
                    active = {
                        http_path = "/status",
                        healthy  = {
                            interval = 0.1,
                        },
                        unhealthy  = {
                            interval = 0.1,
                        },
                        body_match_str = ''
                    },
                }
            })
            ngx.sleep(1) -- active healthchecks might take up to 1s to start
            local ok, err = checker:add_target("127.0.0.1", 2114, nil, true)
            ngx.sleep(1) -- wait for the check interval
            ngx.say(checker:get_target_status("127.0.0.1", 2114))
        }
    }
--- request
GET /t
--- response_body
true
--- no_error_log
[error]

