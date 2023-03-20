use Test::Nginx::Socket::Lua 'no_plan';
use Cwd qw(cwd);

workers(1);

my $pwd = cwd();

our $HttpConfig = qq{
    lua_package_path "$pwd/lib/?.lua;;";
    lua_shared_dict test_shm 8m;
    lua_shared_dict my_worker_events 8m;
};

no_shuffle();
run_tests();

__DATA__



=== TEST 1: healthy
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
            local we = require "resty.worker.events"
            assert(we.configure{ shm = "my_worker_events", interval = 0.1 })
            local healthcheck = require("resty.healthcheck")
            local checker = healthcheck.new({
                ev_callback = function(name, event, data)
                    ngx.log(ngx.WARN, "name=", name)
                    ngx.log(ngx.WARN, "event=", event)
                    ngx.log(ngx.WARN, "ip=", data.ip)
                    ngx.log(ngx.WARN, "port=", data.port)
                    ngx.log(ngx.WARN, "hostname=", data.hostname)
                end,
                name = "testing",
                shm_name = "test_shm",
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
            checker:add_target("127.0.0.1", 2116, nil, false)
            ngx.sleep(3)
        }
    }
--- request
GET /t
--- error_log
name=testing
event=healthy
ip=127.0.0.1
port=2116
hostname=nil



=== TEST 2: unhealthy
--- http_config eval
qq{
    $::HttpConfig

    server {
        listen 2116;
        location = /status {
            return 500;
        }
    }
}
--- config
    location = /t {
        content_by_lua_block {
            local we = require "resty.worker.events"
            assert(we.configure{ shm = "my_worker_events", interval = 0.1 })
            local healthcheck = require("resty.healthcheck")
            local checker = healthcheck.new({
                ev_callback = function(name, event, data)
                    ngx.log(ngx.WARN, "name=", name)
                    ngx.log(ngx.WARN, "event=", event)
                    ngx.log(ngx.WARN, "ip=", data.ip)
                    ngx.log(ngx.WARN, "port=", data.port)
                    ngx.log(ngx.WARN, "hostname=", data.hostname)
                end,
                name = "testing",
                shm_name = "test_shm",
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
                            http_failures = 1,
                            http_statuses = {500,400},
                        }
                    }
                }
            })
            checker:add_target("127.0.0.1", 2116, nil, true)
            ngx.sleep(3)
        }
    }
--- request
GET /t
--- error_log
name=testing
event=unhealthy
ip=127.0.0.1
port=2116
hostname=nil



=== TEST 3: clear
--- http_config eval
qq{
    $::HttpConfig

    server {
        listen 2116;
        location = /status {
            return 500;
        }
    }
}
--- config
    location = /t {
        content_by_lua_block {
            local we = require "resty.worker.events"
            assert(we.configure{ shm = "my_worker_events", interval = 0.1 })
            local healthcheck = require("resty.healthcheck")
            local checker = healthcheck.new({
                ev_callback = function(name, event, data)
                    ngx.log(ngx.WARN, "name=", name)
                    ngx.log(ngx.WARN, "event=", event)
                    ngx.log(ngx.WARN, "ip=", data.ip)
                    ngx.log(ngx.WARN, "port=", data.port)
                    ngx.log(ngx.WARN, "hostname=", data.hostname)
                end,
                name = "testing",
                shm_name = "test_shm",
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
                            http_failures = 1,
                            http_statuses = {500,400},
                        }
                    }
                }
            })
            checker:add_target("127.0.0.1", 2116, nil, true)
            ngx.sleep(1)
            checker:stop()
            checker:clear()
            ngx.sleep(1)
        }
    }
--- request
GET /t
--- error_log
name=testing
event=clear
