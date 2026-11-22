param(
    [string]$ModelPath = "C:\Users\Julio\Documents\GitHub\llama.cpp\models\qwen2.5-3b-instruct-q4_k_m.gguf",
    [int[]]$ContextSteps = @(512, 2048, 4096, 8192, 16384),
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

$PartialLog = Join-Path $BenchDir "ab_alternating_results.md"
$TelemetryCsv = Join-Path $BenchDir "ab_alternating_telemetry.csv"

# Iniciar cabeçalho do log consolidado
@"
# Relatorio Parcial A/B Alternado (Master Upstream vs Fork Zen 2)
Data: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')
Hardware: AMD Ryzen 7 5700U (8C/16T, Zen 2)
Modelo: $(Split-Path $ModelPath -Leaf)

| Contexto | Cenario / Binario | PP (t/s) | TG (t/s) | CPU Pct | RAM Proc (MB) | Sys RAM Usada (MB) | VRAM Comp (MB) | Temp (C) |
| :--- | :--- | :---: | :---: | :---: | :---: | :---: | :---: | :---: |
"@ | Out-File -FilePath $PartialLog -Encoding utf8

"Timestamp,Context,Scenario,ElapsedSec,CpuPct,ProcWSMB,SysRamUsedMB,SysRamFreeMB,GpuSharedMB,TempC" | Out-File -FilePath $TelemetryCsv -Encoding utf8

function Execute-Step {
    param(
        [string]$ScenarioName,
        [string]$BinaryPath,
        [int]$Ctx,
        [string]$Fa = "off",
        [string]$Ctk = "f16",
        [string]$Ctv = "f16"
    )

    Write-Host "`n>>> [Contexto $Ctx] Executando: $ScenarioName" -ForegroundColor Cyan

    $telemetrySamples = [System.Collections.Generic.List[PSObject]]::new()
    $script:collect = $true

    $Job = Start-Job -ScriptBlock {
        param($ProcName, $CsvPath, $CtxVal, $ScenVal)
        $sw = [System.Diagnostics.Stopwatch]::StartNew()
        while ($true) {
            $elapsed = [math]::Round($sw.Elapsed.TotalSeconds, 1)

            # CPU
            $cpuInst = Get-CimInstance Win32_PerfFormattedData_PerfOS_Processor | Where-Object Name -eq '_Total'
            $cpuPct = if ($cpuInst) { $cpuInst.PercentProcessorTime } else { 0 }

            # RAM do sistema
            $os = Get-CimInstance Win32_OperatingSystem
            $ramFreeMB = [math]::Round($os.FreePhysicalMemory / 1024, 1)
            $ramUsedMB = [math]::Round(($os.TotalVisibleMemorySize - $os.FreePhysicalMemory) / 1024, 1)

            # Processo
            $p = Get-Process -Name $ProcName -ErrorAction SilentlyContinue | Select-Object -First 1
            $procWS = if ($p) { [math]::Round($p.WorkingSet64 / 1MB, 1) } else { 0 }

            # VRAM compartilhada
            $gpuItems = Get-CimInstance Win32_PerfFormattedData_GPUPerformanceCounters_GPUProcessMemory -ErrorAction SilentlyContinue
            $gpuSharedMB = 0
            if ($gpuItems) {
                $sumBytes = ($gpuItems | Measure-Object -Property SharedUsage -Sum).Sum
                $gpuSharedMB = [math]::Round($sumBytes / 1MB, 1)
            }

            # Temp
            $tz = Get-CimInstance Win32_PerfFormattedData_Counters_ThermalZoneInformation -ErrorAction SilentlyContinue | Select-Object -First 1
            $tempC = if ($tz -and $tz.HighPrecisionTemperature -gt 0) {
                [math]::Round(($tz.HighPrecisionTemperature - 2732) / 10.0, 1)
            } elseif ($tz -and $tz.Temperature -gt 0) {
                [math]::Round($tz.Temperature - 273.15, 1)
            } else { 0 }

            $line = "$([DateTime]::UtcNow.ToString('o')),$CtxVal,$ScenVal,$elapsed,$cpuPct,$procWS,$ramUsedMB,$ramFreeMB,$gpuSharedMB,$tempC"
            try { Add-Content -Path $CsvPath -Value $line -ErrorAction SilentlyContinue } catch {}

            Start-Sleep -Milliseconds 1000
        }
    } -ArgumentList "llama-bench", $TelemetryCsv, $Ctx, $ScenarioName

    $ppSpeed = "N/A"
    $tgSpeed = "N/A"

    try {
        $ArgsList = @(
            "-m", $ModelPath,
            "-t", "8",
            "-p", "$Ctx",
            "-n", "$GenTokens",
            "-r", "1",
            "-fa", "$Fa",
            "-ctk", "$Ctk",
            "-ctv", "$Ctv"
        )

        $output = & $BinaryPath @ArgsList
        $output | Out-Host

        # Parse output for pp and tg
        foreach ($line in $output) {
            if ($line -match "pp$Ctx\s+\|\s+([0-9\.]+)") {
                $ppSpeed = $Matches[1]
            }
            if ($line -match "tg$GenTokens\s+\|\s+([0-9\.]+)") {
                $tgSpeed = $Matches[1]
            }
        }
    } finally {
        Stop-Job $Job -ErrorAction SilentlyContinue
        Receive-Job $Job -ErrorAction SilentlyContinue | Out-Null
        Remove-Job $Job -Force -ErrorAction SilentlyContinue
    }

    # Pegar medias de telemetria desta rodada
    $stepRows = Import-Csv -Path $TelemetryCsv -ErrorAction SilentlyContinue | Where-Object { $_.Context -eq "$Ctx" -and $_.Scenario -eq "$ScenarioName" }
    $avgCpu = if ($stepRows) { [math]::Round(($stepRows | Measure-Object -Property CpuPct -Average).Average, 1) } else { 0 }
    $maxProcWS = if ($stepRows) { [math]::Round(($stepRows | Measure-Object -Property ProcWSMB -Maximum).Maximum, 1) } else { 0 }
    $maxSysRAM = if ($stepRows) { [math]::Round(($stepRows | Measure-Object -Property SysRamUsedMB -Maximum).Maximum, 1) } else { 0 }
    $maxGpuVRAM = if ($stepRows) { [math]::Round(($stepRows | Measure-Object -Property GpuSharedMB -Maximum).Maximum, 1) } else { 0 }
    $avgTemp = if ($stepRows) { [math]::Round(($stepRows | Measure-Object -Property TempC -Average).Average, 1) } else { 0 }

    # Gravar linha na tabela parcial
    $tableLine = "| $Ctx | $ScenarioName | **$ppSpeed** | **$tgSpeed** | $avgCpu% | $maxProcWS MB | $maxSysRAM MB | $maxGpuVRAM MB | $avgTemp C |"
    Add-Content -Path $PartialLog -Value $tableLine
    Write-Host "`n[RESULTADO PARCIAL] $tableLine`n" -ForegroundColor Green

    # Pequena pausa para resfriamento de 3s
    Start-Sleep -Seconds 3
}

# Loop alternado por tamanho de contexto
foreach ($ctx in $ContextSteps) {
    Write-Host "`n============================================================" -ForegroundColor Yellow
    Write-Host "  RODADA DE CONTEXTO: $ctx TOKENS (ALTERNADA A/B/C)" -ForegroundColor Yellow
    Write-Host "============================================================" -ForegroundColor Yellow

    # A: Master Upstream Padrão
    Execute-Step -ScenarioName "1. Master (Upstream)" -BinaryPath $ExeMaster -Ctx $ctx -Fa "off" -Ctk "f16" -Ctv "f16"

    # B: Fork Zen 2 Padrão
    Execute-Step -ScenarioName "2. Fork Zen 2 (Padrao)" -BinaryPath $Exefork -Ctx $ctx -Fa "off" -Ctk "f16" -Ctv "f16"

    # C: Fork Zen 2 com Flash Attention + KV Cache Q4_0
    Execute-Step -ScenarioName "3. Fork Zen 2 (FA+Q4_0)" -BinaryPath $Exefork -Ctx $ctx -Fa "on" -Ctk "q4_0" -Ctv "q4_0"
}

Write-Host "`n[SUCESSO] Benchmark alternado finalizado! Relatorio em $PartialLog" -ForegroundColor Green
