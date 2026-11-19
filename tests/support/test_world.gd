class_name TestWorld
extends RefCounted
## Общие заготовки для интеграционных тестов: пол, ожидание кадров физики, поиск файлов.


## Плоский пол size×size с верхом на y = 0.
static func make_floor(size: float) -> StaticBody3D:
	var floor := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(size, 1.0, size)
	shape.shape = box
	floor.add_child(shape)
	floor.position = Vector3(0.0, -0.5, 0.0)
	return floor


## Дождаться count кадров физики.
static func physics_frames(node: Node, count: int) -> void:
	for i in count:
		await node.get_tree().physics_frame


## Все файлы с расширением ext в папке root и вложенных.
static func list_files(root: String, ext: String) -> PackedStringArray:
	var result: PackedStringArray = []
	if not DirAccess.dir_exists_absolute(root):
		return result
	for file in DirAccess.get_files_at(root):
		if file.ends_with(ext):
			result.append(root.path_join(file))
	for dir in DirAccess.get_directories_at(root):
		result.append_array(list_files(root.path_join(dir), ext))
	return result
