use Test::Nginx::Socket::Lua 'no_plan';
use Cwd qw(cwd);

workers(1);

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
            local healthcheck = require("resty.healthcheck")
            local name = "testing"
            local shm_name = "test_shm"
            local checker = healthcheck.new({
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
            checker:add_target("127.0.0.1", 2116, nil, false)
            checker:add_target("127.0.0.2", 2116, nil, false)
            ngx.sleep(2)
            local nodes = healthcheck.get_target_list(name, shm_name)
            assert(#nodes == 2, "invalid number of nodes")
            for _, node in ipairs(nodes) do
                assert(node.ip == "127.0.0.1" or node.ip == "127.0.0.2", "invalid ip")
                assert(node.port == 2116, "invalid port")
                assert(node.status == "healthy", "invalid status")
                assert(node.counter.success == 1, "invalid success counter")
                assert(node.counter.tcp_failure == 0, "invalid tcp failure counter")
                assert(node.counter.http_failure == 0, "invalid http failure counter")
                assert(node.counter.timeout_failure == 0, "invalid timeout failure counter")
            end
        }
    }
--- request
GET /t
