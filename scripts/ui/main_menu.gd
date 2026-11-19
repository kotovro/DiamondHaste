extends Control
## Меню подключения: создать игру или подключиться по адресу.

signal host_requested(port: int)
signal join_requested(address: String, port: int)

@onready var address_edit: LineEdit = %AddressEdit
@onready var port_edit: LineEdit = %PortEdit
@onready var host_button: Button = %HostButton
@onready var join_button: Button = %JoinButton
@onready var status_label: Label = %StatusLabel


func _ready() -> void:
	port_edit.text = str(Network.DEFAULT_PORT)
	host_button.pressed.connect(_on_host_pressed)
	join_button.pressed.connect(_on_join_pressed)
	host_button.grab_focus()


func set_busy(busy: bool, message: String = "") -> void:
	host_button.disabled = busy
	join_button.disabled = busy
	status_label.text = message


func show_error(message: String) -> void:
	set_busy(false)
	status_label.text = message


func _on_host_pressed() -> void:
	set_busy(true, "Запуск...")
	host_requested.emit(_port())


func _on_join_pressed() -> void:
	var address := address_edit.text.strip_edges()
	if address.is_empty():
		address = "127.0.0.1"
	set_busy(true, "Подключение к %s..." % address)
	join_requested.emit(address, _port())


func _port() -> int:
	var port := port_edit.text.to_int()
	return port if port > 0 and port < 65536 else Network.DEFAULT_PORT
