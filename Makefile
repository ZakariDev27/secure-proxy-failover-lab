.PHONY: help build up down test demo watch status stats check crash revive proxy-off proxy-on killswitch-on killswitch-off

help:            ## Show this help
	@grep -E '^[a-z-]+: .*##' $(MAKEFILE_LIST) | awk -F ':.*## ' '{printf "  make %-15s %s\n", $$1, $$2}'

build:           ## Build the client and exit proxy images
	docker build -q -t spfl-egress:local egress
	docker build -q -t spfl-client:local client

up: build        ## Start the lab
	docker compose up -d --wait
	@echo "Up. Try: make demo   Stats: http://localhost:8404/stats"

down:            ## Stop the lab and remove containers
	docker compose down -v

test:            ## Run the automated failover and kill switch test
	./scripts/failover-test.sh

demo:            ## Walkthrough: crash proxies and flip the kill switch
	./scripts/demo.sh

watch:           ## Live view of which exit proxy carries each request
	./scripts/watch.sh

status:          ## Show the kill switch and all 20 proxies
	./scripts/killswitch.sh status

stats:           ## Print the stats page URL
	@echo "http://localhost:8404/stats"

check:           ## Validate the gateway configuration
	docker run --rm -v "$(PWD)/gateway/haproxy.cfg:/usr/local/etc/haproxy/haproxy.cfg:ro" \
	  haproxy:3.0-alpine haproxy -c -f /usr/local/etc/haproxy/haproxy.cfg

crash:           ## Crash an exit proxy, e.g. make crash N=07
	docker compose stop -t 0 egress-$(N)

revive:          ## Start a crashed proxy again, e.g. make revive N=07
	docker compose start egress-$(N)

proxy-off:       ## Pull a proxy out of rotation, e.g. make proxy-off N=07
	./scripts/killswitch.sh proxy $(N) off

proxy-on:        ## Put it back, e.g. make proxy-on N=07
	./scripts/killswitch.sh proxy $(N) on

killswitch-on:   ## Block ALL outbound traffic now
	./scripts/killswitch.sh on

killswitch-off:  ## Let traffic flow again
	./scripts/killswitch.sh off
