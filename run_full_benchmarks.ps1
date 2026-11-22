param(
    [string]$Mode = "all"
)

$ErrorActionPreference = "Stop"

$MinGW = "C:\Users\Julio\AppData\Local\Microsoft\WinGet\Packages\BrechtSanders.WinLibs.POSIX.UCRT_Microsoft.Winget.Source_8wekyb3d8bbwe\mingw64\bin"
$env:Path = "$MinGW;$env:Path"

$ModelPath = "models\qwen2.5-3b-instruct-q4_k_m.gguf"
$BenchExe = ".\build-win\bin\llama-bench.exe"

# Benchmark 1: Configuração Padrão (8 threads, pp512, tg128, rep 3, fa=off)
Write-Host "============================================================" -ForegroundColor Yellow
Write-Host "  [1/2] EXECUTANDO BENCHMARK: CPU Padrão Zen 2 (fa off)     " -ForegroundColor Yellow
Write-Host "============================================================" -ForegroundColor Yellow
$Out1 = "benchmarks\win_zen2_native_standard.txt"
& $BenchExe -m $ModelPath -t 8 -p 512 -n 128 -r 3 -fa off | Tee-Object -FilePath $Out1

# Benchmark 2: Flash Attention + KV Cache Q4_0 (8 threads, pp512, tg128, rep 3, fa=on)
Write-Host "`n============================================================" -ForegroundColor Yellow
Write-Host "  [2/2] EXECUTANDO BENCHMARK: Flash Attention + KV Cache Q4_0 " -ForegroundColor Yellow
Write-Host "============================================================" -ForegroundColor Yellow
$Out2 = "benchmarks\win_zen2_native_fa_kv_q4.txt"
& $BenchExe -m $ModelPath -t 8 -p 512 -n 128 -r 3 -fa on -ctk q4_0 -ctv q4_0 | Tee-Object -FilePath $Out2

Write-Host "`n============================================================" -ForegroundColor Green
Write-Host "  BENCHMARKS FINALIZADOS COM SUCESSO!                      " -ForegroundColor Green
Write-Host "============================================================" -ForegroundColor Green
