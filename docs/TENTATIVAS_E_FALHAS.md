# Relatório de Tentativas, Falhas de Engenharia e Limitações do Hardware

Este documento reúne o histórico completo de engenharia reversa, experimentações, hipóteses testadas, comportamentos anômalos encontrados e soluções definitivas no desenvolvimento do **Smart Cooler Control** para macOS (controlando a linha REDMAGIC e outros coolers magnéticos BLE).

---

## 1. Controle de Rotação Abaixo de 40% (Tentativas de 20% e 30% PWM)

### O que foi tentado
- Disponibilizar opções de **20%** e **30%** de potência mínima na interface para permitir uma operação ultra-silenciosa quando o Mac estivesse frio ou em repouso.

### O que aconteceu / Por que falhou
1. **Piso físico do motor brushless (Stall Floor)**:
   - O ventilador utilizado no REDMAGIC Cooler 5 Pro é um soprador centrífugo de alta rotação (teto de 9.000 RPM).
   - Motores brushless desse porte exigem um ciclo de trabalho (PWM duty cycle) mínimo de **~40%** apenas para vencer o torque de retenção dos ímãs (*cogging torque*) e manter os mancais girando sem travar.
2. **Nivelamento silencioso no firmware do cooler**:
   - Ao receber bytes de 1 a 39 na característica BLE `0x1012`, o microcontrolador do cooler não desce a velocidade: ele nivela a saída física no piso de ~40% (~6.000 RPM) ou corta o sinal.
   - O usuário percebia que **20%, 30% e 40% geravam exatamente o mesmo ruído acústico e rotação**, criando a sensação de que a seleção do app não estava funcionando.
3. **Evidência no aplicativo oficial Goper**:
   - A engenharia reversa do app Goper (`MarkView` em `NubiaExternDeviceEN`) comprovou que o slider oficial possui paradas fixas que começam estritamente em **`40.0%`** (`0x4044000000000000` em ponto flutuante de 64 bits).

### Correção / Resolução Adotada
- Eliminação das porcentagens fictícias de 20% e 30%.
- Adoção de uma escala honesta, uniforme e audivelmente distinta: **`[40%] [60%] [80%] [100%]`**.
- Adicionado clamping no `AutopilotPolicy` para que preferências antigas gravadas em 20% ou 30% sejam automaticamente normalizadas para o piso real de 40%.

---

## 2. Acoplamento Cruzado nos Sliders de Shutoff e Engage

### O que foi tentado
- Implementar um mecanismo de "empurrão dinâmico": se o usuário arrastasse o *Shutoff* para cima e ele encostasse no *Engage*, o slider de *Engage* seria empurrado para cima automaticamente; e se arrastasse o *Engage* para baixo, ele empurraria o *Shutoff* para baixo.

### O que aconteceu / Por que falhou
1. **Efeito dominó de callbacks**:
   - No AppKit, o evento `action` do slider dispara `onEngageChange` e `onShutoffChange`.
   - Quando o `shutoffSliderMoved` alterava o valor do `engageSlider` programaticamente e chamava `onEngageChange`, disparava um novo ciclo de avaliação térmica (`runAutopilot`), salvamento com debounce e refresh visual.
2. **Conflito com o timer de refresh (1 Hz)**:
   - A cada 1 segundo, o método `configure()` atualiza a UI com os dados do modelo. Se o usuário soltasse o botão por uma fração de segundo ou se o tracking perdesse o foco durante o arraste rápido, o slider saltava de volta para a posição anterior.
3. **Inversão e travamento nos extremos**:
   - Em `Config.swift`, `shutoffMaxC` estava configurado em **78°C**, enquanto `engageMaxC` estava em **75°C**.
   - Ao arrastar o shutoff além de 73°C, o engage batia no teto de 75°C e não subia mais, mas o shutoff continuava subindo até 78°C, **deixando a barra de desligamento acima da de engate** e travando o arraste.

### Correção / Resolução Adotada
- **Desacoplamento total e independente**:
  - `shutoffSlider` para de subir em `engageSlider.doubleValue − 2.0°C` e nunca altera o Engage.
  - `engageSlider` para de descer em `shutoffSlider.doubleValue + 2.0°C` e nunca altera o Shutoff.
- Invariante rigorosa: `shutoffMaxC` redefinido para `engageMaxC − 2.0°C` (73°C).

---

## 3. Rampa Acústica do Modo Balanced Vinculada ao Shutoff

### O que foi tentado
- Calcular a aceleração progressiva do ventilador usando a faixa entre *Shutoff* e *Engage*:
  $$\text{progresso} = \frac{\text{dieC} - \text{shutoffC}}{\text{engageC} - \text{shutoffC}}$$

### O que aconteceu / Por que falhou
- Se o usuário definisse *Shutoff* em 41°C, *Engage* em 52°C e o Mac estivesse operando em 48°C:
  $$\text{progresso} = \frac{48 - 41}{52 - 41} = \frac{7}{11} \approx 64\%$$
