# ==============================================================================
# Zen 2 (AMD Ryzen 7 5700U) Native Windows Build Script (PowerShell)
# Compilacao recomendada via Clang + Ninja para flags nativas -march=znver2
# ==============================================================================

param (
    [switch]$WithVulkan = $false,
    [switch]$BuildBaseline = $false
)

$ErrorActionPreference = "Stop"

Write-Host "=== Verificando ferramentas de compilacao ===" -ForegroundColor Cyan

# Verifica Clang ou MSVC
$HasClang = (Get-Command clang -ErrorAction SilentlyContinue) -ne $null
$HasNinja = (Get-Command ninja -ErrorAction SilentlyContinue) -ne $null

$OutDir = if ($BuildBaseline) { "build-win-baseline" } else { "build-win" }

$CMakeArgs = @(
    "-B", $OutDir,
    "-DBUILD_SHARED_LIBS=ON",
    "-DGGML_AVX2=ON",
    "-DGGML_FMA=ON",
    "-DGGML_F16C=ON"
)

if ($HasClang -and $HasNinja) {
    Write-Host "[OK] Utilizando LLVM/Clang + Ninja (Otimizacao -march=znver2 completa)" -ForegroundColor Green
    $CMakeArgs += @(
        "-G", "Ninja",
        "-DCMAKE_C_COMPILER=clang",
        "-DCMAKE_CXX_COMPILER=clang++",
        "-DCMAKE_C_FLAGS=-march=znver2 -O3 -fno-finite-math-only",
        "-DCMAKE_CXX_FLAGS=-march=znver2 -O3 -fno-finite-math-only"
    )
} else {
    Write-Host "[AVISO] Clang ou Ninja nao encontrados. Utilizando gerador padrao MSVC." -ForegroundColor Yellow
    $CMakeArgs += @(
        "-DCMAKE_CXX_FLAGS=/arch:AVX2 /O2 /fp:precise"
    )
}

if ($WithVulkan) {
    Write-Host "[OK] Habilitando Backend Vulkan para iGPU Radeon Vega 8" -ForegroundColor Green
    $CMakeArgs += "-DGGML_VULKAN=ON"
}

Write-Host "Configurando CMake em $OutDir..." -ForegroundColor Cyan
cmake @CMakeArgs

Write-Host "Compilando binarios Release com $([System.Environment]::ProcessorCount) threads..." -ForegroundColor Cyan
cmake --build $OutDir --config Release -j 8

Write-Host "Compilacao concluida com sucesso em $OutDir\bin!" -ForegroundColor Green
