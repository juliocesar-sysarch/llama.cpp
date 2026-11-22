@echo off
set "PATH=C:\Users\Julio\AppData\Local\Microsoft\WinGet\Packages\BrechtSanders.WinLibs.POSIX.UCRT_Microsoft.Winget.Source_8wekyb3d8bbwe\mingw64\bin;%PATH%"
set "PYTHONPATH=C:\Users\Julio\Documents\GitHub\llama.cpp\gguf-py;C:\Users\Julio\Documents\WSM;%PYTHONPATH%"
cd /d "C:\Users\Julio\Documents\WSM"
"C:\Users\Julio\AppData\Local\Programs\Python\Python314\python.exe" wsm_cli_interactive.py
pause
