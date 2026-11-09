# Guia de Uso — Smart Cooler Control for MacBook

O **Smart Cooler Control** é o aplicativo de barra de menus do macOS desenvolvido exclusivamente para gerenciar coolers termoelétricos (Peltier) de alta potência (**≥ 30W**) no ecossistema Apple Silicon (M1, M2, M3, M4).

---

## 1. Isolamento Estrito de Drivers e Perfis

O aplicativo implementa o princípio de **Zero Contaminação de Pacotes**:
* **Identificação Automática:** Ao escanear o ambiente Bluetooth, o app inspeciona:
  1. *Manufacturer Data* (ex: Black Shark `0x8F 0x03`).
  2. *Service UUIDs* anunciados (ex: Flydigi `0xFFE0`, REDMAGIC `d52082ad...`).
  3. Nome anunciado localmente no pacote BLE.
* **Carregamento Exclusivo:** Um cooler Black Shark **nunca** receberá bytes do protocolo REDMAGIC ou Flydigi. O driver dedicado da marca (`RedMagicDriver`, `BlackSharkDriver`, `FlydigiDriver`) é o único instanciado.

---

## 2. Modelos Homologados com Suporte Nativo

| Marca | Modelo | Potência Máxima | Driver Ativo | Recursos |
|---|---|---|---|---|
| **REDMAGIC** | VC Cooler 6 Pro+ | **40W** | `RedMagicDriver` | Vapor Chamber líquida, RGB, Telemetria contínua |
| **REDMAGIC** | Cryo Cooler 8 Pro | **36W** | `RedMagicDriver` | TEC 4ª Geração, sensor de acoplamento Hall |
| **REDMAGIC** | VC Cooler 6 Pro | **36W** | `RedMagicDriver` | Controle fino de fan e níveis de potência |
| **REDMAGIC** | Magnetic Cooler 5 Pro | **36W** | `RedMagicDriver` | Modos Custom/Max e proteção térmica |
| **REDMAGIC** | Magcooler 4 Pro | **27W** | `RedMagicDriver` | Telemetria e PWM |
| **Black Shark** | MagCooler 5 Pro | **35W** | `BlackSharkDriver` | 5 níveis de intensidade (até 5100 RPM), Desk Mode |
| **Black Shark** | MagCooler 4 Pro | **27W** | `BlackSharkDriver` | Ajuste individual de Peltier e rotação do fan |
| **Flydigi** | Flydigi B8X | **30W** | `FlydigiDriver` | Nível 5 Overclock, leitura decimal de temperatura |
| **Flydigi** | Flydigi B7X | **27W** | `FlydigiDriver` | Controle de iluminação e modos térmicos |

---

## 3. Modos de Operação

1. **Autopilot Inteligente (Recomendado):**
   * Lê continuamente os sensores de temperatura interna do chip Apple Silicon (`die temp`).
   * Quando o Mac ultrapassa a temperatura de acionamento (padrão: 55°C), ativa o cooler no nível ideal ou máximo.
   * Evita condensação: quando o Mac esfria ou entra em repouso, desliga a placa Peltier automaticamente.
2. **Modo Manual:**
   * Permite fixar o nível de potência desejado pelo slider (0 a 100% ou Níveis 1 a 5).
   * Suporta temporizador de desligamento automático para segurança.

---

## 4. Integração com o Ciclo de Vida do macOS

* **Repouso / Sleep:** Desliga o cooler imediatamente ao fechar a tampa ou suspender a sessão para impedir formação de gelo/água na carcaça de alumínio.
* **Desligamento / Reinicialização:** Envia o comando de desligamento e desconexão limpa antes do encerramento do sistema.
* **Inicialização:** Reconecta automaticamente em segundo plano ao cooler preferido salvo.

---

## 5. Como Compilar e Executar

Para compilar e iniciar o aplicativo:
```bash
./build.sh --run
```
O aplicativo compilado é instalado em `/Applications/Smart Cooler Control.app`.
