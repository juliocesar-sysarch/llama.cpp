param(
    [string]$Label = "Test",
    [string]$OutFile = "benchmarks\stress_result.txt",
    [string]$Fa = "off",
    [string]$Ctk = "f16",
    [string]$Ctv = "f16",
    [string]$P = "512,2048,4096,8192,16384",
    [string]$N = "64",
    [int]$R = 1
)

$ErrorActionPreference = "Stop"

$MinGW = "C:\Users\Julio\AppData\Local\Microsoft\WinGet\Packages\BrechtSanders.WinLibs.POSIX.UCRT_Microsoft.Winget.Source_8wekyb3d8bbwe\mingw64\bin"
$env:Path = "$MinGW;$env:Path"

$ModelPath = "models\qwen2.5-3b-instruct-q4_k_m.gguf"
$BenchExe = ".\build-win\bin\llama-bench.exe"

$TelemetryLog = [System.IO.Path]::ChangeExtension($OutFile, ".telemetry.csv")
"Timestamp,ElapsedSec,CpuTotalPct,ProcessCpuPct,SystemRamUsedMB,SystemRamFreeMB,ProcessWorkingSetMB,GpuSharedUsedMB,TempCelsius" | Out-File -FilePath $TelemetryLog -Encoding utf8

# Telemetry background job
$TelemetryJob = Start-Job -ScriptBlock {
    param($CsvPath, $ProcName)
    $sw = [System.Diagnostics.Stopwatch]::StartNew()
    while ($true) {
        $elapsed = [math]::Round($sw.Elapsed.TotalSeconds, 1)
        
        $cpuInst = Get-CimInstance Win32_PerfFormattedData_PerfOS_Processor | Where-Object Name -eq '_Total'
        $cpuPct = if ($cpuInst) { $cpuInst.PercentProcessorTime } else { 0 }
        
        $os = Get-CimInstance Win32_OperatingSystem
        $ramFreeMB = [math]::Round($os.FreePhysicalMemory / 1024, 1)
        $ramUsedMB = [math]::Round(($os.TotalVisibleMemorySize - $os.FreePhysicalMemory) / 1024, 1)
        
        $p = Get-Process -Name $ProcName -ErrorAction SilentlyContinue | Select-Object -First 1
        $procWS = if ($p) { [math]::Round($p.WorkingSet64 / 1MB, 1) } else { 0 }
        $procCpu = 0
        
        $gpuItems = Get-CimInstance Win32_PerfFormattedData_GPUPerformanceCounters_GPUProcessMemory -ErrorAction SilentlyContinue
        $gpuSharedMB = 0
        if ($gpuItems) {
            $sumBytes = ($gpuItems | Measure-Object -Property SharedUsage -Sum).Sum
            $gpuSharedMB = [math]::Round($sumBytes / 1MB, 1)
        }
        
        $tz = Get-CimInstance Win32_PerfFormattedData_Counters_ThermalZoneInformation -ErrorAction SilentlyContinue | Select-Object -First 1
        $tempC = if ($tz -and $tz.Temperature -gt 0) {
            if ($tz.Temperature -gt 1000) { [math]::Round(($tz.Temperature - 2732) / 10.0, 1) }
            else { [math]::Round($tz.Temperature - 273.15, 1) }
        } else { 0 }
        
        $line = "$([DateTime]::UtcNow.ToString('o')),$elapsed,$cpuPct,$procCpu,$ramUsedMB,$ramFreeMB,$procWS,$gpuSharedMB,$tempC"
        Add-Content -Path $CsvPath -Value $line
        
        Start-Sleep -Milliseconds 1000
    }
} -ArgumentList $TelemetryLog, "llama-bench"

try {
    Write-Host "============================================================" -ForegroundColor Cyan
    Write-Host "  INICIANDO BENCHMARK DE ESTRESSE: $Label" -ForegroundColor Cyan
    Write-Host "  P: $P | N: $N | Rep: $R | FA: $Fa | CTK: $Ctk | CTV: $Ctv" -ForegroundColor Gray
    Write-Host "============================================================" -ForegroundColor Cyan
    
    $ArgsList = @(
        "-m", $ModelPath,
        "-t", "8",
        "-p", "$P",
        "-n", "$N",
        "-r", "$R",
        "-fa", "$Fa",
        "-ctk", "$Ctk",
        "-ctv", "$Ctv"
    )
    
    & $BenchExe @ArgsList | Tee-Object -FilePath $OutFile
} finally {
    Stop-Job $TelemetryJob
    Receive-Job $TelemetryJob | Out-Null
    Remove-Job $TelemetryJob
    Write-Host "`n[OK] Telemetria registrada em: $TelemetryLog" -ForegroundColor Green
}
