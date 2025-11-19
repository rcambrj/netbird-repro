import json
import time

ip_regexp = '(?:\\b\\.?(?:25[0-5]|2[0-4]\d|1\d\d|[1-9]?\d)){4}' # double escape because nix

start_all()

# Wait for server to be ready
server.wait_for_unit("static-web-server.service")
server.wait_for_unit("netbird-management.service")
server.wait_for_unit("netbird-signal.service")
server.wait_for_unit("coturn.service")

# machine1 can ping machine4's router (machine3)
machine1.wait_until_succeeds(f"ping -c1 -W1 {ip['machine3_wan']}", 10)
# machine4 can ping machine1's router (machine2)
machine4.wait_until_succeeds(f"ping -c1 -W1 {ip['machine2_wan']}", 10)
# both can ping server
machine1.wait_until_succeeds(f"ping -c1 -W1 {ip['server_wan']}", 10)
machine4.wait_until_succeeds(f"ping -c1 -W1 {ip['server_wan']}", 10)

jwks = server.succeed("echo -n $(cat /var/lib/fake-idp/jwks.json)")
print(f"Got JWKs: {jwks}")
token = server.succeed("echo -n $(cat /var/lib/fake-idp/token.jwt)")
print(f"Got JWT: {token}")

accounts = json.loads(server.succeed(" ".join([
	"curl -s --fail-with-body -X GET http://localhost:8011/api/accounts",
	"-H 'Content-Type: application/json'",
	f"-H 'Authorization: Bearer {token}'",
])))
print(f"Accounts: {accounts}")

account = accounts[0]
print(f"Account ID: {account['id']}")

account['onboarding']['onboarding_flow_pending'] = False
account['onboarding']['signup_form_pending'] = False
account['settings']['network_range'] = ip['netbird_cidr']

body = json.dumps({
	'onboarding': account['onboarding'],
	'settings': account['settings'],
})
server.succeed(" ".join([
	f"curl -s --fail-with-body -X PUT http://localhost:8011/api/accounts/{account['id']}",
	"-H 'Content-Type: application/json'",
	f"-H 'Authorization: Bearer {token}'",
	f"-d '{body}'",
]))

body = json.dumps({
	'name': "test-setup-key",
	'type': "reusable",
	'expires_in': 86400,
	'auto_groups': [],
	'usage_limit': 0,
})
setup_key = json.loads(server.succeed(" ".join([
	"curl -s --fail-with-body -X POST http://localhost:8011/api/setup-keys",
    "-H 'Content-Type: application/json'",
    f"-H 'Authorization: Bearer {token}'",
    f"-d '{body}'",
])))

print(f"Setup Key: {setup_key}")
setup_key_secret = setup_key['key']
print(f"Setup Key Secret: {setup_key_secret}")

# netbird errors if it's already up
machine2.succeed("netbird-default down")
machine4.succeed("netbird-default down")
time.sleep(5)

# Configure and start peers with the setup key
# fails after ~30s. use a suitable timeout to get useful logs.
machine2.succeed(f"netbird-default up --setup-key {setup_key_secret} --management-url http://{ip['server_wan']}:8011", timeout=60)
machine4.succeed(f"netbird-default up --setup-key {setup_key_secret} --management-url http://{ip['server_wan']}:8011", timeout=60)

# Wait for peers to connect
machine2.wait_until_succeeds("netbird-default status | grep -q 'Peers count: 1'", 10)
machine4.wait_until_succeeds("netbird-default status | grep -q 'Peers count: 1'", 10)

# Configure predictable netbird IPs for peers
netbird_peers = json.loads(server.succeed(" ".join([
	"curl -s --fail-with-body -X GET http://localhost:8011/api/peers",
	"-H 'Content-Type: application/json'",
	f"-H 'Authorization: Bearer {token}'",
])))
print(f"Netbird Peers: {netbird_peers}")

netbird_machine2 = [peer for peer in netbird_peers if peer['hostname'] == "machine2"][0]
netbird_machine4 = [peer for peer in netbird_peers if peer['hostname'] == "machine4"][0]

netbird_machine2['ip'] = ip['machine2_nb']
netbird_machine4['ip'] = ip['machine4_nb']

body = json.dumps(netbird_machine2)
server.succeed(" ".join([
	f"curl -s --fail-with-body -X PUT http://localhost:8011/api/peers/{netbird_machine2['id']}",
    "-H 'Content-Type: application/json'",
    f"-H 'Authorization: Bearer {token}'",
    f"-d '{body}'",
]))
body = json.dumps(netbird_machine4)
server.succeed(" ".join([
	f"curl -s --fail-with-body -X PUT http://localhost:8011/api/peers/{netbird_machine4['id']}",
    "-H 'Content-Type: application/json'",
    f"-H 'Authorization: Bearer {token}'",
    f"-d '{body}'",
]))

# Restart netbird clients to refresh netbird IPs
machine2.succeed("systemctl restart netbird-default")
machine4.succeed("systemctl restart netbird-default")

# Both netbird peers can ping each other
machine2.wait_until_succeeds(f"ping -c1 -W1 {ip['machine4_nb']}", 10)
machine4.wait_until_succeeds(f"ping -c1 -W1 {ip['machine2_nb']}", 10)

# Add a route allowing machine2 to route traffic between machine1 & machine4
# 1/3 Create a Network
body = json.dumps({
	'name': "lan-network",
})
network = json.loads(server.succeed(" ".join([
	"curl -s --fail-with-body -X POST http://localhost:8011/api/networks",
    "-H 'Content-Type: application/json'",
    f"-H 'Authorization: Bearer {token}'",
    f"-d '{body}'",
])))
print(f"Network: {network}")
networkId = network['id']
print(f"Network ID: {networkId}")

# 2/3 Create a Network Resource
body = json.dumps({
	'name': "lan-network-resource",
	'address': ip['lan1_cidr'],
	'enabled': True,
	'groups': [netbird_machine2['groups'][0]['id']],
})
network_resource = json.loads(server.succeed(" ".join([
	f"curl -s --fail-with-body -X POST http://localhost:8011/api/networks/{networkId}/resources",
    "-H 'Content-Type: application/json'",
    f"-H 'Authorization: Bearer {token}'",
    f"-d '{body}'",
])))
print(f"Network: {network_resource}")


# 3/3 Create a Network Router
body = json.dumps({
	'peer': netbird_machine2['id'],
	'metric': 1,
	'masquerade': False,
	'enabled': True,
})
network_router = json.loads(server.succeed(" ".join([
	f"curl -s --fail-with-body -X POST http://localhost:8011/api/networks/{networkId}/routers",
    "-H 'Content-Type: application/json'",
    f"-H 'Authorization: Bearer {token}'",
    f"-d '{body}'",
])))
print(f"Network: {network_router}")

# Wait for the network to propagate to machine2
machine2.wait_until_succeeds(f"netbird-default status | grep -q 'Networks: {ip['lan1_cidr']}'", 10)

# Peers machine1 and machine4 can ping each other via netbird "Network Route"
machine4.wait_until_succeeds(f"ping -c1 -W1 {ip['machine1_lan1']}", 10)
machine1.wait_until_succeeds(f"ping -c1 -W1 {ip['machine4_nb']}", 10)
