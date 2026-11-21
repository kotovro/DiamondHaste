extends GdUnitTestSuite
## Таблица лицензий assets/LICENSES.md (docs/art/ASSET_POLICY.md, раздел «Как выполняем
## указание автора», п. 3, и «Формат assets/LICENSES.md»):
## - у каждого звукового файла в audio/ и у каждого файла игры из assets.lock.json есть строка
##   (строка с путём к папке покрывает пак целиком);
## - лицензия каждой строки разрешена политикой: A — CC0 / общественное достояние / своё
##   (автор — команда); B — CC BY 3.0/4.0 или SIL OFL 1.1; C — только со ссылкой на
##   decision-NN.md; share-alike, NC, ND, GPL, Sampling+, «для личного использования» — нет;
## - у строк уровня B есть текст указания автора, и он есть в data/credits.json.

const LICENSES_PATH := "res://assets/LICENSES.md"
const LOCK_PATH := "res://assets.lock.json"
const CREDITS_PATH := "res://data/credits.json"
const AUDIO_ROOT := "res://audio"
## Служебные файлы Godot рядом с ассетами — не ассеты.
const SERVICE_EXTENSIONS := [".import", ".uid"]
## В assets.lock.json файлы игры лежат в assets/; исходники (art/…) в игру не попадают.
const GAME_ASSETS_PREFIX := "assets/"

const COL_PATH := "Путь в проекте"
const COL_AUTHOR := "Автор"
const COL_LICENSE := "Лицензия"
const COL_LEVEL := "Уровень"
const COL_ATTRIBUTION := "Текст указания автора"

## Запрещённые лицензии (ASSET_POLICY.md, «Уровни лицензий», строка «Запрещено»).
const FORBIDDEN_LICENSE := "(?i)(\\bBY-SA\\b|\\bSA\\b|share.?alike|\\bNC\\b|non.?commercial|\\bND\\b|no.?deriv|\\bL?GPL\\b|sampling|personal|личн|некоммерч|не указан)"
## Уровень A: CC0, общественное достояние, своё.
const LEVEL_A_LICENSE := "(?i)(\\bCC0\\b|public domain|общественное достояние|собственн)"
## Уровень B: CC BY 3.0 / 4.0, для шрифтов — SIL OFL 1.1.
const LEVEL_B_LICENSE := "(?i)(CC BY (3|4)\\.0|SIL OFL 1\\.1)"
## Своё (сделанное командой) — автор в таблице — команда.
const OWN_LICENSE := "(?i)собственн"
const OWN_AUTHOR := "(?i)команд"
## Уровень C — ссылка на запрос решения владельцу.
const DECISION_LINK := "decision-\\d+\\.md"
## «Пусто» в ячейке таблицы.
const EMPTY_CELLS := ["", "—", "-"]


func test_table_exists_and_has_columns() -> void:
	assert_bool(FileAccess.file_exists(LICENSES_PATH)).override_failure_message("есть assets/LICENSES.md").is_true()
	var table := _read_table()
	for column in [COL_PATH, COL_AUTHOR, COL_LICENSE, COL_LEVEL, COL_ATTRIBUTION]:
		assert_bool(table.columns.has(column)).override_failure_message("в таблице есть столбец «%s» (формат ASSET_POLICY.md)" % column).is_true()


func test_every_sound_file_has_license_row() -> void:
	var rows: Array = _read_table().rows
	var sounds := _list_asset_files(AUDIO_ROOT)
	assert_int(sounds.size()).override_failure_message("подготовка: в audio/ есть звуки").is_greater(0)
	for sound in sounds:
		assert_bool(_row_for(rows, sound).is_empty()).override_failure_message("у %s нет строки в assets/LICENSES.md" % sound).is_false()


func test_every_locked_asset_has_license_row() -> void:
	var rows: Array = _read_table().rows
	var locked := _locked_game_assets()
	assert_int(locked.size()).override_failure_message("подготовка: в assets.lock.json есть файлы assets/").is_greater(0)
	for path in locked:
		assert_bool(_row_for(rows, path).is_empty()).override_failure_message("у %s (assets.lock.json) нет строки в assets/LICENSES.md" % path).is_false()


