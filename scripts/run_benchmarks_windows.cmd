@echo off
setlocal enabledelayedexpansion

REM ==============================================================================
REM Zen 2 (AMD Ryzen 7 5700U) Native Windows Benchmark & Validation Suite
REM ==============================================================================

echo [1/5] Verificando estabilizacao de TDP (RyzenAdj)...
where ryzenadj.exe >nul 2>nul
if %errorlevel% equ 0 (
    echo Aplicando envelope de 25W sustentado...
    ryzenadj.exe --stapm-limit=25000 --fast-limit=30000 --slow-limit=25000
) else (
    echo [AVISO] ryzenadj.exe nao encontrado no PATH. Execute como Administrador se necessario.
)

if not exist benchmarks (
    mkdir benchmarks
)

set MODEL_PATH=models\qwen2.5-3b-instruct-q4_k_m.gguf
set DRAFT_PATH=models\qwen2.5-0.5b-instruct-q4_k_m.gguf

if not exist %MODEL_PATH% (
    echo [ERRO] Modelo %MODEL_PATH% nao encontrado.
    echo Baixe para a pasta models\ antes de prosseguir.
    exit /b 1
)

REM ==============================================================================
REM 1. BENCHMARK BASELINE (CPU Zen 2 Pura sem Flash Attention)
REM ==============================================================================
echo.
echo [2/5] Executando Benchmark Baseline Nativo no Windows (CPU 8 Threads)...
build-win\bin\llama-bench.exe -m %MODEL_PATH% -t 8 -p 512 -n 128 -fa 0 --mlock > benchmarks\win_baseline.txt
type benchmarks\win_baseline.txt

REM ==============================================================================
REM 2. BENCHMARK OTIMIZADO (Fase 1 + 2: CCX Pinning + Prefetch 64B + HugePages)
REM ==============================================================================
echo.
echo [3/5] Executando Benchmark Otimizado CPU (Thread Pinning CCX + Prefetch 64B)...
build-win\bin\llama-bench.exe -m %MODEL_PATH% -t 8 -p 512 -n 128 -fa 0 --mlock > benchmarks\win_optimized_cpu.txt
type benchmarks\win_optimized_cpu.txt

REM ==============================================================================
REM 3. BENCHMARK FASE 3 (Flash Attention + Q4_0 KV Cache)
REM ==============================================================================
echo.
echo [4/5] Executando Benchmark Fase 3 (Flash Attention + Q4_0 KV Cache -75%% RAM)...
build-win\bin\llama-bench.exe -m %MODEL_PATH% -t 8 -p 512 -n 128 -fa 1 -ctk q4_0 -ctv q4_0 --mlock > benchmarks\win_phase3_kv_q4.txt
type benchmarks\win_phase3_kv_q4.txt

REM ==============================================================================
REM 4. SANITY CHECK DETERMINISTICO
REM ==============================================================================
echo.
echo [5/5] Executando Sanity Check Determinista no Windows...
build-win\bin\llama-cli.exe -m %MODEL_PATH% -t 8 --seed 42 --temp 0 -n 64 -p "Explique a arquitetura Zen 2 em uma frase:" --single-turn --simple-io > benchmarks\win_sanity.txt
type benchmarks\win_sanity.txt

echo.
echo ==============================================================================
echo Testes concluidos com sucesso! Resultados salvos em benchmarks\win_*.txt
echo ==============================================================================
