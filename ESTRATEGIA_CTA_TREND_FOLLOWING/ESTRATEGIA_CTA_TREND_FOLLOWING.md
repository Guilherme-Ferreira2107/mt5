# Estratégia: CTA Trend-Following

## 1. Visão geral

Porta para MQL5 o modelo Pine Script v6 de `logs.txt`. A estratégia mede a
diferença entre uma EMA rápida e uma EMA lenta, divide essa diferença pelo
desvio-padrão recente do próprio sinal e limita o resultado entre
`-InpClipValue` e `+InpClipValue`.

Por padrão roda em D1, porque `tau` é descrito como um horizonte em dias. O
timeframe é um input independente do gráfico (`InpSignalTimeframe`), portanto
a EA pode ser anexada a qualquer período.

## 2. Regras

Em cada nova barra do timeframe do sinal:

1. Calcula EMA rápida de `tau` e EMA lenta de
   `tau * InpSlowMultiplier`.
2. Calcula `s_tilde = EMA rápida - EMA lenta`.
3. Calcula o desvio-padrão populacional dos últimos
   `tau * InpNormMultiplier` valores de `s_tilde`.
4. Normaliza `s_raw = s_tilde / desvio-padrão`.
5. Limita o sinal ao intervalo configurado pelo clip.
6. Sinal positivo mantém/abre compra; negativo mantém/abre venda. Uma troca
   de polaridade fecha a posição anterior antes de abrir a oposta.

Todos os dados usados são de candles fechados. `CopyBuffer(..., shift=1)`
reproduz o uso de `close[1]` no Pine e evita viés de antecipação.

## 3. Dimensionamento

O Pine calcula:

```text
position_size = signal / EMA(abs(close[1] - close[2]), norm_period)
```

mas não usa `position_size` em `strategy.entry`. Como
`default_qty_value=100`, o backtest Pine na prática usa 100% do patrimônio,
independentemente desse cálculo.

Nesta EA, `InpUseVolatilitySizing=true` torna a intenção do modelo operacional:

```text
orçamento de risco = equity * InpDailyRiskPercent
lote = orçamento de risco * (abs(signal) / clip)
       / perda monetária por lote para um movimento igual à EWMA-vol
```

Assim, o lote diminui quando a volatilidade do ativo aumenta e cresce
linearmente com a força do sinal até o clip. Isso é uma adaptação consciente,
não uma equivalência do sizing efetivamente executado pelo Pine. Para ignorar
essa adaptação, use `InpUseVolatilitySizing=false` e configure `InpFixedLot`.

O lote só é definido na abertura/inversão; não há rebalanceamento diário da
posição já aberta, coerente com `strategy.entry` e `pyramiding=0` implícito.

## 4. Parâmetros principais

| Parâmetro | Padrão | Descrição |
|---|---:|---|
| `InpSignalTimeframe` | D1 | Timeframe usado pelo modelo |
| `InpTau` | 5 | Horizonte rápido |
| `InpSlowMultiplier` | 4 | EMA lenta = `4 * tau` |
| `InpNormMultiplier` | 16 | Janela de normalização = `16 * tau` |
| `InpClipValue` | 2,0 | Limite absoluto do sinal |
| `InpSignalDeadZone` | 0 | Zona neutra opcional |
| `InpDailyRiskPercent` | 0,50% | Risco para um movimento de uma EWMA-vol no clip |
| `InpMaxSpreadPoints` | 0 | Filtro de spread; zero desliga |
| `AutoTrade` | false | Trava explícita para envio de ordens |

## 5. Diferenças e decisões de portabilidade

- O `plot` e as linhas horizontais do Pine não pertencem a uma EA. O valor do
  sinal é emitido no log quando `InpVerboseLog=true`.
- Não há stop-loss ou take-profit no modelo fonte. A saída ocorre apenas por
  inversão do sinal (ou neutralidade, se habilitada).
- O cálculo de volatilidade reconstrói a EWMA com até cinco janelas de
  aquecimento. Pode haver diferença residual nos primeiros candles em relação
  ao histórico integral do TradingView, mas ela decai exponencialmente.
- Em conta netting, a EA bloqueia novas entradas se já existir posição de outro
  magic no mesmo símbolo, evitando fundir exposições.
- A EA não interfere em posições de outro símbolo ou magic number.

## 6. Como testar

1. Compile `expert-index.mq5` no MetaEditor.
2. No Strategy Tester, escolha o ativo e D1 (ou mantenha o timeframe desejado
   em `InpSignalTimeframe`).
3. Ligue `AutoTrade=true`.
4. Use histórico com folga para aquecimento; com os padrões, recomenda-se ao
   menos dois anos de dados antes de avaliar o resultado.
5. Compare datas de inversão com o Pine antes de calibrar risco. Custos,
   especificação de contrato e horário de fechamento diário podem produzir
   diferenças entre broker e TradingView.

Não use em conta real sem backtest, teste forward em demo e revisão dos limites
de lote/risco para o ativo.