func test_licenses_are_allowed() -> void:
	var rows: Array = _read_table().rows
	assert_int(rows.size()).override_failure_message("подготовка: в таблице есть строки").is_greater(0)
	for row: Dictionary in rows:
		var path: String = row.get(COL_PATH, "")
		var license: String = row.get(COL_LICENSE, "")
		var level: String = row.get(COL_LEVEL, "")
		assert_bool(_matches(FORBIDDEN_LICENSE, license)).override_failure_message("%s: лицензия «%s» запрещена ASSET_POLICY.md" % [path, license]).is_false()
		assert_array(["A", "B", "C"]).override_failure_message("%s: уровень «%s» — A, B или C" % [path, level]).contains([level])
		match level:
			"A":
				assert_bool(_matches(LEVEL_A_LICENSE, license)).override_failure_message("%s: уровень A — CC0, общественное достояние или своё, а не «%s»" % [path, license]).is_true()
				if _matches(OWN_LICENSE, license):
					var author: String = row.get(COL_AUTHOR, "")
					assert_bool(_matches(OWN_AUTHOR, author)).override_failure_message("%s: у своего ассета автор — команда, а не «%s»" % [path, author]).is_true()
			"B":
				assert_bool(_matches(LEVEL_B_LICENSE, license)).override_failure_message("%s: уровень B — CC BY 3.0/4.0 или SIL OFL 1.1, а не «%s»" % [path, license]).is_true()
			"C":
				assert_bool(_matches(DECISION_LINK, " | ".join(PackedStringArray(row.values())))).override_failure_message("%s: уровень C — только со ссылкой на decision-NN.md с ответом владельца" % path).is_true()


func test_attribution_rows_are_in_credits() -> void:
	var credits := FileAccess.get_file_as_string(CREDITS_PATH) if FileAccess.file_exists(CREDITS_PATH) else ""
	for row: Dictionary in _read_table().rows:
		if row.get(COL_LEVEL, "") != "B":
			continue
		var path: String = row.get(COL_PATH, "")
		var attribution: String = row.get(COL_ATTRIBUTION, "")
		assert_bool(EMPTY_CELLS.has(attribution)).override_failure_message("%s: у строки уровня B есть текст указания автора" % path).is_false()
		if EMPTY_CELLS.has(attribution):
			continue
		assert_str(credits).override_failure_message("%s: текст указания автора есть в data/credits.json" % path).contains(attribution)


# --- Помощники -----------------------------------------------------------------

## Таблица из LICENSES.md: {columns: Array[String], rows: Array[Dictionary столбец → ячейка]}.
func _read_table() -> Dictionary:
	var result := {"columns": [], "rows": []}
	var text := FileAccess.get_file_as_string(LICENSES_PATH)
	var columns: Array = []
	for line in text.split("\n"):
		var trimmed := line.strip_edges()
		if not trimmed.begins_with("|"):
			if not columns.is_empty():
				break  # таблица кончилась
			continue
		var cells := _cells(trimmed)
		if columns.is_empty():
			if cells.has(COL_PATH):
				columns = cells
			continue
		if cells.all(func(cell: String) -> bool: return cell.replace("-", "").replace(":", "").is_empty()):
			continue  # строка-разделитель |---|
		var row := {}
		for i in mini(cells.size(), columns.size()):
			row[columns[i]] = cells[i]
		row[COL_PATH] = String(row.get(COL_PATH, "")).replace("`", "").strip_edges().trim_suffix("/")
		(result.rows as Array).append(row)
	result.columns = columns
	return result


func _cells(line: String) -> Array:
	var cells: Array = []
	for cell in line.trim_prefix("|").trim_suffix("|").split("|"):
		cells.append(cell.strip_edges())
	return cells


## Строка таблицы для файла: путь совпадает или строка описывает папку пака, где лежит файл.
func _row_for(rows: Array, path: String) -> Dictionary:
	for row: Dictionary in rows:
		var row_path: String = row.get(COL_PATH, "")
		if row_path.is_empty():
			continue
		if path == row_path or path.begins_with(row_path + "/"):
			return row
	return {}


## Файлы ассетов в папке (пути от корня проекта, без res://), без служебных файлов Godot.
func _list_asset_files(root: String) -> PackedStringArray:
	var result: PackedStringArray = []
	if not DirAccess.dir_exists_absolute(root):
		return result
	for file in DirAccess.get_files_at(root):
		if SERVICE_EXTENSIONS.any(func(ext: String) -> bool: return file.ends_with(ext)):
			continue
		result.append(root.path_join(file).trim_prefix("res://"))
	for dir in DirAccess.get_directories_at(root):
		result.append_array(_list_asset_files(root.path_join(dir)))
	return result


func _locked_game_assets() -> PackedStringArray:
	var result: PackedStringArray = []
	var lock: Variant = JSON.parse_string(FileAccess.get_file_as_string(LOCK_PATH))
	assert_bool(lock is Dictionary and (lock as Dictionary).get("files") is Dictionary) \
		.override_failure_message("assets.lock.json читается, в нём есть files").is_true()
	if not (lock is Dictionary and (lock as Dictionary).get("files") is Dictionary):
		return result
	for path: String in (lock as Dictionary).get("files"):
		if path.begins_with(GAME_ASSETS_PREFIX):
			result.append(path)
	return result


func _matches(pattern: String, text: String) -> bool:
	var regex := RegEx.create_from_string(pattern)
	return regex.search(text) != null
