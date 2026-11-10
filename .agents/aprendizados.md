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

## [AL-COOLER-003] Comutação Manual Med -> Max no REDMAGIC 5 Pro e Sincronização do Slider
* **Erro:** No modo Manual, passar o slider de Med para Max não aumentava a potência ou o slider voltava para Med.
* **Causa-Raiz:** 
  1. O firmware do REDMAGIC Cooler 5 Pro possui chave binária na característica `0x1011` (`0x02` = ON, `0x03` = OFF). Ao enviar `0x08` (modo Max), o firmware rejeitava o comando e resetava para OFF ou ignorava.
  2. Como o 5 Pro reporta sempre `0x02` quando ligado, o método `step(matching:)` filtrava apenas passos com `mode == .medium`, ignorando os passos de Max e forçando o medidor a voltar para Med.
  3. A lista de passos anterior continha rotações que não subiam até 100% (paravam em 80%).
* **Solução Permanente:** 
  1. `RedMagicDriver.swift` envia estritamente `0x02` quando `mode.isOn` para o 5 Pro, modulando a potência 100% via PWM na característica `0x1012`.
  2. `CoolingSliderView.steps` reorganizado com rotação estritamente crescente (0%, 40%, 50%, 60%, 65%, 75%, 80%, 85%, 95%, 100%).
  3. `step(matching:)` sincroniza pela velocidade real da ventoinha (`fanPercent`) através dos passos ativos, garantindo que 100% permaneça em Max sem regressão.
