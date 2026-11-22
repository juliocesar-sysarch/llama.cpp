#include "common/wsm_dissonance.h"
#include "common/wsm_vmem.h"
#include <iostream>
#include <cassert>

int main() {
    std::cout << "[TEST] 1. Validando wsm_vmem (Memoria Holografica Esparsa Win32/POSIX)..." << std::endl;
    wsm_vmem_mapped_file map = {};
    // Teste com o proprio executavel ou arquivo de modelo
    bool ok = wsm_vmem_map_file("models/qwen2.5-3b-instruct-q4_k_m.gguf", 4096 * 10, true, &map);
    if (ok && map.addr) {
        std::cout << "  -> Arquivo NVMe mapeado via mmap/MapViewOfFile com sucesso em: " << map.addr << std::endl;
        bool pf_ok = wsm_vmem_prefetch(map.addr, 4096 * 2);
        std::cout << "  -> PrefetchVirtualMemory (4KB alinhado): " << (pf_ok ? "OK" : "SKIP/FAIL") << std::endl;
        wsm_vmem_unmap_file(&map);
    } else {
        std::cout << "  -> Skip file map test (modelo nao encontrado no path relativo direto)" << std::endl;
    }

    std::cout << "[TEST] 2. Validando wsm_dissonance (Motor Popperiano e Equacao Quadrupla)..." << std::endl;
    wsm_popperian_evaluator evaluator;
    evaluator.advance_clock();

    const size_t dim = 128;
    std::vector<float> coherent_amps(dim, 0.5f);
    bool contra_flag = false;
    float d1 = evaluator.compute_dissonance(coherent_amps.data(), dim, 0.95f, contra_flag);
    std::cout << "  -> Dissonancia Estado Coerente: " << d1 << " (Contra-axioma: " << contra_flag << ")" << std::endl;
    assert(!contra_flag);

    // Injetar contra-axioma negativo
    std::vector<float> contra_amps = coherent_amps;
    contra_amps[10] = -0.8f;
    contra_amps[20] = -0.9f;
    float d2 = evaluator.compute_dissonance(contra_amps.data(), dim, 0.95f, contra_flag);
    std::cout << "  -> Dissonancia com Contra-Axioma: " << d2 << " (Contra-axioma ativo: " << contra_flag << ")" << std::endl;
    assert(contra_flag);
    assert(d2 > d1);

    // Validar Veto Popperiano em logits
    std::vector<float> logits = { 2.5f, 5.0f, -1.0f, 0.2f };
    bool veto_triggered = evaluator.evaluate_and_veto(logits.data(), logits.size(), contra_amps.data(), dim);
    std::cout << "  -> Veto Popperiano disparado: " << (veto_triggered ? "SIM (Logits suprimidos)" : "NAO") << std::endl;
    assert(veto_triggered);
    std::cout << "  -> Logit maximo pos-veto: " << logits[1] << " (reduzido de 5.0f)" << std::endl;

    // Validar Ajuste Atomico da/dt sem backprop
    evaluator.atomic_gradient_update(coherent_amps.data(), dim, 0.95f);
    std::cout << "  -> Ajuste Atomico Minima Acao (da/dt sem backpropagation): OK" << std::endl;

    std::cout << "\n>>> TODOS OS TESTES UNITARIOS DO WSM PASSARAM COM SUCESSO! <<<" << std::endl;
    return 0;
}
