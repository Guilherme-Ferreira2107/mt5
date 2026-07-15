---
name: mt5-ea-lite
description: Scaffold a new MT5 Expert Advisor (EA) in this repo using the enxuto (lightweight) architecture from price_action_simples.mq5 — indicator handles + risco por %saldo + single-position gate + stop estrutural simples por lookback, sem sessao, sem CSV, sem governanca diaria. Use quando o usuario pedir um EA simples/rapido, "criar um EA leve", "outro price action", ou explicitamente disser que nao quer a camada de governanca da skill mt5-ea. Se o usuario nao especificar o nivel, pergunte se quer o estilo leve (esta skill) ou o completo (skill mt5-ea).
user-invocable: true
---

# /mt5-ea-lite — Scaffold a new lightweight MT5 Expert Advisor

Arguments passed: `$ARGUMENTS` (free text describing the entry signal idea, if given).

Este repo tem duas linhagens de EA. A skill `mt5-ea` cobre a linhagem
madura/completa (`zig-zag_rsi_adx*.mq5`: sessao, governanca diaria,
CSV/relatorio). Esta skill cobre a outra linhagem, deliberadamente
enxuta: `price_action_simples.mq5`. Ela existe para prototipar uma
ideia de sinal rapido sem a sobrecarga de governanca — bom para testar
um gatilho novo antes de decidir se ele "vira" um EA completo.

**Nao ofereca a camada de governanca diaria/CSV desta skill.** Se o
usuario pedir isso no meio da conversa, avise que esse e o escopo da
skill `mt5-ea` e pergunte se ele quer trocar de skill em vez de
misturar as duas.

## Esqueleto fixo (copiar a forma, trocar o sinal)

Estrutura de `price_action_simples.mq5`, nesta ordem:

1. **Header** com aviso padrao de AutoTrade real + `#property strict` +
   `#include <Trade/Trade.mqh>`.
2. **Inputs comuns** (mantenha os nomes, ajuste s0 os defaults):
   `RiskRewardRatio`, `RiskPercent`, `AutoTrade` (default `false`),
   `MagicNumber`, `DebugLog` (default `true`). Acrescente os inputs
   especificos do sinal novo (periodos de indicador, lookback, buffers
   etc.) acima desses.
3. **Globais**: `CTrade trade;` + um handle de indicador por indicador
   usado no sinal (ex.: `fastMAHandle`, `slowMAHandle` no exemplo —
   troque pelos indicadores da nova estrategia).
4. **`OnInit`**: cria os handles, valida `INVALID_HANDLE` com
   `Print` + `GetLastError()` e `return INIT_FAILED`, chama
   `trade.SetExpertMagicNumber(MagicNumber)`, avisa se `AutoTrade=false`.
5. **`OnDeinit`**: `IndicatorRelease` de cada handle criado.
6. **Helpers puros** (sem estado, reaproveitar como estao):
   - `Highest(shift, count)` / `Lowest(shift, count)` — extremos via
     `iHighest`/`iLowest`, usados como stop estrutural por lookback.
   - `LotsForRisk(stopDistance)` — sizing por `RiskPercent` do saldo,
     normalizado por `SYMBOL_VOLUME_STEP`/`MIN`/`MAX`.
   - `HasOpenPosition()` — varre `PositionsTotal()` filtrando por
     `_Symbol` + `MagicNumber`, para permitir no maximo 1 posicao por
     vez neste EA/simbolo.
7. **`OnTick`**, nesta ordem de guard clauses (nao pular nenhuma):
   `!AutoTrade` → `SYMBOL_TRADE_MODE_DISABLED` → `HasOpenPosition()` →
   gate de barra nova (`static datetime lastBarTime` comparado com
   `iTime(_Symbol, PERIOD_CURRENT, 0)`) → checagem de barras
   suficientes para os lookbacks/periodos usados. Depois: le os
   buffers dos indicadores via `CopyBuffer` (sempre checando retorno
   `<= 0`), calcula o sinal, faz `Print` de diagnostico se
   `DebugLog`, calcula `entry`/`stop`/`target` (target = entry +/-
   `(entry-stop) * RiskRewardRatio`), `LotsForRisk`, e manda
   `trade.Buy(...)`/`trade.Sell(...)` com SL/TP diretos — sem
   `OnTradeTransaction`, sem CSV, sem meta/stop diario.

O que **nao** entra nesta linhagem (isso e o que a torna "lite"):
filtro de janela de sessao, `OnTradeTransaction`, exportacao CSV,
relatorio final, limite de trades/perdas por dia, saida por tempo
maximo. Se o usuario pedir qualquer um desses, é sinal de que ele quer
a skill `mt5-ea`, nao esta.

## Workflow

1. **Entenda o sinal de entrada** (a unica parte que sempre muda).
   Se `$ARGUMENTS` ja descreve a ideia, confirme em 1-2 frases. Se
   vazio, pergunte: qual o gatilho (indicador(es) e condicao de
   cruzamento/rompimento/pullback), simbolo/timeframe alvo, e se o
   stop deve ser o lookback simples (`Highest`/`Lowest`, igual ao
   exemplo) ou algo especifico do novo sinal.

2. **Escolha a pasta/nome do arquivo** seguindo a convencao do repo:
   pasta nova por estrategia com `expert-index.mq5`, ou um `.mq5`
   solto na raiz com nome descritivo (como `price_action_simples.mq5`),
   conforme o usuario preferir.

3. **Monte o EA** seguindo o esqueleto acima, trocando apenas: os
   indicadores/handles do `OnInit`/`OnDeinit`, os inputs especificos
   do sinal, e a logica de deteccao de sinal dentro de `OnTick`
   (mantendo as guard clauses, o calculo de entry/stop/target via
   `RiskRewardRatio`, e o `LotsForRisk` intactos).

4. **Depois de escrever o arquivo**, revise manualmente (nao ha
   compilador MQL5 no ambiente): handles liberados no `OnDeinit`,
   `CopyBuffer` com checagem de retorno, sizing usando a distancia real
   do stop (nao um valor fixo), e mensagens de `Print` em portugues
   consistentes com o resto do arquivo.

## Decisoes ja fixadas pelo usuario (nao perguntar de novo)

- Esta skill e deliberadamente **sem** governanca diaria/CSV/sessao —
  isso e o que a diferencia da skill `mt5-ea`. Nao adicionar essas
  partes "por seguranca"; se fizerem falta, o EA pertence a outra
  skill.
- O sinal de entrada e sempre a parte plugavel; o resto do arquivo
  (inputs de risco, helpers, guard clauses do `OnTick`) e copiado da
  forma do `price_action_simples.mq5`.
