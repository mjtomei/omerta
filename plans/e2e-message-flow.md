# End-to-End Message Flow: Linux Consumer to Mac Provider

This document describes the complete flow for requesting a VM from a Mac provider via the mesh network.

## Network Topology

```
┌─────────────────────────────────────────────────────────────────┐
│                      Linux Consumer (192.168.1.10)            │
│                                                                  │
│  ┌──────────────┐   IPC (Unix Socket)   ┌────────────────────┐  │
│  │  omerta CLI  │◄─────────────────────►│     omertad        │  │
│  │              │   ping → endpoint      │  (MeshNetwork)     │  │
│  └──────┬───────┘                       └─────────┬──────────┘  │
│         │                                         │              │
│         │ Direct encrypted UDP                    │ Mesh proto   │
│         │ (VM request/response)                   │ (discovery)  │
└─────────┼─────────────────────────────────────────┼──────────────┘
          │                                         │
          │              ════════════════           │
          │                  Network                │
          │              ════════════════           │
          │                                         │
          ▼                                         ▼
┌─────────────────────────────────────────────────────────────────┐
│                      Mac Provider (192.168.1.30)               │
│                                                                  │
│                    ┌────────────────────────────┐                │
│                    │         omertad            │                │
│                    │   (MeshProviderDaemon)     │                │
│                    │      Port: 9999            │                │
│                    └─────────────┬──────────────┘                │
│                                  │                               │
│                    ┌─────────────▼──────────────┐                │
│                    │           VM               │                │
│                    │   NAT: 192.168.64.x        │                │
│                    └─────────────┬──────────────┘                │
└──────────────────────────────────┼───────────────────────────────┘
                                   │
          ┌────────────────────────┘
          │  WireGuard tunnel
          ▼
┌─────────────────────┐
│  Consumer WireGuard │
│  Port: 51900+       │
│  VM IP: 10.x.y.2    │
└─────────────────────┘
```

**Key Design:** The CLI does NOT run its own MeshNetwork. It queries the running
daemon (omertad) via IPC to get the provider's endpoint, then sends VM requests
directly using lightweight encrypted UDP.

The Mac Provider acts as the bootstrap node. Its peer ID and endpoint are embedded in the invite link.

---

## Quick Start Commands

### On Mac (Provider)

```bash
# 1. Create a network (one time)
cd ~/omerta
swift build && codesign --force --sign - --entitlements Entitlements/Omerta.entitlements .build/debug/omertad .build/debug/omerta
.build/debug/omerta network create --name "my-network" --endpoint "$(ipconfig getifaddr en0):9999"

# Save the invite link from output!

# 2. Start the provider daemon
.build/debug/omertad start --network <network-id>
```

### On Linux (Consumer)

```bash
# 1. Join the network (one time)
cd ~/omerta
swift build
.build/debug/omerta network join --key 'omerta://join/eyJ...'

# 2. Start the consumer daemon (required for IPC)
.build/debug/omertad start --network <network-id>

# 3. Request a VM (in another terminal)
sudo .build/debug/omerta vm request --network <network-id> --peer <provider-peer-id>

# 4. SSH to the VM (use the IP shown in output)
ssh -i ~/.omerta/ssh/id_ed25519 omerta@10.x.y.2
```

---

## Detailed Flow

### Phase 1: Network Creation (Mac)

```bash
omerta network create --name 'test' --endpoint '192.168.1.30:9999'
```

What happens:
1. Generates Ed25519 identity keypair
2. Derives peer ID from public key hash (e.g., `75af67f14ec0f9ba`)
3. Generates 32-byte ChaCha20-Poly1305 encryption key
4. Creates NetworkKey containing:
   - Network name
   - Encryption key
   - Bootstrap peers: `["75af67f14ec0f9ba@192.168.1.30:9999"]`
5. Saves identity to `~/Library/Application Support/OmertaMesh/identities.json`
6. Saves network to `~/Library/Application Support/OmertaMesh/networks.json`
7. Outputs invite link (base64-encoded NetworkKey)

### Phase 2: Start Provider (Mac)

