---
name: mt5-ea-lite
description: Scaffold a new MT5 Expert Advisor (EA) in this repo using the enxuto (lightweight) architecture from price_action_simples.mq5 / doji_pavio_superior_lite.mq5 — indicator handles + risco por %saldo + single-position gate + stop estrutural ou fixo + filtro de tendencia por media movel (opcional) + janela unica de horario (opcional), sem multiplas sessoes, sem CSV, sem governanca diaria. Use quando o usuario pedir um EA simples/rapido, "criar um EA leve", "outro price action", ou explicitamente disser que nao quer a camada de governanca da skill mt5-ea. Se o usuario nao especificar o nivel, pergunte se quer o estilo leve (esta skill) ou o completo (skill mt5-ea).
user-invocable: true
---

# /mt5-ea-lite — Scaffold a new lightweight MT5 Expert Advisor

Arguments passed: `$ARGUMENTS` (free text describing the entry signal idea, if given).

Este repo tem duas linhagens de EA. A skill `mt5-ea` cobre a linhagem
madura/completa (`zig-zag_rsi_adx*.mq5`: multiplas sessoes, governanca
diaria, CSV/relatorio). Esta skill cobre a outra linhagem, deliberadamente
enxuta: `price_action_simples.mq5` / `doji_pavio_superior_lite.mq5`. Ela
existe para prototipar uma ideia de sinal rapido sem a sobrecarga de
governanca — bom para testar um gatilho novo antes de decidir se ele
"vira" um EA completo.

**Nao ofereca a camada de governanca diaria/CSV/multiplas sessoes desta
skill.** Se o usuario pedir isso no meio da conversa, avise que esse e o
escopo da skill `mt5-ea` e pergunte se ele quer trocar de skill em vez de
misturar as duas.

## Esqueleto fixo (copiar a forma, trocar o sinal)

Estrutura de `price_action_simples.mq5` / `doji_pavio_superior_lite.mq5`,
nesta ordem:

1. **Header** com aviso padrao de AutoTrade real + `#property strict` +
   `#include <Trade/Trade.mqh>`.
2. **Inputs comuns** (mantenha os nomes, ajuste so os defaults) —
   agora incluem tres blocos "basicos" alem do sinal, cada um
   liga/desliga por bool:
   - Risco/execucao: `RiskRewardRatio`, `RiskPercent`, `AutoTrade`
     (default `false`), `MagicNumber`, `DebugLog` (default `true`).
   - Filtro de tendencia por media movel: `UseMAFilter` (default
     `true`), `MAPeriod`, `MAMethod` (`ENUM_MA_METHOD`, default
     `MODE_SMA`). Quando ligado, so libera compra com preco acima da
     media e so libera venda com preco abaixo da media.
   - Stop/alvo manual: `UseFixedStopTarget` (default `false`),
     `FixedStopPoints`, `FixedTargetPoints` — alternativa em pontos
     fixos ao stop estrutural do sinal + alvo por `RiskRewardRatio`.
   - Janela de horario: `UseTradingWindow` (default `false`),
     `TradingWindowStart`, `TradingWindowEnd` (strings `HH:MM`, hora do
     servidor) — uma unica janela, com suporte a cruzar a meia-noite.
     Isto NAO e a governanca de sessoes multiplas da `mt5-ea`.
   Acrescente acima desses apenas os inputs especificos do sinal novo
   (periodos de indicador do sinal, lookback, buffers etc.).
3. **Globais**: `CTrade trade;` + `maHandle` (so criado se
   `UseMAFilter`) + um handle por indicador usado no sinal (troque
   pelos indicadores da nova estrategia; sinais puramente de price
   action, como o Doji, podem nao precisar de handle proprio).
4. **`OnInit`**: cria `maHandle` (somente se `UseMAFilter`), valida
   `INVALID_HANDLE` com `Print` + `GetLastError()` e `return
   INIT_FAILED`; cria os handles dos indicadores do sinal do mesmo
   jeito; se `UseTradingWindow`, valida `TradingWindowStart`/
   `TradingWindowEnd` com `ParseTimeToMinutes` e `return
   INIT_PARAMETERS_INCORRECT` se invalido; chama
   `trade.SetExpertMagicNumber(MagicNumber)`; avisa se
   `AutoTrade=false`.
5. **`OnDeinit`**: `IndicatorRelease` de cada handle criado, sempre
   checando `!= INVALID_HANDLE` antes (a media pode nao ter sido
   criada se `UseMAFilter=false`).
6. **Helpers puros** (sem estado, reaproveitar como estao):
   - `Highest(shift, count)` / `Lowest(shift, count)` — extremos via
     `iHighest`/`iLowest`, usados como stop estrutural por lookback
     quando o sinal precisar (nem todo sinal precisa — ex.: um Doji
     usa o proprio candle de sinal como stop).
   - `LotsForRisk(stopDistance)` — sizing por `RiskPercent` do saldo,
     normalizado por `SYMBOL_VOLUME_STEP`/`MIN`/`MAX`.
   - `HasOpenPosition()` — varre `PositionsTotal()` filtrando por
     `_Symbol` + `MagicNumber`, para permitir no maximo 1 posicao por
     vez neste EA/simbolo.
   - `ParseTimeToMinutes(time_text, &minutes_total)` +
     `IsWithinTradingWindow()` — usadas so se `UseTradingWindow`.
     **Devem ser declaradas antes do `OnInit`** no arquivo, porque o
     `OnInit` chama `ParseTimeToMinutes` pra validar os inputs de
     horario (MQL5 exige declaracao antes do uso, ao contrario de
     C/C++ com header separado).
