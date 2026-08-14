# Estratégia: Abertura 16h - 1º Candle 30min

## 1. Visão geral

Porte para MQL5 da estratégia Pine "Abertura 16h - 1º Candle 30min". A ideia é
simples: um único trade por dia, disparado no fechamento do candle de
referência (por padrão, 16:00), com direção definida pela cor desse candle e
TP/SL calculados como percentual da altura (`high - low`) dele.

Em relação à versão de 15 minutos (`abertura-1-candle-15min.mq5`, raiz do
repo), esta versão adiciona risco por operação configurável e um relatório
final no log de Experts, mas mantém o mesmo gatilho de entrada.

> **Nota de histórico:** uma versão anterior desta EA incluía uma camada de
> governança diária (meta de lucro, stop de perda, limite de trades/dia,
> limite de perdas consecutivas/dia) e um input para permitir múltiplas
> posições simultâneas. Ambos foram removidos após constatar que, dado que o
> sinal só dispara uma vez por dia, esses controles nunca chegavam a
> influenciar o comportamento real do EA (ver seção 5).

## 2. Gatilho de entrada

Em cada novo candle fechado do timeframe do gráfico (`_Period`):

1. Verifica se o candle que acabou de fechar (`rates[1]`) começou exatamente
   em `InpSessionHour:InpSessionMinute` (padrão 16:00). Como esse horário só
   ocorre uma vez por dia, isso já garante no máximo um sinal por dia.
2. Calcula `range = high - low` do candle de referência. Se `range <= 0`,
   ignora.
3. Direção = cor do candle:
   - Fechou acima da abertura (`close > open`) → **compra**
   - Fechou abaixo da abertura (`close < open`) → **venda**
4. Não entra se já existir posição aberta do mesmo símbolo/magic
   (`HasOpenPosition()`) — ou seja, se o trade do dia anterior ainda não bateu
   SL/TP, o sinal do dia é ignorado.
5. Não entra se o spread no momento estiver acima de `InpMaxSpreadPoints`.
6. Se `InpUseMAFilter=true` (padrão: desligado), aplica o filtro de tendência
   descrito na seção 2.1 antes de decidir a direção.
7. Entrada a mercado (`ORDER_TYPE_BUY`/`ORDER_TYPE_SELL`), com SL/TP enviados
   junto na mesma ordem.

### 2.1 Filtro de tendência por média móvel (`InpUseMAFilter`)

Desligado por padrão. Quando ativado, funciona como na
`abertura-1-candle-15min.mq5`: cria um handle `iMA(_Symbol, PERIOD_CURRENT,
InpMAPeriod, 0, InpMAMethod, InpMAAppliedPrice)` e compara o fechamento do
candle de referência com o valor da média **no mesmo candle** (`CopyBuffer`
com `shift=1`):

- `close_do_candle > MA` → só permite compra
- `close_do_candle < MA` → só permite venda

Se o candle de referência for de alta mas o fechamento estiver do lado errado
da média (ou vice-versa), o sinal do dia é descartado silenciosamente.
Período, método (`MODE_SMA`/`EMA`/`SMMA`/`LWMA`) e preço aplicado são todos
configuráveis via input.

## 3. Stop e alvo

Calculados a partir do candle de referência, não do preço de entrada real:

```text
BUY:
  sl = ref_close - range * InpStopLossPercent / 100   (padrão 150%)
  tp = ref_close + range * InpTakeProfitPercent / 100  (padrão 1050%)

SELL:
  sl = ref_close + range * InpStopLossPercent / 100
  tp = ref_close - range * InpTakeProfitPercent / 100
```

`ref_close` é o fechamento do candle de referência; a ordem em si é enviada
ao preço de mercado (`ask`/`bid`) no momento do envio, que pode já estar
levemente distante de `ref_close`. Se o SL calculado ficar do lado errado do
preço atual (`sl_distance <= 0`) ou o TP já tiver sido "ultrapassado", a
entrada é abortada (`ENTRY-FAIL`).

Com os padrões (SL=150%, TP=1050% do range), a relação risco:retorno é de
1:7 — bem mais assimétrica que a versão de 15min (SL=25%, TP=alvo via
`RiskRewardRatio`).

## 4. Dimensionamento (lote)

```text
risco_dinheiro = saldo * InpRiskPercent / 100   (modo RISK_PERCENT_BALANCE, padrão)
              ou InpFixedRiskMoney               (modo RISK_FIXED_MONEY)

lote = risco_dinheiro / (distância_SL_em_pontos * valor_por_ponto)
```

