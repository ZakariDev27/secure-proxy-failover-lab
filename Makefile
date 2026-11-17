.PHONY: help certs up down test demo watch logs stats check kill revive

help:            ## Show this help
	@grep -E '^[a-z-]+: .*##' $(MAKEFILE_LIST) | awk -F ':.*## ' '{printf "  make %-10s %s\n", $$1, $$2}'

certs:           ## Generate the self-signed lab certificate
	./scripts/gen-certs.sh

up: certs        ## Start the lab
	docker compose up -d --wait
	@echo "HTTPS: https://localhost:8443   Stats: http://localhost:8404/stats"

down:            ## Stop the lab and remove containers
	docker compose down -v

test:            ## Run the automated failover test
	./scripts/failover-test.sh

demo:            ## Guided demo: kills servers and shows traffic moving
	./scripts/demo.sh

watch:           ## Live view of which backend serves each request
	./scripts/watch.sh

logs:            ## Follow the proxy log
	docker compose logs -f proxy

stats:           ## Print the dashboard URL
	@echo "http://localhost:8404/stats"

check: certs     ## Validate the HAProxy configuration
	docker run --rm -v "$(PWD)/haproxy/haproxy.cfg:/usr/local/etc/haproxy/haproxy.cfg:ro" \
	  -v "$(PWD)/certs:/usr/local/etc/haproxy/certs:ro" haproxy:3.0-alpine \
	  haproxy -c -f /usr/local/etc/haproxy/haproxy.cfg

kill:            ## Simulate a failure, e.g. make kill NODE=web1
	docker compose stop -t 0 $(NODE)

revive:          ## Bring a node back, e.g. make revive NODE=web1
	docker compose start $(NODE)
