# Aprendizados do Projeto Smart Cooler Control

## [AL-COOLER-001] Oscilação e Chattering por Sliders Contínuos e Heartbeat BLE
* **Erro:** Ventoinha ligando e desligando em ciclos curtos e soluços de PWM a cada 30 segundos no REDMAGIC Cooler 5 Pro.
* **Causa-Raiz:** 
  1. Sliders contínuos livres permitiam o usuário colocar Shutoff e Engage em faixas coladas (ex: 37°C e 39°C), criando um loop oscilatório inevitável.
  2. O heartbeat BLE de 30 segundos reescrevia cegamente o comando de modo `1011` (`0x02`), resetando a eletrônica PWM do motor físico.
* **Solução Permanente:** 
  1. Deduplicação de escritas idênticas em `RedMagicDriver.swift` via cache de estado.
  2. Transição para o motor determinístico Step-Ladder em `AutopilotPolicy.swift` com patamares discretos (50°, 60°, 65°, 70°C) e folgas amplas de histerese assimétrica (até 8°C no Tier 1: liga em 50°C e só solta em 42°C).
  3. Hard cutoff de condensação `< 36.0°C` em todos os modos com re-arm em $\ge 38.0^\circ\text{C}$.

## [AL-COOLER-002] Dwell de Velocidade Térmica (dT/dt)
* **Erro:** Transição rápida de step-down por encerramento de carga pesada não completava em 3s e revertia para o dwell lento de 20s.
* **Causa-Raiz:** Quando a temperatura caía abruptamente (ex: 57°C -> 45°C) e estabilizava no tick seguinte, $dT/dt$ tornava-se 0.0°C/s, fazendo a checagem instantânea desarmar o bypass de velocidade.
* **Solução Permanente:** Persistir o estado no flag `pendingIsFastDwell = true` associado ao `pendingTier`, garantindo que o dwell acelerado de 3s permaneça ativo até a conclusão do step-down.
