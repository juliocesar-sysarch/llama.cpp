$os = Get-CimInstance Win32_OperatingSystem
$total = [math]::Round($os.TotalVisibleMemorySize / 1024 / 1024, 2)
$free = [math]::Round($os.FreePhysicalMemory / 1024 / 1024, 2)
Write-Host "Total RAM: $total GB, Free RAM: $free GB"

# Test temperature sensors
$tempWmi = Get-CimInstance -Namespace "root/wmi" -ClassName "MSAcpi_ThermalZoneTemperature" -ErrorAction SilentlyContinue
if ($tempWmi) {
    $tempC = ($tempWmi.CurrentTemperature - 2732) / 10.0
    Write-Host "ACPI ThermalZone Temp: $tempC C"
} else {
    Write-Host "MSAcpi_ThermalZoneTemperature not available directly without elevation/OEM driver"
}

# GPU Process Memory counter
$gpuProcMem = Get-Counter "\GPU Process Memory(*)\Shared Usage" -ErrorAction SilentlyContinue
Write-Host "GPU Process Memory available: $([bool]$gpuProcMem)"

# CPU Processor Time Counter (Suporte a nomes localizados PT-BR e EN)
$cpuCounter = Get-Counter "\Processor(_Total)\% Processor Time" -ErrorAction SilentlyContinue
if (-not $cpuCounter) {
    $cpuCounter = Get-Counter "\Processador(_Total)\% tempo de processador" -ErrorAction SilentlyContinue
}
if ($cpuCounter) {
    $cpuVal = [math]::Round($cpuCounter.CounterSamples[0].CookedValue, 1)
    Write-Host "CPU % tempo de processador: $cpuVal%"
} else {
    Write-Host "CPU Counter not available"
}

# WSM Virtual Memory / NVMe Page Fault Counters (Protocolo Seção 7.2)
$pageFaults = Get-Counter "\Memory\Page Faults/sec" -ErrorAction SilentlyContinue
if (-not $pageFaults) {
    $pageFaults = Get-Counter "\Memória\Falhas de páginas/s" -ErrorAction SilentlyContinue
}
if ($pageFaults) {
    $pfRate = [math]::Round($pageFaults.CounterSamples[0].CookedValue, 2)
    Write-Host "Memória Falhas de páginas/s (Page Faults): $pfRate"
} else {
    Write-Host "Memory Page Faults counter not available"
}
