#pragma once

#include <vector>
#include <cmath>
#include <cstdint>
#include <algorithm>

// WSM Quadruple Coupling Parameters, Atomic Phase Dynamics and Popperian Veto Engine
struct wsm_popperian_evaluator {
    float global_phase_clock   = 0.0f;
    float phase_step           = 0.05f;
    float dissonance_threshold = 0.85f;  // Veto threshold
    float contra_threshold     = 0.15f;  // Negative amplitude threshold triggering contra-axiom repulsion
    float gamma_reg            = 1e-4f;  // Regularization factor for logarithmic T-norm
    float learning_rate_eta    = 0.01f;  // Learning rate for atomic gradient descent without backprop

    // Update Global Phase Clock (T) along helical trajectory in M = R x S^2 x H_n
    void advance_clock() {
        global_phase_clock += phase_step;
        if (global_phase_clock > 2.0f * 3.14159265358979323846f) {
            global_phase_clock -= 2.0f * 3.14159265358979323846f;
        }
    }

    // Evaluate Dissonance D = 1 - M_total with strict contra-axiom tracking and normalized phase cosine
    // Quadruple Coupling: M_total = C * R_gamma * S_euc * S_cos
    float compute_dissonance(
        const float * amplitudes,
        size_t dim,
        float context_score,
        bool & out_contra_axiom_triggered
    ) const {
        out_contra_axiom_triggered = false;
        if (dim == 0 || !amplitudes) return 0.0f;

        // 1. C: Coherence factor bounded in [0, 1]
        float coherence = std::clamp(context_score, 0.0f, 1.0f);

        // 2. R_gamma: Log-regularized T-norm + Contra-axiom parity tracking
        float log_t_norm      = 0.0f;
        float norm_sq         = 0.0f;
        float phase_norm_sq   = 0.0f;
        float phase_alignment = 0.0f;
        int   neg_count       = 0;

        for (size_t i = 0; i < dim; ++i) {
            float val = amplitudes[i];
            float abs_val = std::abs(val);

            // Check contra-axiom repulsion: significant negative amplitude violates axiomatic invariant
            if (val < -contra_threshold) {
                out_contra_axiom_triggered = true;
                neg_count++;
            }

            log_t_norm += std::log(abs_val + gamma_reg);
            norm_sq    += val * val;

            // Phase reference vector on helical manifold
            float mode_phase = static_cast<float>(i) * 0.1f + global_phase_clock;
            float cos_val    = std::cos(mode_phase);

            phase_alignment += val * cos_val;
            phase_norm_sq   += cos_val * cos_val;
        }

        // Geometric mean regularization
        float r_gamma = std::exp(log_t_norm / static_cast<float>(dim));

        // Invert resonance if strong contra-axiom parity is active (Section 3.1 & 3.3 repulsion)
        if (out_contra_axiom_triggered) {
            float contra_penalty = static_cast<float>(neg_count) / static_cast<float>(dim);
            r_gamma *= std::max(0.0f, 1.0f - 2.0f * contra_penalty);
        }

        // 3. S_euc: Normalized Euclidean proximity
        float euclidean_dist = std::sqrt(norm_sq);
        float s_euc          = 1.0f / (1.0f + euclidean_dist);

        // 4. S_cos: Cosine phase synchronization normalized by product of norms sqrt(||a||^2 * ||cos||^2)
        float denom = std::sqrt(norm_sq * phase_norm_sq) + 1e-6f;
        float cos_sim = phase_alignment / denom;
        float s_cos = std::clamp((cos_sim + 1.0f) * 0.5f, 0.0f, 1.0f);

        // M_total calculation
        float m_total = coherence * r_gamma * s_euc * s_cos;

        // Dissonance metric D in [0, 1]
        return std::clamp(1.0f - m_total, 0.0f, 1.0f);
    }

    // Atomic Adjustment Rule (da_i / dt = -eta * dD / da_i) without backpropagation (Eq. 10)
    void atomic_gradient_update(float * amplitudes, size_t dim, float context_score) const {
        if (!amplitudes || dim == 0) return;

        bool contra_flag = false;
        float d_base = compute_dissonance(amplitudes, dim, context_score, contra_flag);

        // Finite difference analytical approximation per mode to avoid matrix backprop
        const float eps = 1e-3f;
        for (size_t i = 0; i < dim; ++i) {
            float original = amplitudes[i];
            amplitudes[i] += eps;
            bool tmp_contra = false;
            float d_perturbed = compute_dissonance(amplitudes, dim, context_score, tmp_contra);
            amplitudes[i] = original;

            // Gradient: dD / da_i
            float grad = (d_perturbed - d_base) / eps;

            // Minimum Action step: a_i <- a_i - eta * grad
            amplitudes[i] -= learning_rate_eta * grad;

            // Enforce bounds [-1.0, 1.0]
            amplitudes[i] = std::clamp(amplitudes[i], -1.0f, 1.0f);
        }
    }

    // Apply Popperian Veto on logits prior to token sampling
    // Suppresses ungrounded candidate tokens if dissonance > threshold OR contra-axiom is detected
    bool evaluate_and_veto(
        float * logits,
        size_t n_vocab,
        const float * state_amplitudes,
        size_t dim
    ) {
        if (!logits || n_vocab == 0) return false;

        bool contra_axiom_active = false;
        float d = compute_dissonance(state_amplitudes, dim, 0.95f, contra_axiom_active);

        // Trigger veto if dissonance threshold breached OR explicit contra-axiom falsification
        if (d > dissonance_threshold || contra_axiom_active) {
            float suppression = 0.0f;
            if (contra_axiom_active) {
                suppression = 0.05f; // Strong suppression for falsified/counter-axiom branch
            } else {
                suppression = (1.0f - d) / (1.0f - dissonance_threshold);
                suppression = std::clamp(suppression, 0.05f, 1.0f);
            }

            for (size_t i = 0; i < n_vocab; ++i) {
                if (logits[i] < 0.0f) {
                    logits[i] *= (2.0f - suppression); // Amplify negative penalty
                } else {
                    logits[i] *= suppression;          // Flatten hallucinated positive logits
                }
            }
            return true; // Veto applied
        }
        return false;
    }
};
