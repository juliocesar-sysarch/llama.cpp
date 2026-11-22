#pragma once

#include <vector>
#include <cmath>
#include <cstdint>
#include <algorithm>

// WSM Quadruple Coupling Parameters and Popperian Veto Engine
struct wsm_popperian_evaluator {
    float global_phase_clock = 0.0f;
    float phase_step = 0.05f;
    float dissonance_threshold = 0.85f; // Threshold above which candidates are falsified/vetoed
    float gamma_reg = 1e-4f;           // T-norm regularization to prevent underflow

    // Update Global Phase Clock (T) along helical trajectory
    void advance_clock() {
        global_phase_clock += phase_step;
        if (global_phase_clock > 2.0f * 3.14159265358979323846f) {
            global_phase_clock -= 2.0f * 3.14159265358979323846f;
        }
    }

    // Evaluate Dissonance D = 1 - M_total
    // Quadruple Coupling: M_total = C * R_gamma * S_euc * S_cos
    float compute_dissonance(const float * amplitudes, size_t dim, float context_score) const {
        if (dim == 0 || !amplitudes) return 0.0f;

        // 1. C: Coherence factor bounded in [0, 1]
        float coherence = std::clamp(context_score, 0.0f, 1.0f);

        // 2. R_gamma: Regularized T-norm in log domain (avoids zero underflow in high dimensions)
        float log_t_norm = 0.0f;
        float norm_sq = 0.0f;
        float phase_alignment = 0.0f;

        for (size_t i = 0; i < dim; ++i) {
            float a = std::clamp(std::abs(amplitudes[i]), 0.0f, 1.0f);
            log_t_norm += std::log(a + gamma_reg);
            norm_sq += amplitudes[i] * amplitudes[i];
            
            // Phase projection against global clock
            float mode_phase = static_cast<float>(i) * 0.1f + global_phase_clock;
            phase_alignment += amplitudes[i] * std::cos(mode_phase);
        }

        // Geometric mean regularization
        float r_gamma = std::exp(log_t_norm / static_cast<float>(dim));

        // 3. S_euc: Euclidean proximity normalized
        float euclidean_dist = std::sqrt(norm_sq);
        float s_euc = 1.0f / (1.0f + euclidean_dist);

        // 4. S_cos: Cosine phase synchronization
        float denom = (euclidean_dist + 1e-6f);
        float s_cos = std::clamp((phase_alignment / denom + 1.0f) * 0.5f, 0.0f, 1.0f);

        // M_total calculation
        float m_total = coherence * r_gamma * s_euc * s_cos;

        // Dissonance metric D in [0, 1]
        return std::clamp(1.0f - m_total, 0.0f, 1.0f);
    }

    // Apply Popperian Veto: Penalize or zero logits of candidates that violate axiological invariant
    // If dissonance exceeds threshold or contra-axiom (amplitude < 0) is flagged
    bool evaluate_and_veto(float * logits, size_t n_vocab, const float * state_amplitudes, size_t dim) {
        if (!logits || n_vocab == 0) return false;

        float d = compute_dissonance(state_amplitudes, dim, 0.95f);

        if (d > dissonance_threshold) {
            // Apply popperian suppression factor
            float suppression = (1.0f - d) / (1.0f - dissonance_threshold);
            for (size_t i = 0; i < n_vocab; ++i) {
                if (logits[i] < 0.0f) {
                    logits[i] *= (2.0f - suppression); // Increase penalty for negative logits
                } else {
                    logits[i] *= suppression;          // Suppress ungrounded peaks
                }
            }
            return true; // Veto triggered
        }
        return false;
    }
};