7. **`OnTick`**, nesta ordem de guard clauses (nao pular nenhuma):
   `!AutoTrade` → `SYMBOL_TRADE_MODE_DISABLED` → `HasOpenPosition()` →
   `!IsWithinTradingWindow()` (so entra no fluxo se `UseTradingWindow`
   estiver ligado; a funcao retorna `true` sempre que estiver
   desligado) → gate de barra nova (`static datetime lastBarTime`
   comparado com `iTime(_Symbol, PERIOD_CURRENT, 0)`) → checagem de
   barras suficientes (`MAPeriod + 2` se `UseMAFilter`, senao o minimo
   que o sinal precisar). Depois: se `UseMAFilter`, le a media via
   `CopyBuffer` (checando retorno `<= 0`) e calcula `allowBuy = close1
   > maValue` / `allowSell = close1 < maValue` (senao os dois ficam
   `true`); le os buffers dos indicadores do sinal do mesmo jeito;
   calcula o sinal; faz `Print` de diagnostico se `DebugLog` (incluir
   `maValue`/`allowBuy`/`allowSell` quando fizer sentido); calcula
   `entry`/`stop`/`target` — se `UseFixedStopTarget`, `stop`/`target`
   saem de `FixedStopPoints`/`FixedTargetPoints` em pontos a partir do
   `entry`; senao, `stop` e o estrutural do sinal e `target = entry +/-
   (entry-stop) * RiskRewardRatio`; usa `allowBuy`/`allowSell` como
   condicao extra no `if` de compra/venda; `LotsForRisk`; manda
   `trade.Buy(...)`/`trade.Sell(...)` com SL/TP diretos — sem
   `OnTradeTransaction`, sem CSV, sem meta/stop diario.

O que **nao** entra nesta linhagem (isso e o que a torna "lite"):
multiplas sessoes de horario (com limite de candles no inicio de cada
uma), `OnTradeTransaction`, exportacao CSV, relatorio final, meta/stop
diario, limite de trades/perdas por dia, sequencia maxima de perdas,
saida por tempo maximo. A janela unica de horario (`UseTradingWindow`)
e o filtro de MA e o stop/alvo fixo **sao basicos e entram por
padrao** — o que continua fora e a governanca diaria completa e o
log estruturado. Se o usuario pedir qualquer coisa da lista acima, e
sinal de que ele quer a skill `mt5-ea`, nao esta.

## Workflow

1. **Entenda o sinal de entrada** (a unica parte que sempre muda).
   Se `$ARGUMENTS` ja descreve a ideia, confirme em 1-2 frases. Se
   vazio, pergunte: qual o gatilho (indicador(es) e condicao de
   cruzamento/rompimento/pullback), simbolo/timeframe alvo, e se o
   stop estrutural deve ser o lookback simples (`Highest`/`Lowest`) ou
   algo especifico do novo sinal (ex.: extremo do proprio candle de
   sinal). Nao pergunte sobre filtro de MA, stop/alvo fixo ou janela
   de horario — esses tres ja entram por padrao no esqueleto (ver
   secao anterior), so ficam desligados (`false`) quando nao fizer
   sentido ligados por padrao.

2. **Escolha a pasta/nome do arquivo** seguindo a convencao do repo:
   pasta nova por estrategia com `expert-index.mq5`, ou um `.mq5`
   solto na raiz com nome descritivo (como `price_action_simples.mq5`
   ou `doji_pavio_superior_lite.mq5`), conforme o usuario preferir.

3. **Monte o EA** seguindo o esqueleto acima, trocando apenas: os
   indicadores/handles do sinal no `OnInit`/`OnDeinit`, os inputs
   especificos do sinal, e a logica de deteccao de sinal dentro de
   `OnTick` (mantendo os tres blocos basicos, as guard clauses, o
   calculo de entry/stop/target, e o `LotsForRisk` intactos).

4. **Depois de escrever o arquivo**, revise manualmente (nao ha
   compilador MQL5 no ambiente): `ParseTimeToMinutes`/
   `IsWithinTradingWindow` declaradas antes do `OnInit`; `maHandle`
   (e outros handles) liberados no `OnDeinit` sempre checando `!=
   INVALID_HANDLE`; `CopyBuffer` com checagem de retorno; sizing
   usando a distancia real do stop (estrutural ou fixo, nunca um
   valor achado por acaso); `allowBuy`/`allowSell` aplicados nas duas
   condicoes de entrada; e mensagens de `Print` em portugues
   consistentes com o resto do arquivo.

## Decisoes ja fixadas pelo usuario (nao perguntar de novo)

- Todo EA desta linhagem nasce com os tres blocos basicos —
  `UseMAFilter`, `UseFixedStopTarget`, `UseTradingWindow` — presentes
  como inputs liga/desliga, mesmo que o usuario nao peça
  explicitamente. Nao pular esses inputs "por simplicidade"; a
  simplicidade vem de eles virem desligados por default quando nao
  combinam com o sinal, nao de omiti-los.
- Esta skill e deliberadamente **sem** governanca diaria completa,
  CSV e multiplas sessoes — isso e o que ainda a diferencia da skill
  `mt5-ea`. Uma janela unica de horario ja faz parte do basico (ver
  acima); o que fica de fora e sessoes multiplas com limite de
  candles, meta/stop diario, contagem de trades/perdas por dia e
  relatorio final. Nao adicionar essas partes "por seguranca"; se
  fizerem falta, o EA pertence a outra skill.
- O sinal de entrada e sempre a parte plugavel; o resto do arquivo
  (inputs de risco, os tres blocos basicos, helpers, guard clauses do
  `OnTick`) e copiado da forma padrao acima.
