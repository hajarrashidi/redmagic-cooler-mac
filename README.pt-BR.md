<div align="center">

<img src="docs/images/banner.jpg" alt="Smart Cooler Control Banner" width="100%" style="border-radius: 12px; margin-bottom: 16px;">

# Smart Cooler Control para MacBook

**O controlador inteligente e multimarca de resfriamento ativo termoelétrico para MacBooks com Apple Silicon.**  
*Desenvolvido exclusivamente para coolers externos termoelétricos (Peltier) de alta potência (≥ 30W), eliminando o estrangulamento térmico (thermal throttling) e mantendo o desempenho máximo sustentado.*

[English](README.md) • [Português (Brasil)](README.pt-BR.md) • [简体中文](README.zh-CN.md)

<br/>

[![macOS 13+](https://img.shields.io/badge/macOS-13%2B%20Ventura%20%7C%20Sonoma%20%7C%20Sequoia-blue?logo=apple)](docs/GETTING_STARTED.md#requirements)
[![Apple Silicon](https://img.shields.io/badge/Apple%20Silicon-M1%20%7C%20M2%20%7C%20M3%20%7C%20M4%20%7C%20M5-black?logo=apple)](docs/GETTING_STARTED.md#requirements)
[![Swift 5.9+](https://img.shields.io/badge/Swift-5.9%2B%20%7C%20AppKit%20%2B%20CoreBluetooth-orange?logo=swift)](docs/DEVELOPMENT.md)
[![Padrão de Hardware](https://img.shields.io/badge/Padr%C3%A3o%20de%20Cooler-%E2%89%A5%2030W%20Peltier%20TEC-red?logo=target)](docs/COMPATIBILITY.md)
[![Licença: MIT](https://img.shields.io/badge/Licen%C3%A7a-MIT-green.svg)](LICENSE)

</div>

---

## ⚡ Por que o Smart Cooler Control?

Os MacBooks equipados com Apple Silicon (**M1, M2, M3, M4 nas versões Base, Pro, Max e Ultra, além do MacBook Air sem ventoinha**) entregam uma densidade de processamento incomparável em chassis finos de alumínio. No entanto, sob cargas de trabalho intensas e contínuas — como **renderização 3D (Blender, Octane), exportação de vídeo em 8K ProRes, inferência local de IA (Ollama, LM Studio), compilação no Xcode e jogos** —, o calor se acumula na estrutura de alumínio, provocando queda de clock por proteção térmica (*thermal throttling*).

Coolers comuns de celular de **10W a 15W** não têm potência de bombeamento de calor suficiente para penetrar a inércia térmica do chassi do MacBook.

**O Smart Cooler Control estabelece um padrão rigoroso: ≥ 30W.** Ele desbloqueia o controle total de coolers magnéticos de alta performance equipados com câmara de vapor (Vapor Chamber), pastilhas termoelétricas Peltier (TEC) e ventiladores de até 9.000 RPM, comunicando-se diretamente via Bluetooth Low Energy (BLE) nativo no macOS.

---

## 📸 Demonstração da Interface

<div align="center">
<table>
  <tr>
    <td align="center" width="25%">
      <img src="docs/images/screenshot_auto_smartmax.png" alt="Perfil Smart Max" width="100%"/>
      <br/><b>Perfil Smart Max</b><br/>
      <sub>Salto imediato para 100% no limiar de engate</sub>
    </td>
    <td align="center" width="25%">
      <img src="docs/images/screenshot_auto_balanced.png" alt="Perfil Balanced" width="100%"/>
      <br/><b>Perfil Balanced</b><br/>
      <sub>Rampa acústica suave e progressiva</sub>
    </td>
    <td align="center" width="25%">
      <img src="docs/images/screenshot_manual.png" alt="Modo Manual" width="100%"/>
      <br/><b>Modo Manual de Precisão</b><br/>
      <sub>Slider, timer e espectro RGB</sub>
    </td>
    <td align="center" width="25%">
      <img src="docs/images/screenshot_device_picker.png" alt="Seletor Multimarca" width="100%"/>
      <br/><b>Descoberta Multimarca</b><br/>
      <sub>Catálogo BLE isolado ≥ 30W</sub>
    </td>
  </tr>
</table>
</div>

---

## 🚀 Principais Recursos

### 🧠 Piloto Automático Step-Ladder em 4 Estágios (v3.1)
- **Projetado para Apple Silicon:** Substitui curvas contínuas imprevisíveis por 4 estágios determinísticos calibrados para o comportamento térmico dos chips M1–M4:
  - **Standby (< 50°C):** Ventoinha a 0% / TEC 0W em repouso e navegação leve.
  - **Tier 1 — Quiet (≥ 50°C):** 40% ventoinha (`.low`) com liberação abaixo de 42°C.
  - **Tier 2 — Balanced (≥ 60°C):** 60% ventoinha (`.medium`) com liberação abaixo de 55°C.
  - **Tier 3 — Boost (≥ 65°C):** 80% ventoinha (`.medium`) com liberação abaixo de 61°C.
  - **Tier 4 — Turbo (≥ 70°C):** 100% ventoinha (`.max`) com liberação abaixo de 66°C para máxima sustentação térmica.
- **Histerese Assimétrica e Dwell Dinâmico:** Subida imediata em picos de compilação/render; amortecimento de 20s para reduções de velocidade protegendo a pastilha semicondutora, com bypass rápido em 3s se houver queda térmica brusca ($dT/dt \le -3^\circ\text{C/s}$).

### ❄️ Governador de Segurança Universal contra Condensação
- Coolers de 30W a 45W podem atingir temperaturas negativas ($< 0^\circ\text{C}$) na face fria.
- O Smart Cooler Control aplica uma trava de segurança em nível de hardware em **TODOS os modos** (Auto, Manual e Turbo):
  - **Corte Imediato:** Se a temperatura do processador cair para **`< 36.0°C`**, a alimentação é cortada instantaneamente para 0% (Standby).
  - **Rearme Seguro:** Permanece em Standby até a temperatura subir de forma estável para **`≥ 38.0°C`**.

### ⚙️ Controle em Três Modos (Tri-Mode)
- **Auto:** Autopilot inteligente com degraus determinísticos e proteção ativa.
- **Manual:** Slider contínuo de 10 posições (0% a 100%) para controle acústico e térmico tátil.
- **Turbo:** Potência máxima imediata (100%) com preservação da segurança contra condensação.

### 🌈 LED Térmico Calibrado por Família de Mac
- O LED do cooler reflete o envelope térmico real do Apple Silicon:
  - **MacBook Air (passivo):** **Azul** (frio/nominal `< 65°C`) $\rightarrow$ **Amarelo** (carga moderada `65°C–75°C`) $\rightarrow$ **Laranja** (`75°C–85°C`) $\rightarrow$ **Vermelho Alerta** (`≥ 88°C`).
  - **MacBook Pro (ventoinhas internas):** **Azul** (`< 68°C`) $\rightarrow$ **Amarelo** (`68°C–78°C`) $\rightarrow$ **Laranja** (`78°C–88°C`) $\rightarrow$ **Vermelho** (`≥ 90°C`).
  - **Mac Studio / Mac mini / Mac Pro:** **Azul** (`< 58°C`) $\rightarrow$ **Amarelo** (`58°C–68°C`) $\rightarrow$ **Laranja** (`68°C–78°C`) $\rightarrow$ **Vermelho** (`≥ 85°C`).
- **Persistência em Standby:** Mantém o LED azul sereno mesmo quando o cooler está em 0% no modo Auto, evitando alertas falsos em vermelho de firmware padrão.

### 🛡️ Integração Nativa com o Ciclo de Vida do macOS
- Monitora os eventos do sistema via `NSWorkspace`: desliga o cooler imediatamente ao **Suspender / Repouso** (`willSleepNotification`) e ao **Desligar** (`willPowerOffNotification`), e retoma o resfriamento ao **Acordar** (`didWakeNotification`).
- Reconexão automática em segundo plano ao abrir o aplicativo.

---

## 🔌 Catálogo de Coolers Homologados (Padrão ≥ 30W)

Arquitetura com isolamento de driver: cada fabricante opera em classes dedicadas, eliminando risco de contaminação de comandos BLE:

| Marca | Modelo | Potência Máxima | Arquitetura | Status |
| :--- | :--- | :---: | :--- | :---: |
| **REDMAGIC** | **VC Cooler 6 Pro+** | **40W** | Câmara de Vapor Líquida + Overclock TEC | ✅ Suportado |
| **REDMAGIC** | **Magnetic Cooler 5 Pro** | **36W** | Câmara de Vapor 3D + Pastilha TEC (9.000 RPM) | ✅ Suportado e Validado |
| **REDMAGIC** | **VC Cooler 6 Pro** | **36W** | Câmara de Vapor + Pastilha TEC | ✅ Suportado e Validado |
| **REDMAGIC** | **Cryo Cooler 8 Pro** | **36W** | Pastilha Criogênica Customizada 4ª Geração | ✅ Suportado |
| **REDMAGIC** | **Magcooler 4 Pro** | **27W** | Pastilha Magnética Alta Potência | ✅ Suportado |
| **Black Shark** | **MagCooler 5 Pro** | **35W** | TEC Customizada de 5 Estágios (5.100 RPM) | ✅ Suportado |
| **Black Shark** | **MagCooler 4 Pro** | **27W** | Canal Duplo de Potência + Ventilador | ✅ Suportado |
| **Flydigi** | **Flydigi B8X** | **30W** | TEC com Modo Overclock por Conversor | ✅ Suportado |
| **Flydigi** | **Flydigi B7X** | **27W** | Pastilha Magnética com Frequência Inteligente | ✅ Suportado |
| **MEMO** | **CX08 / CX07** | **30W–36W** | Cooler Gamer Magnético de Alta Potência | ✅ Suportado |
| **iQOO** | **Cooling Back Clip 2 Pro** | **27W–33W** | Clipe Duplo com Semicondutor | 🔄 Extração de Protocolo |
| **OnePlus** | **45W Liquid Cooler** | **45W** | Radiador Externo + Bomba d'Água TEC | 🔄 Extração de Protocolo |

---

## 🛠️ Como Instalar e Compilar

### Requisitos do Sistema
- macOS 13.0 (Ventura), macOS 14.0 (Sonoma) ou macOS 15.0 (Sequoia) ou superior.
- Mac com processador Apple Silicon (`arm64`): M1, M2, M3, M4, M5 (Base, Pro, Max ou Ultra).
- Bluetooth ativado e com permissão concedida.

### Compilação Local
```bash
# Clone o repositório
git clone https://github.com/Despensativo/redmagic-cooler-mac.git
cd redmagic-cooler-mac

# Compile e instale automaticamente em /Applications
./build.sh --run
```
O script compila o executável nativo em Swift, assina o pacote localmente e instala `/Applications/Smart Cooler Control.app` sem nenhuma dependência externa ou gerenciador de pacotes pesado.

---

## 🏷️ Palavras-Chave para Indexação (SEO)

`cooler-macbook` • `apple-silicon-cooling` • `macbook-pro-m3` • `macbook-air-m2` • `resfriamento-ativo-mac` • `thermal-throttling-mac` • `cooler-redmagic-mac` • `redmagic-5-pro` • `vc-cooler-6-pro` • `black-shark-cooler` • `flydigi-b8x` • `cooler-peltier-mac` • `swift-macos` • `appkit` • `corebluetooth` • `menu-bar-mac` • `controle-ventoinha-mac`

---

## 🤖 Seu Cooler Não Funcionou? Correção Assistida por IA e Envio de Relatório

Como os fabricantes de coolers Bluetooth lançam novas revisões de firmware ou mudam os UUIDs das características GATT entre lotes, pode acontecer de algum modelo conectar sem responder aos comandos ou ainda não ser reconhecido.

Você pode usar qualquer modelo de IA (**Claude, ChatGPT, Gemini, Cursor ou Antigravity**) para diagnosticar, extrair a correção na hora e nos enviar as informações necessárias:

### 1. Extraia o log de comunicação do seu cooler
Abra o app, tente escanear ou conectar ao cooler e rode este comando no Terminal do Mac para copiar as últimas 50 linhas do log:
```bash
tail -n 50 ~/.cooler.log
```

### 2. Copie e cole este Prompt no seu modelo de IA
```text
Estou usando o projeto open-source para macOS "Smart Cooler Control" (https://github.com/Despensativo/redmagic-cooler-mac).
Meu cooler Bluetooth não está funcionando como esperado ou ainda não é reconhecido.

Contexto da arquitetura do projeto:
- Os perfis de dispositivos e regras de identificação BLE ficam em `src-swift/BLE/DeviceProfile.swift`.
- Os drivers GATT isolados por marca ficam em `src-swift/BLE/Drivers/` (`RedMagicDriver.swift`, `BlackSharkDriver.swift`, `FlydigiDriver.swift`, `MemoDriver.swift`, `OnePlusDriver.swift`, `IQOODriver.swift`).
- Para compilar e testar localmente após editar, basta rodar `./build.sh --run`.

Aqui estão os dados do meu cooler e a saída do arquivo `~/.cooler.log`:
- Marca e Modelo do Cooler: [INSIRA O MODELO E POTÊNCIA EM WATTS]
- Sintoma observado: [Ex: Não aparece no Scan / Conecta mas a ventoinha não muda / LED não responde]
- Saída do log (`~/.cooler.log`):
[COLE AQUI O RESULTADO DO COMANDO tail -n 50 ~/.cooler.log]

Por favor:
1. Analise o nome anunciado via BLE, os Service UUIDs, Characteristic UUIDs e os bytes hexadecimais no log.
2. Identifique a causa raiz e gere o ajuste exato em Swift (`DeviceProfile.swift` e no driver correspondente) para que eu possa testar a correção localmente com `./build.sh --run`.
3. Gere um Resumo Técnico estruturado (Nome BLE, UUIDs de Serviço/Característica, Formato dos Bytes e Diff da Correção) pronto para eu enviar ao mantenedor do projeto.
```

### 3. Envie o resultado para atualizarmos o app oficial!
Assim que a IA gerar a correção (ou mesmo se você quiser enviar apenas o diagnóstico e o log para analisarmos), basta mandar para:
- 📧 **E-mail direto:** [despensativo@gmail.com](mailto:despensativo@gmail.com?subject=Smart%20Cooler%20Control%20-%20Relatorio%20ou%20Correcao%20de%20Cooler)
- 🐛 **GitHub Issues / PR:** [Abrir uma Issue ou Pull Request](https://github.com/Despensativo/redmagic-cooler-mac/issues)

Com essas informações, homologamos e incluímos o suporte nativo na próxima atualização para toda a comunidade!

---

## 🙏 Créditos e Agradecimentos

O **Smart Cooler Control** é um novo projeto independente e multimarca de gerenciamento térmico ativo (≥ 30W) para Apple Silicon. Agradecimentos especiais a [@hajarrashidi](https://github.com/hajarrashidi/redmagic-cooler-mac) pela base inicial focada no REDMAGIC 6 Pro a partir da qual esta plataforma evoluiu.

---

## 📄 Licença

Este projeto está licenciado sob a licença de código aberto [MIT](LICENSE).
