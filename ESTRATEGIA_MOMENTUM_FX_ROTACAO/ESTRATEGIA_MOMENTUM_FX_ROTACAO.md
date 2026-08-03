# Estratégia: Momentum Cross-Sectional em Cesta de FX (rotação trimestral)

Adaptado de: https://quantpedia.com/strategies/momentum-in-mutual-fund-returns/
(código original em `momentum-in-mutual-fund-returns.py`, QuantConnect/Python).

## 1. Visão geral

O artigo original ranqueia ~500 fundos mútuos de ações pelo retorno dos
últimos 6 meses, compra o decil (10%) de melhor desempenho em pesos iguais,
e mantém por 3 meses, repetindo o processo (rebalanceamento trimestral).
É uma estratégia de **momentum cross-sectional**: o que importa não é o
desempenho absoluto de um ativo, e sim o desempenho *relativo* dentro de um
universo comparável.

MT5 não tem dados de fundos mútuos, então o universo foi substituído por uma
**cesta de pares de forex** (majors + minors + crosses) — o ativo mais
próximo, em termos de disponibilidade de histórico e negociação simultânea,
do que o artigo precisa. A lógica de ranking/seleção/rebalanceamento foi
preservada; o resto (sizing, execução, proteção de portfólio) foi adaptado
para MT5.

**Importante**: esta é uma EA fundamentalmente diferente das outras deste
repositório — não é sinal técnico em 1 símbolo, é rotação de carteira em
vários símbolos ao mesmo tempo. Ver seções 6 e 7 para as diferenças
explícitas.

## 2. Passo a passo

1. **Universo**: lista de pares de FX configurável (`InpUniverse`,
   separados por vírgula). No `OnInit`, cada símbolo é validado via
   `SymbolSelect` — os que o broker não oferece são ignorados (log).
2. **Momentum**: para cada símbolo do universo, calcula-se o retorno dos
   últimos `InpMomentumTradingDays` (default 126 ≈ 6 meses úteis, mesma
   janela do artigo) usando `iClose` em D1: `(preço_agora - preço_então) /
   preço_então`. Símbolos sem histórico suficiente são ignorados nesse
   rebalanceamento.
3. **Ranking**: os símbolos prontos são ordenados por momentum
   decrescente.
4. **Seleção**:
   - Top `InpTopPercent`% (default 20%) → carteira comprada.
   - Se `InpAllowShort = true`, bottom `InpBottomPercent`% (default 20%)
     → carteira vendida (o artigo é long-only; o long-short é uma opção
     extra, não o comportamento default).
5. **Peso por posição**: `InpGrossExposurePercent / N` (equal-weight entre
   as posições selecionadas), limitado a `InpMaxSymbolWeightPercent` por
   símbolo (proteção caso `N` fique pequeno).
6. **Rebalanceamento**: a cada `InpRebalanceMonths` meses (default 3,
   igual ao artigo). Posições cujo símbolo/direção não está mais na
   lista-alvo são fechadas (`REBALANCE_ROTATED_OUT`); símbolos novos na
   lista-alvo sem posição aberta são abertos a mercado. Posições que
   continuam na lista-alvo, na mesma direção, **não são mexidas** (não
   reajusta peso a cada rebalanceamento como o `SetHoldings` do QC faria)
   — simplificação deliberada para reduzir custo de transação (ver seção
   7).
7. **Proteção de portfólio**: monitorado a cada tick — se o drawdown de
   equity (do pico) atingir `InpMaxDrawdownPercent`, o EA entra em
   kill-switch: para de rebalancear e, se `InpFlattenOnMaxDrawdown = true`,
   zera todas as posições. Ver seção 7 sobre por que isso substitui o stop
   por operação.

## 3. Parâmetros a calibrar

| Parâmetro | Descrição |
|---|---|
| `InpUniverse` | Cesta de pares FX (csv). Ajustar à oferta real do broker. |
| `InpMomentumTradingDays` | Janela de momentum em dias úteis (126 ≈ 6 meses) |
| `InpRebalanceMonths` | Frequência de rebalanceamento em meses (3 = trimestral, igual ao artigo) |
| `InpTopPercent` / `InpBottomPercent` | % do universo comprado / vendido |
| `InpAllowShort` | Long-only (fiel ao artigo) vs long-short |
| `InpMinUniverseReady` | Mínimo de símbolos com histórico OK para rebalancear |
| `InpGrossExposurePercent` | Exposição bruta total (% do saldo) dividida entre as posições |
| `InpMaxSymbolWeightPercent` | Teto de peso por símbolo |
| `InpMaxSpreadPoints` | Spread máximo por símbolo no momento da abertura (calibrar por classe — JPY tem escala de ponto diferente dos demais) |
| `InpMaxDrawdownPercent` / `InpFlattenOnMaxDrawdown` | Kill-switch de portfólio |
| `InpHardStopPercent` | Stop de segurança opcional por posição (0 = desliga) |