Lote arredondado para baixo no step do símbolo e limitado a
`SYMBOL_VOLUME_MIN`/`MAX`.

## 4.1 Proteção de lucro por retração (`InpUseProfitGiveback`)

Desligada por padrão. Quando ativada, monitora a posição aberta **a cada
tick** (não só no fechamento de candle) e fecha a mercado se o preço
devolver `InpGivebackPercent`% (padrão 50%) do maior movimento favorável já
atingido desde a entrada.

Mecânica (`ManageProfitGiveback()`):

1. A cada tick, atualiza o "pico" — a melhor cotação (bid para compra, ask
   para venda) alcançada desde a abertura da posição.
2. Calcula o movimento favorável = `pico - entrada` (compra) ou
   `entrada - pico` (venda). Se esse valor ainda não for positivo (a posição
   nunca esteve no lucro), não faz nada — **este recurso nunca corta uma
   posição no prejuízo**, só protege lucro já formado.
3. Se o preço atual recuar até `pico - movimento_favoravel *
   (InpGivebackPercent/100)` (compra) ou o equivalente para venda, fecha a
   posição a mercado.

Como o preço de gatilho fica sempre entre a entrada e o pico (para qualquer
percentual entre 0 e 100), o fechamento só pode ocorrer enquanto a posição
ainda está com lucro em relação à entrada — exatamente o comportamento
pedido ("só para o caso de ganho"). O SL/TP originais continuam ativos no
lado do broker; a proteção de lucro é apenas um gatilho adicional que pode
fechar a posição antes deles.

Se o fechamento falhar (ex.: erro de envio da ordem), a EA registra
`[EXIT-FAIL]` no log de Experts — esse é o único log que a EA emite fora do
relatório final, exatamente por indicar uma falha real, não um evento
rotineiro.

## 4.2 Fechamento forçado por horário no dia seguinte (`InpUseTimeExit`)

Desligado por padrão. Quando ativado, encerra a posição a mercado no
**`InpExitHour:InpExitMinute` (padrão 23:00) do dia seguinte ao da entrada** —
não no mesmo dia. Como a estratégia só entra uma vez por dia, isso dá
margem para o trade trabalhar durante todo o resto do dia da entrada, e só
aplica o corte a partir da sessão seguinte. É **incondicional**: fecha estando
em lucro ou prejuízo, ao contrário do giveback (seção 4.1).

Mecânica (`ManageTimeExit()`): a cada tick, compara a data de abertura da
posição (`POSITION_TIME`, gravada pelo próprio terminal — sobrevive a
reinícios da EA) com a data atual. Enquanto ainda for o mesmo dia da entrada,
não faz nada; a partir do dia seguinte, passa a checar se o horário atual já
atingiu `InpExitHour:InpExitMinute` e, se sim, fecha.

## 5. Por que não há governança diária nem múltiplas posições

O gatilho (`IsTriggerCandle`) só pode ser verdadeiro uma vez por dia (um
horário fixo). Isso tem uma consequência importante: **qualquer controle que
dependa de "bloquear a próxima entrada do dia" nunca tem efeito**, porque não
existe uma próxima entrada no mesmo dia para bloquear. Especificamente:

- Meta/stop diário eram avaliados só depois que um trade fechava
  (`OnTradeTransaction`) — nesse momento o único trade do dia já tinha
  acontecido, então bloquear novas entradas não fazia diferença.
- `InpMaxTradesPerDay=1` nunca era testado de fato: o contador de trades do
  dia só poderia chegar a 1 depois que já não havia mais sinal naquele dia.