- O cooler pulava para **65% de ventoinha**, mesmo o Mac estando em carga normal e bem abaixo da temperatura de engate.
- O usuário sentia que a velocidade mínima escolhida não era respeitada e que alterar o shutoff desregulava a velocidade da ventoinha.

### Correção / Resolução Adotada
- Separação estrita em três zonas operacionais:
  1. $\text{dieC} < \text{shutoffC}$: Cooler **100% desligado** (0% PWM, Peltier Standby) para economia e evitar condensação.
  2. $\text{shutoffC} \le \text{dieC} < \text{engageC}$: Cooler opera estritamente no **MIN POWER** configurado (`minFanPercent`), de forma silenciosa e estável.
  3. $\text{dieC} \ge \text{engageC}$:
     - No **Smart Max**: Salto imediato para 100% de potência.
     - No **Balanced**: Rampa acústica suave iniciando em `engageC` até `engageC + 15°C`.
- O valor do *Shutoff* não entra mais em nenhuma fórmula matemática de velocidade.

---

## 4. Persistência de Desligamento na Flash do Cooler via BLE

### O que foi tentado
- Fazer com que o cooler memorizasse internamente o estado desligado (para não ligar a ventoinha ao ser plugado na tomada antes da conexão BLE do Mac).

### O que aconteceu / Por que falhou
1. **Crash de firmware no comando de escrita**:
   - O comando documentado `aa631103dd` (gravação de OFF na EEPROM/Flash) trava o stack BLE do microcontrolador interno do cooler, exigindo remoção física do cabo USB-C para reiniciar.
2. **Bloqueio de autorização do CoreBluetooth no macOS**:
   - O app oficial Goper utiliza bonding BLE no Android e escreve através de um descritor de autorização proprietário (`0x2901`).
   - A API pública `CoreBluetooth` do macOS não permite que aplicações comuns negociem emparelhamento com troca manual de chaves e escrita em descritores protegidos.

### Correção / Resolução Adotada
- Tratado como limitação intransponível do firmware do hardware.
- O app assume o controle volátil assim que o Mac desperta ou conecta via BLE, enviando o comando `0x03` (Standby/Off) ou o modo térmico calculado imediatamente após o handshake.

---

## 5. Modos Intermediários de Pastilha Peltier (0x04 a 0x07)

### O que foi tentado
- Utilizar os modos `0x04`, `0x05`, `0x06` e `0x07` na característica `0x1011` para criar degraus graduais de resfriamento elétrico TEC.

### O que aconteceu / Por que falhou
- No REDMAGIC Cooler 5 Pro, embora o firmware não rejeite esses bytes, o comportamento térmico revelou que apenas três patamares de corrente são estáveis:
  - `0x01`: Low (~10°C)
  - `0x02`: Medium (~40°C do lado quente)
  - `0x08`: Super / Max Overclock (~69°C do lado quente)
- Modos intermediários sem o ventilador rodando em rotação proporcional causavam aquecimento excessivo no dissipador interno por acúmulo de calor térmico inverso.

### Correção / Resolução Adotada
- Mapeamento fiel aos 3 modos homologados de fábrica:
  - Min Power (40%–50%): Modo `0x01` (Low)
  - Min Power (60%–80%): Modo `0x02` (Medium)
  - Min Power (100%) ou Engate Térmico: Modo `0x08` (Max)

---

## 6. Escalas com Min/Max Diferentes entre Sliders

### O que foi tentado
- `shutoffSlider` com escala de 30°C a 50°C.
- `engageSlider` com escala de 35°C a 80°C.

### O que aconteceu / Por que falhou
- Como as larguras em pixels eram iguais, a posição visual de um ponto (por exemplo, 44°C) no Shutoff ficava à direita da posição de 46°C no Engage.
- Isso gerava a ilusão óptica de que os controles estavam "invertidos" ou cruzados.

### Correção / Resolução Adotada
- Ambos os sliders foram alinhados exatamente para o mesmo intervalo de coordenadas: **30°C a 80°C**.
- Dessa forma, 1°C representa o mesmo deslocamento geométrico em ambas as barras.

---

## Resumo das Lições Consolidadas

| Componente | Tentativa com Falha | Causa Raiz Técnica | Solução Homologada |
| :--- | :--- | :--- | :--- |
| **Ventilador** | Modos 20% e 30% PWM | Limite físico de torque do motor (stall) e piso de 40% no firmware | Escala `[40%, 60%, 80%, 100%]` |
| **Sliders UI** | Empurrão cruzado contínuo | Loop de eventos AppKit + colisão com `configure()` | Travamento independente (`maxAllowed`/`minAllowed`) |
| **Limites Térmicos** | `shutoffMaxC = 78°C` | Shutoff podia ultrapassar `engageMaxC` (75°C) | `shutoffMaxC = engageMaxC - 2.0°C` (73°C) |
| **Curva Térmica** | Rampa entre Shutoff e Engage | Elevava rotação indevidamente antes do ponto de engate | Min power fixo até Engage; rampa progressiva apenas acima de Engage |
| **Flash Hardware** | Persistência de estado OFF | Crash de microcontrolador BLE e restrição de CoreBluetooth | Gerenciamento dinâmico via sessão ativa no Mac |