```bash
omertad start --network aabe9ce9d06737a6
```

Startup sequence:
1. Loads network config (encryption key, bootstrap peers)
2. Loads identity (must match peer ID in invite link)
3. Starts MeshProviderDaemon with:
   - UDP listener on port 9999
   - Message encryption with network key
   - VM request handler

### Phase 3: Join Network (Linux)

```bash
omerta network join --key 'omerta://join/eyJ...'
```

What happens:
1. Decodes base64 invite link → NetworkKey
2. Generates new identity for this machine
3. Saves network and identity to local stores

### Phase 4: Request VM (Linux)

First, start the consumer daemon (if not already running):
```bash
.build/debug/omertad start --network aabe9ce9d06737a6
```

Then request the VM:
```bash
sudo .build/debug/omerta vm request --network aabe9ce9d06737a6 --peer 75af67f14ec0f9ba
```

#### Step 4.1: IPC Ping to Get Provider Endpoint

The CLI queries the running omertad daemon via Unix socket IPC:

```
CLI                                  omertad                           Provider
 │                                      │                                  │
 │──── IPC: ping(peerId) ──────────────►│                                  │
 │                                      │──── Mesh Ping ──────────────────►│
 │                                      │◄─── Mesh Pong ──────────────────│
 │◄─── IPC: {endpoint, latency} ───────│                                  │
 │                                      │                                  │
```

The daemon's MeshNetwork handles discovery, keepalives, and NAT traversal.
The CLI just needs the endpoint result.

#### Step 4.2: Direct VM Request (No Mesh Stack)

The CLI sends the VM request directly to the provider using lightweight encrypted UDP:

```
CLI                                                   Provider omertad
 │                                                          │
 │  1. Create UDP socket on random port                     │
 │  2. Create signed MeshEnvelope with VM request           │
 │  3. Encrypt with network key (ChaCha20-Poly1305)         │
 │                                                          │
 │──── Encrypted VM Request ───────────────────────────────►│
 │                                                          │
 │◄─── Encrypted VM Response ──────────────────────────────│
 │                                                          │
 │  4. Decrypt response                                     │
 │  5. Verify signature                                     │
 │  6. Close socket                                         │
 │                                                          │
```

All messages are:
- Wrapped in MeshEnvelope with Ed25519 signature
- Encrypted with ChaCha20-Poly1305 using network key
- Sent via direct UDP (NOT through a full MeshNetwork)

**Why not use the daemon's mesh?** The CLI only needs one request/response.
Starting a full MeshNetwork would involve NAT detection, keepalives, peer
discovery, etc. - unnecessary overhead for a simple operation.

#### Step 4.3: Create WireGuard Tunnel

Before sending the VM request, the CLI creates a local WireGuard interface:
- Consumer IP: `10.x.y.1/24`
- VM IP: `10.x.y.2/24` (allocated by consumer)
- Listening port: `51900+offset`

#### Step 4.4: VM Request Message

The MeshVMRequest sent to the provider contains:

```json
{
    "type": "vm_request",
    "vmId": "<uuid>",
    "requirements": { "cpu": 2, "memory": 4096, "storage": 20 },
    "consumerPublicKey": "<WireGuard public key>",
    "consumerEndpoint": "192.168.1.10:51900",
    "consumerVPNIP": "10.x.y.1",
    "vmVPNIP": "10.x.y.2",
    "sshPublicKey": "<SSH public key>",
    "sshUser": "omerta"
}
```

#### Step 4.5: Provider Creates VM

Provider (MeshProviderDaemon):
1. Receives VM request via its MeshNetwork
2. Creates VM with cloud-init containing:
   - WireGuard config pointing to consumer endpoint
   - VM's WireGuard IP from request (`10.x.y.2`)
   - SSH authorized key
   - Firewall rules (only allow traffic through WireGuard)
3. Starts VM via Virtualization.framework (macOS) or QEMU/KVM (Linux)
4. Returns VM's WireGuard public key in response

#### Step 4.6: Complete WireGuard Tunnel

