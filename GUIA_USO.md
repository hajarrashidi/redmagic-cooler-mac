# Guia de Uso — Smart Cooler Control for MacBook

O **Smart Cooler Control** é o aplicativo nativo de barra de menus do macOS desenvolvido exclusivamente para gerenciar coolers termoelétricos (Peltier) de alta potência (**≥ 27W/30W**) no ecossistema Apple Silicon (M1, M2, M3, M4).

---

## 1. Isolamento Estrito de Drivers e Perfis

O aplicativo implementa o princípio de **Zero Contaminação de Pacotes**:
* **Identificação Automática:** Ao escanear o ambiente Bluetooth, o app inspeciona:
  1. *Manufacturer Data* (ex: Black Shark `0x8F 0x03`).
  2. *Service UUIDs* anunciados (ex: Flydigi/MEMO `0xFFE0`, iQOO `0xFFF0`, OnePlus `0xFEE7`, REDMAGIC `d52082ad...`).
  3. Nome anunciado localmente no pacote BLE.
* **Carregamento Exclusivo:** Cada marca possui driver isolado via protocolo `CoolerDriver` (`RedMagicDriver`, `BlackSharkDriver`, `FlydigiDriver`, `IQOODriver`, `OnePlusDriver`, `MemoDriver`). Nenhum comando cruzado ou formato inválido é transmitido.

---

## 2. Modelos Homologados no Catálogo Global (≥ 27W/30W)

| Marca | Modelo | Potência Máxima | Driver Ativo | Recursos |
|---|---|---|---|---|
| **OnePlus** | 45W Liquid Cooler | **45W** | `OnePlusDriver` | Bloco TEC com circulação líquida, modo Overclock 45W |
| **REDMAGIC** | VC Cooler 6 Pro+ | **40W** | `RedMagicDriver` | Vapor Chamber líquida, RGB, Telemetria contínua |
| **REDMAGIC** | Cryo Cooler 8 Pro | **36W** | `RedMagicDriver` | TEC 4ª Geração, sensor de acoplamento Hall |
| **REDMAGIC** | VC Cooler 6 Pro | **36W** | `RedMagicDriver` | Controle fino de fan e níveis de potência |
| **REDMAGIC** | Magnetic Cooler 5 Pro | **36W** | `RedMagicDriver` | Modos Custom/Max e proteção térmica Hall |
| **MEMO** | CX08 Magnetic Cooler | **36W** | `MemoDriver` | TEC 36W de alta potência com controle PWM |
| **Black Shark** | MagCooler 5 Pro | **35W** | `BlackSharkDriver` | 5 níveis de intensidade (até 5100 RPM), Desk Mode |
| **MEMO** | CX07 Magnetic Cooler | **30W** | `MemoDriver` | Refrigeração magnética 30W com RGB |
| **Flydigi** | Flydigi B8X | **30W** | `FlydigiDriver` | Nível 5 Overclock (30W), leitura decimal de temperatura |
| **Flydigi** | Flydigi B7X | **27W** | `FlydigiDriver` | Controle de iluminação e modos térmicos |
| **Black Shark** | MagCooler 4 Pro | **27W** | `BlackSharkDriver` | Ajuste individual de Peltier e rotação do fan |
| **REDMAGIC** | Magcooler 4 Pro | **27W** | `RedMagicDriver` | Telemetria e PWM |
| **OnePlus** | 27W Freezing Point Clip | **27W** | `OnePlusDriver` | TEC SuperVOOC 27W silencioso |
| **iQOO** | Cooling Back Clip 2 Pro | **27W** | `IQOODriver` | Refrigeração 27W com peak 30W |

---

## 3. Lógica do Autopilot e Desligamento em 38°C

Para conciliar máxima refrigeração com total segurança contra condensação (gotículas de água na carcaça de alumínio):

1. **Faixa do Slider de Engajamento:** Ajustável de **38°C até 85°C** (anteriormente travado em 45°C mínimo).
2. **Engajamento Térmico:** Quando a temperatura do die do Mac atinge o limite configurado (ex: ≥ 45°C ou 50°C), o cooler é ativado de imediato.
3. **Resfriamento Contínuo até 38°C:** Após ativado, o cooler continua ligado (passando para o modo de rotação suave de 60%) dissipando o calor acumulado enquanto a temperatura estiver acima de **38°C**.
4. **Desligamento Completo (< 38°C):** Quando o chip do MacBook atinge menos de **38°C**, o cooler desliga 100% (Standby, 0% fan) para evitar condensação e economia de energia.
5. **Anti-Oscilação:** Uma vez desligado, ele permanece em Standby até que o Mac esquente novamente e alcance a temperatura do slider.

---

## 4. Como Compilar e Executar

Para compilar e iniciar o aplicativo:
```bash
./build.sh --run
```
O executável homologado reside em `/Applications/Smart Cooler Control.app`.
