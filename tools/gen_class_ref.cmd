@echo off
rem Dumps the Godot class reference (XML) of the exact engine version used by the project
rem into .godot\class_ref (ignored by git, regenerate any time).
rem   Classes:  .godot\class_ref\doc\classes\<ClassName>.xml
rem   GDScript: .godot\class_ref\modules\gdscript\doc_classes\@GDScript.xml
rem Godot path: GODOT_BIN environment variable, otherwise the default below.
set GODOT=%GODOT_BIN%
if "%GODOT%"=="" set GODOT=C:\Repositories\Godot_v4.4.1-stable_mono_win64\Godot_v4.4.1-stable_mono_win64_console.exe
set OUT=%~dp0..\.godot\class_ref
if not exist "%OUT%" mkdir "%OUT%"
rem Run outside the project folder so Godot does not open (and import) the project.
pushd "%TEMP%"
"%GODOT%" --headless --doctool "%OUT%"
set CODE=%ERRORLEVEL%
popd
if not "%CODE%"=="0" (
    echo Class reference dump failed with code %CODE%
    exit /b %CODE%
)
"%GODOT%" --version
echo Class reference: %OUT%\doc\classes
exit /b 0
