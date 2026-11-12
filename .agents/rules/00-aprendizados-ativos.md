---
trigger: always_on
---

# Guardrails Ativos — Smart Cooler Control (`[AL-COOLER-001..009]`)

- **BLE REDMAGIC 5 Pro (`001`, `003`, `008`, `009`)**: Característica `0x1011` é binária (`0x02`=ON, `0x03`=OFF; nunca envie `0x08` Max — module 100% via PWM em `0x1012` e sincronize slider por `fanPercent`, preservando modo lógico no readback `0x02`). Exija guard `ble.isConnected` antes de qualquer escrita GATT. Readback de `0x1013` ativo para confirmar RGB no hardware.
- **Autopilot Térmico & Standby (`001`, `002`, `006`, `008`, `009`)**: Step-Ladder discreto com `resetStandby(isStandby: true)` abaixo de `50°C`, cutoff anticondensação `< 36°C` (re-arm `>= 38°C`), liberação Tier 1 em `tier1ReleaseC = 46.0°C` (histerese 4°C, libera Mac Air em idle), filtro anti-spike de Standby (`standbyWakeDwellSeconds = 4.0s` para 50–59.9°C; $\ge 60^\circ\text{C}$ imediato) e piso `Tier 2 (60%)` em `thermalState == .serious`. Escala Apple Silicon: Azul `< 65°C`, Amarelo `65–75°C`, Laranja `75–85°C`, Vermelho `>= 88°C`.
- **LED RGB & AppKit RunLoop (`005`, `007`, `008`, `009`, `010`)**: Protocolo do REDMAGIC 5 Pro em `0x1013` usa ordem BGR (`[effect, B, G, R]`); enviar RGB inverte canais (Azul vira Vermelho 100%). Trocas em `0x1011` resetam o MCU do LED; dispare `scheduleLedReassertion(delay: 0.45)` com `force: true` após os `0.20s` da ventoinha, bloqueie `updateAutoColor` em `tick()` se `pendingLedWorkItem != nil` e limpe o ponteiro ao concluir. Registre **todos** os `Timer` em `RunLoop.Mode.common` e decodifique subzero com `Int8(bitPattern:)`.