## 4. Casos de borda / pontos de atenção

- **Sizing aproximado por par**: o lote-alvo usa
  `notional = saldo * peso%`, convertido em lote via
  `(preço / tick_size) * tick_value` — o `tick_value` do MT5 já embute a
  conversão de moeda de cotação para moeda da conta, então a fórmula
  funciona para qualquer par, mas é uma aproximação (não conta
  correlação entre posições, nem margem exata).
- **Escala de pontos varia entre pares**: `InpMaxSpreadPoints` em pontos
  brutos do símbolo não é comparável entre um par JPY (2 casas) e os
  demais (4-5 casas) — calibre por classe ou aceite o filtro ser mais
  permissivo/restritivo dependendo do par.
- **Símbolo ausente no broker**: ignorado silenciosamente (com log) na
  montagem do universo — se `InpMinUniverseReady` não for atingido, o EA
  não rebalanceia (loga aviso) até ter símbolos suficientes.
- **Sem stop por operação (por padrão)**: fiel ao artigo, que não usa
  stop-loss — a proteção é o kill-switch de drawdown do portfólio
  (`InpMaxDrawdownPercent`). Isso é uma decisão de risco real: até o
  kill-switch disparar, uma posição individual pode perder bem além do
  que uma EA com stop estrutural permitiria. Se quiser mais proteção por
  posição, ative `InpHardStopPercent`.

## 5. Diferenças em relação ao artigo original

| Artigo (QuantConnect) | Esta EA (MT5) | Motivo |
|---|---|---|
| ~500 fundos mútuos (equity funds) | Cesta de pares FX configurável | MT5 não tem dado de fundo mútuo; FX é o que tem histórico simultâneo e liquidez em qualquer broker MT5 |
| Decis (10 grupos) | Top/Bottom % configurável | Com dezenas de pares (não centenas), decis ficam pequenos demais (2-3 símbolos); % é mais flexível |
| Long-only | Long-only por padrão, long-short opcional (`InpAllowShort`) | Long-short é uma extensão natural para FX (não existe "venda a descoberto" limitada como em ações), mas o default respeita o artigo |
| `SetHoldings` reajusta peso todo rebalanceamento | Só abre/fecha o que mudou de lista-alvo; mantém posições que continuam qualificadas | Reduz custo de transação/slippage; equal-weight já é aproximadamente estável entre rebalanceamentos consecutivos se N não mudar muito |
| Sem stop-loss | Sem stop por padrão + kill-switch de drawdown de portfólio (+ stop opcional por posição) | Rodar 3 meses sem nenhuma proteção é um risco real em conta alavancada; kill-switch é a rede de segurança equivalente |

## 6. Diferenças em relação à arquitetura padrão do repo (skill `mt5-ea`)

Esta EA **não** usa os blocos padrão de `session-window.mqh` /
`structural-stop.mqh` / governança diária de `risk-governance.mqh`, porque
eles pressupõem uma EA de sinal técnico intradiário em 1 símbolo:

- **Sem filtro de sessão**: a estratégia opera em D1 com rebalanceamento
  trimestral, não em janelas de horário intradiárias.
- **Sem stop estrutural (ZigZag/lookback)**: não há um "movimento" de
  preço a medir — a tese é ranking relativo, não rompimento de estrutura.
- **Sem governança diária (meta/stop do dia, trades/perdas por dia)**:
  não faz sentido em uma EA que abre posições a cada 3 meses; foi
  substituída por governança de portfólio (`InpMaxDrawdownPercent` +
  kill-switch), que é o equivalente na escala de tempo certa para esta
  estratégia.
- **Múltiplas posições simultâneas, vários símbolos**: ao contrário do
  padrão "1 posição por vez" das outras EAs, aqui é normal ter N posições
  abertas ao mesmo tempo (uma por símbolo selecionado).

O que **foi mantido** do padrão do repo: magic number, filtro de spread
(por símbolo), sizing por risco (adaptado para peso de portfólio em vez de
risco por stop), CSV de trades, log verboso, relatório final no
`OnDeinit`.

## 7. Como testar no Strategy Tester (multi-símbolo)

