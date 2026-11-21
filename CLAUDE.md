@AGENTS.md

## Claude Code

- Из PowerShell-инструмента тесты запускаются так: `& C:\Repositories\DiamondHeist\tools\run_tests.cmd`.
- Путь к Godot на этой машине (если `GODOT_BIN` не задан): `C:\Repositories\Godot_v4.4.1-stable_mono_win64\Godot_v4.4.1-stable_mono_win64_console.exe`.
- Blender MCP подключён к Blender 3.3, запущенному у пользователя. Рабочую сцену пользователя не трогать: каждый ассет — в своей сцене (`AGENTS.md`, «Ассеты»).
- Перед изменением системы сверяться с файлом техзадания в `docs/tech/`, который её описывает.
- Справочник классов Godot 4.4.1 (XML): `C:\Repositories\DiamondHeist\.godot\class_ref\doc\classes\<Класс>.xml`, GDScript — `.godot\class_ref\modules\gdscript\doc_classes\@GDScript.xml`. Нет или устарел — `tools\gen_class_ref.cmd`.
- Задержка сети для ручных проверок: `tools\run_local_coop.cmd 150` (клиент идёт через `tools\lag_proxy.py`, пинг ≈ 150 мс).
