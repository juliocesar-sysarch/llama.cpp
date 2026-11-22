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

# Test GPU memory counter
$gpuMem = Get-Counter "\GPU Engine(*)\Running Time" -ErrorAction SilentlyContinue
$gpuProcMem = Get-Counter "\GPU Process Memory(*)\Shared Usage" -ErrorAction SilentlyContinue
Write-Host "GPU Process Memory available: $([bool]$gpuProcMem)"

# CPU and System Counters
$cpuCounter = Get-Counter "\Processor(_Total)\% Processor Time" -ErrorAction SilentlyContinue
Write-Host "CPU Counter available: $([bool]$cpuCounter)"
