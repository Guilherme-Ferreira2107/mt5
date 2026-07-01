---
name: mt5-ea
description: Scaffold a new MT5 Expert Advisor (EA) in this repo using the proven architecture from zig-zag_rsi_adx.mq5 / zig-zag_rsi_adx_quant.mq5 (session filter, structural or fixed stop, risk-based sizing, daily risk governance, CSV/report). Use when the user asks to create a new EA, start a new strategy folder, "criar um EA", "nova estrategia MT5", or wants to port a raw signal idea into a production-shaped EA with proper risk management.
user-invocable: true
---

# /mt5-ea — Scaffold a new MT5 Expert Advisor

Arguments passed: `$ARGUMENTS` (free text describing the entry signal idea, if given).

Este repo é um laboratório de estratégias MT5 — uma pasta por ideia
(`QB/`, `ENVELOPES/`, `TRENDS/`, etc). `zig-zag_rsi_adx.mq5` e
`zig-zag_rsi_adx_quant.mq5` são os dois EAs mais maduros daqui: o
primeiro prova um estilo de sinal estrutural (ZigZag + RSI + ADX +
janelas de sessão), o segundo prova uma camada de risco/governança
diária muito mais sólida. Esta skill existe para que todo EA novo
nasça já com essas duas partes maduras, e você só precise pensar no
sinal de entrada.

## Blocos reutilizáveis (nesta pasta)

- `session-window.mqh` — filtro de até 3 janelas de horário (com virada
  de meia-noite) + limite de candles desde o início da sessão.
- `structural-stop.mqh` — duas opções de stop: lookback simples
  (extremo das últimas N barras) ou pivôs confirmados do ZigZag
  (fundo ascendente / topo descendente).
- `risk-governance.mqh` — sizing por % de saldo ou valor fixo, modos de
  RR, meta/stop diário em R ou dinheiro, limite de trades e de perdas
  seguidas por dia, saída por tempo máximo/sinal oposto, CSV e
  relatório final (profit factor, expectância, drawdown).

Esses arquivos são **referência para copiar/adaptar**, não `#include`
prontos para produção — os blocos `risk-governance.mqh` marcados como
comentário (governança diária, CSV, relatório) devem ser copiados de
`zig-zag_rsi_adx_quant.mq5` linha a linha, ajustando só os nomes de
inputs/globais conforme necessário.

## Workflow

1. **Entenda o sinal de entrada.** Se `$ARGUMENTS` já descreve a ideia,
   confirme seu entendimento em 1-2 frases. Se vazio, pergunte: qual é o
   gatilho de entrada (indicador(es), condição de cruzamento/extremo),
   símbolo/timeframe alvo, e se a estratégia é de swing (precisa de
   estrutura de topos/fundos) ou intradia/scalping (pode dispensar
   estrutura).

2. **Decida o estilo de stop** com o usuário:
   - Lookback simples (`structural-stop.mqh` opção A) — default para
     a maioria dos casos.
   - Pivôs confirmados do ZigZag (`structural-stop.mqh` opção B) — só
     se o sinal já depende de estrutura de swing (ex.: variações do
     próprio zig-zag_rsi_adx).
   - Stop fixo em pontos (mais simples, ver `InpStopLossPoints` em
     `risk-governance.mqh`) — bom para EAs de scalping tipo
     `zig-zag_rsi_adx_quant.mq5`.

3. **Decida se precisa de filtro de sessão.** Nem toda estratégia
   precisa (ex.: `zig-zag_rsi_adx_quant.mq5` usa uma janela única
   simples, não as 3 sessões). Pergunte antes de assumir 3 sessões.

4. **Sempre inclua o módulo de governança diária** de
   `risk-governance.mqh` (sizing por risco, meta/stop diário, limite de
   trades/perdas seguidas, CSV, relatório final) — isso já foi validado
   com o usuário como padrão obrigatório em todo EA novo deste repo,
   não é opcional a menos que ele peça explicitamente para tirar.

5. **Escolha a pasta/nome do arquivo** seguindo a convenção do repo:
   uma pasta nova por estratégia (ex. `MEU_SINAL/`), arquivo
   `expert-index.mq5` para o EA (ver `MA_TREND/expert-index.mq5`,
   `ENVELOPES/expert-index.mq5` como precedente) ou um nome descritivo
   como os dois arquivos `zig-zag_rsi_adx*.mq5` na raiz, se o usuário
   preferir manter na raiz.

6. **Monte o EA** combinando, na ordem:
   `OnInit` (cria handles dos indicadores do sinal, valida sessões se
   houver, zera globais de risco/dia, abre CSV) →
   `OnTick` (`RolloverDayIfNeeded` → `UpdateDrawdown` → detecta nova
   barra → se nova barra, calcula sinal e sessão/stop → `ManageOpenPosition`
   para saídas por tempo/sinal oposto → se já tem posição, retorna →
   `CanOpenNewTrade` → calcula stop e lote via `CalculateLotSize` →
   `OrderSend`) →
   `OnTradeTransaction` (agrega profit do deal, decide `exit_reason`,
   atualiza estatísticas, chama `CheckDailyLimitsAfterClose`,
   `ExportTradeRow`) →
   `OnDeinit` (libera handles, `PrintFinalReport`, fecha CSV).

7. **Depois de escrever o arquivo**, rode uma checagem de sanidade
   (não há compilador MQL5 no ambiente, então revise manualmente):
   inputs sem uso, handles não liberados, `GetFillingType()` usado em
   vez de `ORDER_FILLING_IOC` hardcoded, e que o sizing por risco usa
   a distância real do stop (não um valor fixo desatualizado).

## Decisões já fixadas pelo usuário (não perguntar de novo)

- Governança de risco diária é **sempre** incluída em EAs novos gerados
  por esta skill.
- Esta skill é sobre **arquitetura reutilizável**, não uma cópia
  1:1 do sinal ZigZag+RSI+ADX — o sinal de entrada é sempre a parte
  plugável e específica de cada nova pasta.
