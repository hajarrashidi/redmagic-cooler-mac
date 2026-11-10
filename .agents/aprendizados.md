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

## [AL-COOLER-004] Sobreposição no Cabeçalho de Status e Escala Térmica de LED (Azul-Amarelo-Laranja-Vermelho)
* **Erro:** A versão `v3.1` saía desenhada por cima do nome do modelo do Mac (`MacBook Air`) no topo do menu bar, e o LED no modo térmico ficava verde/vermelho em repouso em vez de azul.
* **Causa-Raiz:** 
  1. `StatusCardView.swift` renderizava Título, Versão, Modelo e Estado Térmico todos em uma única linha horizontal de 330pt, causando colisão direta quando o texto da esquerda encontrava o da direita.
  2. `AutopilotPolicy.swift` usava uma interpolação antiga restrita a Verde -> Vermelho. Em repouso ou temperatura mínima, o hardware nunca recebia Azul, transmitindo sensação incorreta de calor.
* **Solução Permanente:** 
  1. No `StatusCardView.swift`, separou-se a Linha 1 (Marca à esquerda + Versão à direita) da Linha 2 (Temperatura grande à esquerda + Modelo e Estado empilhados com folga à direita).
  2. Em `AutopilotPolicy.swift`, implementou-se a escala térmica de 4 quadrantes contínuos calibrada por família de Mac (Air, Pro, Studio): Azul (< 48°C) -> Amarelo (48°C-60°C) -> Laranja (60°C-70°C) -> Vermelho (≥ 80°C).

## [AL-COOLER-005] Reset de LED RGB no Hardware MCU em Trocas de Modo e Supressão de Escrita BLE
* **Erro:** Ao alternar de Turbo (Máximo) para Auto, o LED físico no cooler ficava travado em Vermelho indefinidamente em vez de voltar para o Azul da temperatura.
* **Causa-Raiz:**
  1. O MCU interno dos coolers (especialmente REDMAGIC 5 Pro e Black Shark) reseta sua eletrônica de iluminação para o perfil de fábrica (estático/pulsante vermelho) toda vez que recebe comando de modo de refrigeração na característica principal (`0x1011`).
  2. O `LedController` utilizava cache em `lastWrittenColor` para evitar escritas BLE redundantes. Ao voltar para Auto, como a temperatura do Mac continuava fria (ex: Azul), `color == lastWrittenColor` retornava `true` e suprimia silenciosamente o envio do pacote `0x1013`, deixando o LED preso no padrão do hardware.
  3. Comandos de LED enviados simultaneamente com a comutação de modo colidiam com a escrita de ventoinha (`0x1012`) que possui delay de ~200ms no firmware.
  4. O heartbeat periódico de 30 segundos chamava apenas `reassertCurrentSettings()` (refrigeração), nunca re-afirmando o LED.
* **Solução Permanente:**
  1. Criado `invalidateCache()` em `LedController.swift` e parâmetro `force: Bool = false` em `updateAutoColor` para furar o cache em reaplicações explícitas.
  2. Criado `scheduleLedReassertion(delay: 0.35)` em `AppDelegate.swift`, cancelando dispatches anteriores e enviando o comando de LED 350ms após as escritas de refrigeração assentarem.
  3. `scheduleLedReassertion()` disparado em todas as transições de modo (`selectMode`, `applyManualStep`, `turnOff`).
  4. Adicionada re-afirmação periódica de LED no heartbeat de 30s (`led.reapply(dieC:autopilot:)`), tornando a recuperação de hardware 100% autônoma e imune a quedas ou resets de firmware.

## [AL-COOLER-006] Calibração Realista do Envelope Térmico Apple Silicon (Amarelo apenas > 65°C)
* **Erro:** No MacBook Air, temperaturas nominais de 50°C a 55°C (onde a ventoinha mal precisa rodar) exibiam texto e LED em Amarelo, gerando falsa sensação de alerta/aquecimento.
* **Causa-Raiz:** O limiar inferior de Amarelo estava fixado muito baixo (48°C / 50°C). Em chips Apple Silicon (M1 a M4), 45°C a 60°C é operação de repouso / carga leve sem risco térmico.
* **Solução Permanente:** 
  1. Calibrado `MacThermalProfile` em `AutopilotPolicy.swift`: Azul (< 65°C), Amarelo (65°C – 75°C), Laranja (75°C – 85°C), Vermelho (≥ 88°C).
  2. Alinhado `UIStyle.heatColor` para refletir estritamente essa regra: temperaturas até 64.9°C permanecem no Azul Puro / Nominal.



