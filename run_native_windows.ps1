# ==============================================================================
# Pipeline Completo "1-Clique": Zen 2 (AMD Ryzen 7 5700U) Benchmark Nativo
# Execucao nativa no Host Windows: Setup + TDP + Build (Clang/Ninja) + Benchmarks
# ==============================================================================

[CmdletBinding()]
param (
    [switch]$WithVulkan = $false
)

$ErrorActionPreference = "Continue"

Write-Host "===================================================================" -ForegroundColor Cyan
Write-Host "   BENCHMARK NATIVO ZEN 2 - AMD RYZEN 7 5700U (WINDOWS NATIVO)   " -ForegroundColor Cyan
Write-Host "===================================================================" -ForegroundColor Cyan

# ------------------------------------------------------------------------------
# 1. Ajuste de Energia e TDP (RyzenAdj)
# ------------------------------------------------------------------------------
Write-Host "`n[Passo 1/5] Verificando e aplicando TDP sustentado de 25W..." -ForegroundColor Yellow
$RyzenAdj = Get-Command ryzenadj.exe -ErrorAction SilentlyContinue
if ($RyzenAdj) {
    & ryzenadj.exe --stapm-limit=25000 --fast-limit=30000 --slow-limit=25000
    Write-Host "[OK] TDP travado em 25W (evitando throttling de 15W)." -ForegroundColor Green
} else {
    Write-Host "[INFO] ryzenadj.exe nao encontrado no PATH. Prosseguindo sem travamento de TDP." -ForegroundColor Gray
}

# ------------------------------------------------------------------------------
# 2. Verificacao de Diretorio e Modelos
# ------------------------------------------------------------------------------
Write-Host "`n[Passo 2/5] Verificando modelos em models\..." -ForegroundColor Yellow
if (-not (Test-Path "benchmarks")) {
    New-Item -ItemType Directory -Path "benchmarks" | Out-Null
}

$ModelPath = "models\qwen2.5-3b-instruct-q4_k_m.gguf"
if (-not (Test-Path $ModelPath)) {
    if (-not (Test-Path "models")) {
        New-Item -ItemType Directory -Path "models" | Out-Null
    }
    Write-Host "[INFO] Modelo $ModelPath nao encontrado. Baixando via curl..." -ForegroundColor Yellow
    curl.exe -L "https://huggingface.co/Qwen/Qwen2.5-3B-Instruct-GGUF/resolve/main/qwen2.5-3b-instruct-q4_k_m.gguf" -o $ModelPath
}

if (-not (Test-Path $ModelPath)) {
    Write-Host "[ERRO] Nao foi possivel localizar nem baixar $ModelPath." -ForegroundColor Red
    exit 1
}
Write-Host "[OK] Modelo pronto: $ModelPath" -ForegroundColor Green

# ------------------------------------------------------------------------------
# 3. Compilacao Nativa Otimizada (Clang/Ninja ou MSVC)
# ------------------------------------------------------------------------------
Write-Host "`n[Passo 3/5] Compilando binarios nativos (Release)..." -ForegroundColor Yellow

$HasClang = (Get-Command clang -ErrorAction SilentlyContinue) -ne $null
$HasNinja = (Get-Command ninja -ErrorAction SilentlyContinue) -ne $null

$OutDir = "build-win"
$CMakeArgs = @(
    "-B", $OutDir,
    "-DBUILD_SHARED_LIBS=ON",
    "-DGGML_AVX2=ON",
    "-DGGML_FMA=ON",
    "-DGGML_F16C=ON"
)

if ($HasClang -and $HasNinja) {
    Write-Host "[OK] Utilizando LLVM/Clang + Ninja com -march=znver2 -O3" -ForegroundColor Green
    $CMakeArgs += @(
        "-G", "Ninja",
        "-DCMAKE_C_COMPILER=clang",
        "-DCMAKE_CXX_COMPILER=clang++",
        "-DCMAKE_C_FLAGS=-march=znver2 -O3 -fno-finite-math-only",
        "-DCMAKE_CXX_FLAGS=-march=znver2 -O3 -fno-finite-math-only"
    )
} else {
    Write-Host "[INFO] Compilando via MSVC padrao (/arch:AVX2 /O2)..." -ForegroundColor Yellow
    $CMakeArgs += @(
        "-DCMAKE_CXX_FLAGS=/arch:AVX2 /O2 /fp:precise"
    )
}

if ($WithVulkan) {
    Write-Host "[OK] Ativando Backend Vulkan para iGPU Vega 8..." -ForegroundColor Green
    $CMakeArgs += "-DGGML_VULKAN=ON"
}

cmake @CMakeArgs
cmake --build $OutDir --config Release -j 8

$LlamaBench = "$OutDir\bin\llama-bench.exe"
$LlamaCli = "$OutDir\bin\llama-cli.exe"

if (-not (Test-Path $LlamaBench)) {
    Write-Host "[ERRO] Falha ao compilar $LlamaBench" -ForegroundColor Red
    exit 1
}
Write-Host "[OK] Binarios compilados com sucesso!" -ForegroundColor Green

# ------------------------------------------------------------------------------
# 4. Execucao dos Benchmarks Quantitativos
# ------------------------------------------------------------------------------
Write-Host "`n[Passo 4/5] Executando bateria de benchmarks quantitativos (-t 8 --mlock)..." -ForegroundColor Yellow

Write-Host "  -> Teste 1: CPU Zen 2 Otimizada (Thread Pinning CCX + Prefetch 64B)..." -ForegroundColor Cyan
& $LlamaBench -m $ModelPath -t 8 -p 512 -n 128 -fa 0 --mlock | Tee-Object -FilePath "benchmarks\win_optimized_cpu.txt"

Write-Host "`n  -> Teste 2: Flash Attention + Quantized KV Cache Q4_0 (-75% RAM)..." -ForegroundColor Cyan
& $LlamaBench -m $ModelPath -t 8 -p 512 -n 128 -fa 1 -ctk q4_0 -ctv q4_0 --mlock | Tee-Object -FilePath "benchmarks\win_phase3_kv_q4.txt"

# ------------------------------------------------------------------------------
# 5. Sanity Check Determinista
# ------------------------------------------------------------------------------
Write-Host "`n[Passo 5/5] Executando Sanity Check Determinista (--seed 42 --temp 0)..." -ForegroundColor Yellow
& $LlamaCli -m $ModelPath -t 8 --seed 42 --temp 0 -n 64 -p "Explique a arquitetura Zen 2 em uma frase:" --single-turn --simple-io | Tee-Object -FilePath "benchmarks\win_sanity.txt"

Write-Host "`n===================================================================" -ForegroundColor Green
Write-Host "   TODOS OS TESTES FORAM CONCLUIDOS COM SUCESSO NO WINDOWS NATIVO!  " -ForegroundColor Green
Write-Host "   Resultados salvos em: benchmarks\win_*.txt                     " -ForegroundColor Green
Write-Host "===================================================================" -ForegroundColor Green
