param(
    [string]$ModelPath = "C:\Users\Julio\Documents\GitHub\llama.cpp\models\qwen2.5-3b-instruct-q4_k_m.gguf",
    [string]$Contexts = "512,2048,4096,8192,16384",
    [int]$GenTokens = 64
)

$ErrorActionPreference = "Stop"

$MinGW = "C:\Users\Julio\AppData\Local\Microsoft\WinGet\Packages\BrechtSanders.WinLibs.POSIX.UCRT_Microsoft.Winget.Source_8wekyb3d8bbwe\mingw64\bin"
$env:Path = "$MinGW;$env:Path"

$ExeMaster = "C:\Users\Julio\Documents\GitHub\llama.cpp-master\build-win\bin\llama-bench.exe"
$Exefork   = "C:\Users\Julio\Documents\GitHub\llama.cpp\build-win\bin\llama-bench.exe"
$BenchDir  = "C:\Users\Julio\Documents\GitHub\llama.cpp\benchmarks"

if (-not (Test-Path $BenchDir)) {
    New-Item -ItemType Directory -Path $BenchDir -Force | Out-Null
}

function Run-BenchmarkWithTelemetry {
    param(
        [string]$Name,
        [string]$BenchBinary,
        [string]$OutPrefix,
        [string]$FaMode = "off",
        [string]$CtkMode = "f16",
        [string]$CtvMode = "f16"
    )

    $ResultFile = Join-Path $BenchDir "${OutPrefix}_bench.txt"
    $CsvFile    = Join-Path $BenchDir "${OutPrefix}_telemetry.csv"

    "Timestamp,ElapsedSec,CpuTotalPct,ProcessWorkingSetMB,SystemRamUsedMB,SystemRamFreeMB,GpuSharedUsedMB,TempCelsius" | Out-File -FilePath $CsvFile -Encoding utf8

    $TelemetryJob = Start-Job -ScriptBlock {
        param($LogPath, $TargetName)
        $sw = [System.Diagnostics.Stopwatch]::StartNew()
        while ($true) {
            $elapsed = [math]::Round($sw.Elapsed.TotalSeconds, 1)

            # CPU total
            $cpuInst = Get-CimInstance Win32_PerfFormattedData_PerfOS_Processor | Where-Object Name -eq '_Total'
            $cpuPct = if ($cpuInst) { $cpuInst.PercentProcessorTime } else { 0 }

            # RAM do sistema
            $os = Get-CimInstance Win32_OperatingSystem
            $ramFreeMB = [math]::Round($os.FreePhysicalMemory / 1024, 1)
            $ramUsedMB = [math]::Round(($os.TotalVisibleMemorySize - $os.FreePhysicalMemory) / 1024, 1)

            # RAM do processo
            $p = Get-Process -Name $TargetName -ErrorAction SilentlyContinue | Select-Object -First 1
            $procWS = if ($p) { [math]::Round($p.WorkingSet64 / 1MB, 1) } else { 0 }

            # VRAM / Memoria Compartilhada com GPU
            $gpuItems = Get-CimInstance Win32_PerfFormattedData_GPUPerformanceCounters_GPUProcessMemory -ErrorAction SilentlyContinue
            $gpuSharedMB = 0
            if ($gpuItems) {
                $sumBytes = ($gpuItems | Measure-Object -Property SharedUsage -Sum).Sum
                $gpuSharedMB = [math]::Round($sumBytes / 1MB, 1)
            }

            # Temperatura
            $tz = Get-CimInstance Win32_PerfFormattedData_Counters_ThermalZoneInformation -ErrorAction SilentlyContinue | Select-Object -First 1
            $tempC = if ($tz -and $tz.Temperature -gt 0) {
                if ($tz.Temperature -gt 1000) { [math]::Round(($tz.Temperature - 2732) / 10.0, 1) }
                else { [math]::Round($tz.Temperature - 273.15, 1) }
            } else { 0 }

            $line = "$([DateTime]::UtcNow.ToString('o')),$elapsed,$cpuPct,$procWS,$ramUsedMB,$ramFreeMB,$gpuSharedMB,$tempC"
            try {
                Add-Content -Path $LogPath -Value $line -ErrorAction SilentlyContinue
            } catch {}

            Start-Sleep -Milliseconds 1000
        }
    } -ArgumentList $CsvFile, "llama-bench"

    try {
        Write-Host "`n============================================================" -ForegroundColor Cyan
        Write-Host "  EXECUTANDO: $Name" -ForegroundColor Cyan
        Write-Host "  Binario: $BenchBinary" -ForegroundColor Gray
        Write-Host "  Contextos: $Contexts | Gen: $GenTokens | FA: $FaMode | CTK: $CtkMode | CTV: $CtvMode" -ForegroundColor Gray
        Write-Host "============================================================" -ForegroundColor Cyan

        $ArgsList = @(
            "-m", $ModelPath,
            "-t", "8",
            "-p", "$Contexts",
            "-n", "$GenTokens",
            "-r", "1",
            "-fa", "$FaMode",
            "-ctk", "$CtkMode",
            "-ctv", "$CtvMode"
        )

        & $BenchBinary @ArgsList | Tee-Object -FilePath $ResultFile
    } finally {
        Stop-Job $TelemetryJob -ErrorAction SilentlyContinue
        Receive-Job $TelemetryJob -ErrorAction SilentlyContinue | Out-Null
        Remove-Job $TelemetryJob -Force -ErrorAction SilentlyContinue
        Write-Host "[OK] Concluido. Telemetria gravada em $CsvFile" -ForegroundColor Green
    }
}

# Se o bench da Master ja terminou perfeitamente, podemos rodar o Fork diretamente
$MasterBenchDone = (Test-Path "$BenchDir\ab_master_default_bench.txt") -and ((Get-Content "$BenchDir\ab_master_default_bench.txt" | Measure-Object -Line).Lines -gt 5)

if (-not $MasterBenchDone) {
    # 1. Execucao A: MASTER Upstream (Configuracao Padrao)
    Run-BenchmarkWithTelemetry -Name "TESTE A: MASTER UPSTREAM (PADRAO)" `
        -BenchBinary $ExeMaster `
        -OutPrefix "ab_master_default" `
        -FaMode "off" -CtkMode "f16" -CtvMode "f16"

    Start-Sleep -Seconds 5
} else {
    Write-Host "[INFO] Teste A (Master Upstream) ja executado e registrado!" -ForegroundColor Green
}

# 2. Execucao B: FORK Otimizado Zen 2 (Configuracao Padrao)
Run-BenchmarkWithTelemetry -Name "TESTE B: FORK ZEN 2 (CONFIG PADRAO)" `
    -BenchBinary $Exefork `
    -OutPrefix "ab_fork_zen2_default" `
    -FaMode "off" -CtkMode "f16" -CtvMode "f16"

Start-Sleep -Seconds 5

# 3. Execucao C: FORK Otimizado Zen 2 com Flash Attention + Q4_0 KV Cache (Limite Extremo de Contexto)
Run-BenchmarkWithTelemetry -Name "TESTE C: FORK ZEN 2 (FA ON + KV Q4_0 - LIMITE DE CONTEXTO)" `
    -BenchBinary $Exefork `
    -OutPrefix "ab_fork_zen2_fa_q4" `
    -FaMode "on" -CtkMode "q4_0" -CtvMode "q4_0"

Write-Host "`n============================================================" -ForegroundColor Green
Write-Host "  BATERIA COMPLETA DE TESTES A/B FINALIZADA COM SUCESSO!    " -ForegroundColor Green
Write-Host "============================================================" -ForegroundColor Green
