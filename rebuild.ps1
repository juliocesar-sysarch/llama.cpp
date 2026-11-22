$MinGW = "C:\Users\Julio\AppData\Local\Microsoft\WinGet\Packages\BrechtSanders.WinLibs.POSIX.UCRT_Microsoft.Winget.Source_8wekyb3d8bbwe\mingw64\bin"
$Ninja = "C:\Users\Julio\AppData\Local\Microsoft\WinGet\Packages\Ninja-build.Ninja_Microsoft.Winget.Source_8wekyb3d8bbwe"
$env:Path = "$MinGW;$Ninja;$env:Path"

ninja -C build-win llama-bench
