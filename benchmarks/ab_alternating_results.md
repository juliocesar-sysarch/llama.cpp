# Relatorio Parcial A/B Alternado (Master Upstream vs Fork Zen 2)
Data: 2026-11-22 12:50:57
Hardware: AMD Ryzen 7 5700U (8C/16T, Zen 2)
Modelo: qwen2.5-3b-instruct-q4_k_m.gguf

| Contexto | Cenario / Binario | PP (t/s) | TG (t/s) | CPU Pct | RAM Proc (MB) | Sys RAM Usada (MB) | VRAM Comp (MB) | Temp (C) |
| :--- | :--- | :---: | :---: | :---: | :---: | :---: | :---: | :---: |
| 512 | 1. Master (Upstream) | **46.32** | **5.32** | 49.5% | 3277.3 MB | 10696.1 MB | 215 MB | 85.4 C |
| 512 | 2. Fork Zen 2 (Padrao) | **27.26** | **4.41** | 46.9% | 3268.9 MB | 11101 MB | 215.4 MB | 85.4 C |
| 512 | 3. Fork Zen 2 (FA+Q4_0) | **32.82** | **4.63** | 42.2% | 3258 MB | 10725.5 MB | 207 MB | 85.1 C |
| 2048 | 1. Master (Upstream) | **35.62** | **5.14** | 53.8% | 3342.1 MB | 11246.1 MB | 299.2 MB | 84.9 C |
| 2048 | 2. Fork Zen 2 (Padrao) | **30.32** | **4.02** | 48% | 3341.6 MB | 10867.5 MB | 215.3 MB | 85.8 C |
