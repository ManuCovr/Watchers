extends Node
## NET — minimal ENet host/join, autoloaded as `Net`. "Minecraft-server style":
## the host opens a UDP port; friends connect by the host's IP:port. For friends on
## DIFFERENT networks the host must PORT-FORWARD that UDP port (or everyone joins a
## free VPN like ZeroTier/Hamachi and uses the VPN IP — no port-forwarding needed).
##
## This layer is transport-agnostic on purpose: swapping ENetMultiplayerPeer for a
## SteamMultiplayerPeer later (for launch) only touches host_game/join_game.

signal connected_ok       ## client finished connecting
signal connect_failed     ## client could not reach the host
signal server_left        ## client lost the host

const DEFAULT_PORT := 24545
const MAX_PEERS := 8

var mode := "none"        ## "none" | "host" | "client"
var last_ip := "127.0.0.1"
var last_port := DEFAULT_PORT


func _ready() -> void:
	multiplayer.connected_to_server.connect(func(): connected_ok.emit())
	multiplayer.connection_failed.connect(_on_connection_failed)
	multiplayer.server_disconnected.connect(_on_server_disconnected)


func host_game(port := DEFAULT_PORT) -> bool:
	var peer := ENetMultiplayerPeer.new()
	if peer.create_server(port, MAX_PEERS) != OK:
		push_warning("Net: failed to open server on port %d (in use?)" % port)
		return false
	multiplayer.multiplayer_peer = peer
	mode = "host"
	last_port = port
	return true


func join_game(ip: String, port := DEFAULT_PORT) -> bool:
	var peer := ENetMultiplayerPeer.new()
	if peer.create_client(ip, port) != OK:
		return false
	multiplayer.multiplayer_peer = peer
	mode = "client"
	last_ip = ip
	last_port = port
	return true


func leave() -> void:
	if multiplayer.multiplayer_peer != null:
		multiplayer.multiplayer_peer.close()
	multiplayer.multiplayer_peer = null
	mode = "none"


func is_active() -> bool:
	return mode != "none" and multiplayer.multiplayer_peer != null


## Server (or solo) owns the watcher / tasks / win-lose simulation.
func is_authority() -> bool:
	return not is_active() or multiplayer.is_server()


func _on_connection_failed() -> void:
	leave()
	connect_failed.emit()


func _on_server_disconnected() -> void:
	leave()
	server_left.emit()