- `InpMaxConsecLossesPerDay` também nunca disparava: como só há 1 trade/dia,
  o contador de perdas consecutivas *no dia* nunca passava de 1 — o mesmo
  valia para a estatística "sequência máxima de perdas (trades)" do relatório
  final, que na prática nunca passava de 1 e não media nada útil (a
  estatística equivalente e significativa é "sequência máxima de dias
  negativos", que continua no relatório).
- O input `InpAllowMultiplePositions` (testado e descartado) permitia ignorar
  o `HasOpenPosition()` e abrir uma posição nova mesmo com uma já aberta, mas
  não trouxe benefício observado na estratégia e foi removido.

O único filtro de entrada que continua ativo e é, de fato, avaliado a cada
sinal é o de spread (`SpreadOk()` / `InpMaxSpreadPoints`).

Se no futuro o sinal passar a poder disparar mais de uma vez por dia (ex.:
reentrada após stop), esses controles voltam a fazer sentido — é só
reintroduzi-los nesse momento.

## 6. Parâmetros principais

| Parâmetro | Padrão | Descrição |
|---|---:|---|
| `InpSessionHour` / `InpSessionMinute` | 16:00 | Horário do candle de referência |
| `InpTakeProfitPercent` | 1050% | TP como % da altura do candle |
| `InpStopLossPercent` | 150% | SL como % da altura do candle |
| `InpMaxSpreadPoints` | 100 | Spread máximo permitido no momento da entrada |
| `InpRiskMode` | `RISK_PERCENT_BALANCE` | Risco fixo em dinheiro ou % do saldo |
| `InpRiskPercent` | 0.5% | Risco por operação (se % do saldo) |
| `InpFixedRiskMoney` | 50.0 | Risco por operação (se fixo) |
| `InpUseMAFilter` | false | Ativa o filtro de tendência por média móvel |
| `InpMAPeriod` | 50 | Período da média móvel |
| `InpMAMethod` | `MODE_SMA` | Método da média móvel |
| `InpMAAppliedPrice` | `PRICE_CLOSE` | Preço aplicado da média móvel |
| `InpUseProfitGiveback` | false | Ativa o fechamento por retração de lucro |
| `InpGivebackPercent` | 50.0 | % do movimento favorável que, se devolvido, fecha a posição |
| `InpUseTimeExit` | false | Ativa o fechamento forçado no dia seguinte à entrada |
| `InpExitHour` / `InpExitMinute` | 23:00 | Horário do dia seguinte em que a posição é encerrada |
| `InpMagicNumber` | 20260710 | Identificador das posições da EA |

## 7. Timeframe

Não há timeframe fixo no código — ele usa `_Period` (o timeframe do gráfico)
em todas as chamadas (`CopyTime`, `CopyRates`). O nome do arquivo reflete a
migração original (candle de 30 minutos), mas a EA deve ser anexada a um
gráfico M30 para reproduzir o comportamento pretendido; em outro timeframe, o
"candle de referência" passa a ter a duração desse timeframe.

## 8. Log e relatório

Não há CSV nem log detalhado configurável nesta versão (ambos existiram e
foram removidos por simplicidade). O que resta:

- `[ENTRY-FAIL]` no log de Experts quando uma entrada é abortada (SL/TP
  inválido em relação ao preço atual, ou lote calculado ≤ 0).
- `[EXIT-FAIL]` quando um fechamento pela própria EA (giveback ou corte por
  horário) falha ao enviar a ordem.
- `ERRO: ...` quando a criação do handle da média móvel ou a leitura do seu
  buffer falham.
- Ao remover a EA do gráfico (`OnDeinit`), imprime um relatório final único:
  total de trades, dias operados, dias positivos/negativos, profit factor,
  drawdown máximo, sequência máxima de dias negativos, expectativa por
  trade/dia.

Esses quatro casos são sempre impressos (não dependem de nenhum input) — a
ideia é que o log só fale quando algo dá errado ou quando a sessão termina,
sem ruído de eventos rotineiros (entradas/saídas bem-sucedidas, bloqueios por
spread ou MA, virada de dia). Se precisar rastrear trade a trade, use o
histórico da conta (`HistorySelect`/aba "Histórico" do terminal) — o
`InpMagicNumber` identifica as posições desta EA.

## 9. Pontos de atenção / possíveis ajustes futuros

- Sem filtro de tendência (MA) por padrão — todo candle de referência gera um
  sinal, compre ou venda, desde que passe pelo filtro de spread.
- TP muito distante do SL (1050% vs 150% do range, ~1:7) faz o alvo raramente
  ser atingido dentro do mesmo pregão; vale observar o tempo médio de
  permanência em posição ao avaliar resultados.
- Não há trava `AutoTrade` explícita como na versão de 15min — a EA envia
  ordens reais assim que anexada ao gráfico (com `AutoTrading` do terminal
  ligado).

## 10. Como testar

1. Compile `expert-index.mq5` no MetaEditor (dentro desta pasta).
2. No Strategy Tester, use o ativo desejado no timeframe **M30**.
3. Não há trava explícita de `AutoTrade` nesta versão — a EA opera assim que
   anexada, então em conta real use spread/risco conservadores até validar em
   demo.
4. Revise `InpRiskPercent`/`InpFixedRiskMoney` antes de qualquer teste com
   dinheiro real.
5. Confira o relatório final impresso no log de Experts (`OnDeinit`) e o
   histórico de negociações do Strategy Tester para validar as estatísticas
   do backtest.

Não use em conta real sem backtest, teste forward em demo e revisão dos
limites de lote/risco para o ativo.