Consumer CLI adds provider's public key to WireGuard:
```bash
wg set wgXXXXXXXX peer <vm-public-key> allowed-ips 10.x.y.2/32
```

#### Step 4.7: VM Boots and Connects

VM boot sequence:
1. Cloud-init installs WireGuard
2. Configures WireGuard interface with `10.x.y.2`
3. Connects to consumer at `192.168.1.10:51900`
4. WireGuard handshake completes
5. SSH accessible at `10.x.y.2`

---

## Message Encryption

All mesh messages use:
- **Confidentiality**: ChaCha20-Poly1305 with 32-byte network key
- **Authentication**: Ed25519 signatures (public key embedded in every message)
- **Peer ID derivation**: `SHA256(publicKey)[0:8].hexString`

Message verification:
1. Decrypt with network key
2. Verify peer ID matches SHA256(embedded public key)
3. Verify Ed25519 signature

---

## Debugging

### Ping a Peer

Ping goes through the running omertad daemon via IPC:

```bash
# Simple ping (requires omertad running)
omerta mesh ping <peer-id> --network <network-id>

# Multiple pings with verbose gossip info
omerta mesh ping <peer-id> --network <network-id> -c 5 -v
```

Verbose mode shows:
- Latency for each ping
- Peers we sent (our recentPeers)
- Peers they sent (their recentPeers)
- New peers discovered

If omertad is not running, you'll get:
```
Error: omertad is not running for network '<network-id>'
```

### Check WireGuard Status

```bash
# On consumer (Linux)
sudo wg show all

# Look for:
#   latest handshake: X seconds ago
#   transfer: X received, Y sent
```

### Check VM Console (Mac)

```bash
cat ~/.omerta/vm-disks/*-console.log | tail -50
```

### Check Cloud-Init Seed

```bash
# On Mac - mount and inspect
cd ~/.omerta/vm-disks
hdiutil attach <vmid>-seed.iso -mountpoint /tmp/seed
cat /tmp/seed/user-data
hdiutil detach /tmp/seed
```

### Common Issues

| Symptom | Cause | Fix |
|---------|-------|-----|
| "Provider endpoint not available" | Consumer omertad not running | Start `omertad start --network <id>` first |
| "omertad is not running" | Daemon not started | Start daemon before running CLI commands |
| "Peer unreachable" | Bootstrap peer ID mismatch | Check peer ID in invite link matches running daemon |
| "No response from provider" | Provider omertad not running | Start daemon on provider machine |
| No WireGuard handshake | Wrong port in consumer endpoint | Check firewall allows WireGuard port |
| SSH timeout | VM still booting | Wait 30-60 seconds after VM creation |
| SSH to wrong IP | Using NAT IP instead of VPN IP | Use the 10.x.y.2 IP from output, not 192.168.64.x |
| "virtualization entitlement" | omertad not signed (macOS) | Re-run codesign command |

---

## Architecture Notes

### Why IPC + Direct UDP?

The CLI uses a two-step approach:
1. **IPC to omertad**: Get provider endpoint via daemon's MeshNetwork
2. **Direct UDP**: Send encrypted VM request directly to provider

This avoids starting a full MeshNetwork in the CLI, which would require:
- NAT detection via STUN
- Keepalive timers
- Peer discovery via gossip
- Freshness queries
- Hole punch coordination

For a simple request/response, direct encrypted UDP is sufficient. The daemon
handles all the mesh complexity.

### Why WireGuard?

The VM runs behind NAT on the Mac (192.168.64.x). Direct SSH isn't possible from external machines. WireGuard provides:
1. Encrypted tunnel from consumer to VM
2. NAT traversal (VM connects out to consumer)
3. Firewall isolation (VM only accepts traffic through tunnel)

### IP Assignment

- Consumer assigns VPN IPs when creating tunnel
- Consumer tells provider what IP to configure on VM
- Consumer uses its assigned `vmVPNIP` for SSH (not provider's reported NAT IP)

### Port Assignment

- Consumer's WireGuard listens on port 51900 (base) + offset
- This port is sent to provider via `vpnConfig.consumerEndpoint`
- VM connects to this exact port