Esta EA abre ordens em símbolos diferentes do gráfico onde está anexada —
isso exige o modo de teste multi-símbolo do MT5:

1. No **Strategy Tester**, selecione o modelo **"Todos os ticks (baseado
   em ticks reais)"** — é o único modo que carrega dados de múltiplos
   símbolos simultaneamente de forma consistente.
2. Anexe/teste em **qualquer símbolo do gráfico em D1** (ele só serve de
   "relógio" para detectar nova barra diária — não precisa estar na
   cesta `InpUniverse`, mas ajuda deixá-lo nela).
3. Antes de rodar, garanta que o terminal tem **histórico D1 baixado**
   para todos os símbolos da cesta: abra um gráfico D1 de cada par (ou
   use a janela "Símbolos" → aba "Barras"/"Histórico" → baixar) cobrindo
   o período do teste + `InpMomentumTradingDays` úteis de folga no início.
4. Rode o teste e acompanhe o log de `[REBALANCE]` no separador
   "Diário"/"Jornal" — cada rebalanceamento imprime a lista comprada
   (e vendida, se `InpAllowShort`).
5. Dois CSVs são gerados na pasta `MQL5/Files`: um por trade fechado
   (`MOMENTUM_FX_<magic>.csv`) e um por rebalanceamento
   (`MOMENTUM_FX_REBALANCES_<magic>.csv`, com a lista comprada/vendida em
   cada data) — útil para auditar se o ranking está fazendo sentido.

## 8. Versão Pine Script (TradingView)

Além do EA MT5, a mesma lógica de ranking foi portada para Pine Script v6
em dois arquivos desta pasta — mas com uma limitação estrutural do Pine
que não existe no MT5: **`strategy()` só envia ordens no símbolo do
gráfico onde está rodando**. Não existe backtest de portfólio
multi-símbolo de verdade no TradingView (não dá para abrir posições
simultâneas em 28 pares dentro de uma única estratégia e ver uma curva de
patrimônio agregada). Por isso, viraram dois scripts com propósitos
diferentes:

- **`momentum_fx_ranking_indicator.pine`** — indicador (não `strategy`)
  que calcula o momentum de todos os pares da cesta via
  `request.security()` e mostra uma tabela com o ranking atual (top %
  em verde, bottom % em vermelho, se habilitado). É o painel fiel à
  lógica cross-sectional, mas sem equity curve — serve para inspecionar
  visualmente se o ranking faz sentido, mesmo papel dos CSVs de
  rebalanceamento do EA.
- **`momentum_fx_rotation_strategy.pine`** — `strategy()` que compra ou
  vende **apenas o símbolo do gráfico**, quando ele está no Top/Bottom %
  do ranking calculado contra o resto da cesta (input `Resto da cesta`,
  que não deve incluir o próprio símbolo do gráfico, para não contá-lo
  duas vezes). Roda o Strategy Tester do TradingView, mas é um backtest
  **por símbolo isolado** — assume 100% do capital alocado quando esse
  símbolo está selecionado, não a fração `1/N` do portfólio real que o
  EA usa. Para comparar pares, troque o símbolo do gráfico e rode de
  novo — não existe uma curva de patrimônio única somando todos.

Pontos de atenção específicos do Pine:

- Ajuste os prefixos de exchange nos tickers (`FX:`, `OANDA:`,
  `FX_IDC:`, `FOREXCOM:` etc.) conforme o feed de dados disponível na
  sua conta TradingView — os tickers default usam `FX:`.
- `request.security()` com símbolo dinâmico dentro de um loop é
  suportado ("dynamic requests"), mas o TradingView limita a ~40
  símbolos distintos por script — os 28 pares default cabem dentro
  desse teto; não adicione dezenas a mais sem checar o limite do seu
  plano.
- O relógio de rebalanceamento (`rebalanceDue`) dispara na primeira
  barra de um novo mês **do gráfico**. Rode em gráfico Diário — em
  timeframes intradiários o rebalanceio dispara atrasado (na primeira
  barra intradiária do mês), e em Semanal/Mensal pode não alinhar.

## 9. Próximos passos (fora do escopo deste documento)

1. Confirmar a cesta de pares (`InpUniverse`) contra o que o broker
   realmente oferece com histórico completo.
2. Validar visualmente algumas datas de rebalanceamento (ranking bate com
   o gráfico?) antes de rodar o backtest completo.
3. Rodar o backtest multi-símbolo conforme seção 7.
4. Calibrar `InpMaxSpreadPoints` por classe de par e `InpMaxDrawdownPercent`
   / `InpHardStopPercent` conforme a tolerância a risco desejada.
