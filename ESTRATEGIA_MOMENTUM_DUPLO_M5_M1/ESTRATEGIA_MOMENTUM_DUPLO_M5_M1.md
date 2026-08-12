# Estratégia: Momentum Duplo (M5 viés + M1 gatilho) — EURUSD scalping

## 1. Visão geral

Ideia amadurecida em conversa a partir de "2 momentum" no gráfico de 1
minuto. Não é reversão pura (perigosa em M1 — spread e ruído dominam boa
parte do movimento) nem continuação pura (perseguir a força local de
1min vira comprar o topo facilmente). É um **híbrido**:

- Um `iMomentum` no **timeframe de referência** (`InpBiasTimeframe`,
  default M5) define a **direção** (viés comprado ou vendido) — é o
  "porquê" do trade.
- Um `iMomentum` mais rápido no **timeframe alvo** (`InpTargetTimeframe`,
  default M1) cronometra a **entrada num pullback a favor** dessa
  direção — é o "quando" do trade: espera o momentum do timeframe alvo
  recuar e voltar a cruzar 100 na direção do viés, em vez de perseguir
  o impulso ou apostar contra ele.

`iMomentum` é o indicador clássico de Larry Williams: `(preço_atual /
preço_N_períodos_atrás) * 100`, oscilando em torno de 100 — acima é
força de alta, abaixo é força de baixa.

Ativo: EURUSD apenas. Sessões: Londres + Nova York (as janelas de maior
volatilidade do par), Ásia disponível mas desligada por padrão.

**Timeframes parametrizáveis**: `InpTargetTimeframe` (gatilho/entrada)
e `InpBiasTimeframe` (referência/viés) são inputs independentes do
período do gráfico onde a EA está anexada — os defaults M1/M5 são só o
ponto de partida (nascido da ideia original de "1 minuto"), mas dá pra
testar M5/M15, M15/H1 etc. sem editar código. O único requisito
validado no `OnInit` é `InpBiasTimeframe` ser estritamente maior que
`InpTargetTimeframe` — senão a lógica "viés maior + gatilho menor"
perde sentido.

## 2. Passo a passo

1. **Viés (timeframe de referência)**: a cada candle do timeframe alvo
   fechado, lê o último valor fechado do `iMomentum` no timeframe de
   referência (`InpBiasTimeframe`, `InpMomentumBiasPeriod`). `> 100` =
   viés de alta, `< 100` = viés de baixa.
2. **Gatilho (timeframe alvo)**: lê as 2 últimas barras fechadas do
   `iMomentum` no timeframe alvo (`InpTargetTimeframe`,
   `InpMomentumTriggerPeriod`, mais rápido que o do viés).
   - Compra: viés de alta **e** a barra anterior estava em pullback
     (`<= 100 - InpMinPullbackDistance`) **e** a última barra já
     cruzou de volta acima de 100.
   - Venda: espelho, com viés de baixa.
3. **Sem máquina de estados**: diferente do
   `ESTRATEGIA_ROMPIMENTO_LT_RETRACAO` (3 estados: idle → aguarda fim
   do movimento → pendente armada), aqui a avaliação é simples —
   2 barras de lookback a cada candle fechado, igual ao padrão de
   `rsi_extremo_lite.mq5`. Ordem enviada a mercado (não pendente).
4. **Stop/alvo**: por padrão, estrutural — mínima/máxima recente do
   timeframe alvo (`InpStructuralLookback` candles) via
   `Highest`/`Lowest`, alvo por múltiplo de risco/retorno
   (`InpRiskRewardRatio`). Alternativa: fixo em pontos
   (`InpUseFixedStopTarget`).
5. **Tamanho de posição**: risco por % do saldo (`InpRiskPercent`),
   convertido em lote pela distância real até o stop.
6. **Saída da posição aberta** (a cada tick, não só no fechamento do
   candle):
   - **Viés invertido** (`InpCloseOnOppositeBias`): se o timeframe de
     referência virou contra a posição, fecha — a tese do trade não
     existe mais.
   - **Fim de sessão** (`InpCloseAtSessionEnd`): se saiu da janela de
     Londres/NY, fecha — inclusive no intervalo Londres→NY (ver seção
     4), já que a estratégia só deveria estar posicionada nas janelas
     de alta volatilidade.

## 3. Parâmetros a calibrar

| Parâmetro | Descrição |
|---|---|
| `InpBiasTimeframe` / `InpMomentumBiasPeriod` | Timeframe e período do momentum de viés (default M5/14) |
| `InpTargetTimeframe` / `InpMomentumTriggerPeriod` | Timeframe e período do momentum de gatilho (default M1/6, mais rápido que o viés) — precisa ser um timeframe menor que `InpBiasTimeframe` (validado no `OnInit`) |
| `InpMinPullbackDistance` | Distância mínima de 100 para o cruzamento contar como pullback real, não ruído (ver seção 4 — **o parâmetro mais sensível desta EA**) |
| `UsarAsia/Londres/NovaYork` + horários | Janelas de sessão (default Londres 08-11, NY 13-16, Ásia desligada) |
| `InpStructuralLookback` / `InpRiskRewardRatio` | Stop estrutural (mín/máx recente do timeframe alvo) e múltiplo do alvo |
| `InpUseFixedStopTarget` + pontos | Alternativa de stop/alvo fixo, se preferir não usar o estrutural |
| `InpRiskPercent` | Risco por trade, % do saldo |
| `InpMaxSpreadPoints` | Spread máximo para permitir entrada (EURUSD costuma ter 1-2 pips de spread típico — calibrar por corretora/horário) |

## 4. Casos de borda / pontos de atenção

- **`InpMinPullbackDistance` precisa de calibração real**: exigir só o
  cruzamento bruto de 100 (distância mínima = 0) tende a gerar sinais
  por ruído — em timeframes curtos como M1 o momentum oscila perto de
  100 o tempo todo, mesmo sem um pullback de verdade. Antes de rodar o
  backtest "de valer", observe a faixa típica do
  `iMomentum(EURUSD, InpTargetTimeframe, InpMomentumTriggerPeriod)` no
  período que for testar (ex.: plotando o indicador manualmente no
  gráfico) para escolher um valor que filtre ruído sem descartar
  pullbacks genuínos. Quanto maior o `InpTargetTimeframe` escolhido,
  menos ruidoso tende a ser o cruzamento, exigindo uma distância mínima
  menor.
- **Fechar posição no intervalo Londres→NY (11h-13h)**: é
  intencional, não um bug — `InpCloseAtSessionEnd` fecha a posição
  sempre que `IsWithinTradingWindow()` retorna falso, o que inclui o
  intervalo entre as duas sessões, não só o fim do dia. Se preferir
  manter a posição aberta durante esse intervalo (torcendo pra pegar o
  início da sessão de NY com a mesma posição), desligue esse input —
  mas sem stop/alvo estrutural recalculado nesse meio-tempo, a posição
  fica "solta" fora da janela de alta volatilidade.
- **EA independente do período do gráfico**: `InpTargetTimeframe` e
  `InpBiasTimeframe` controlam tudo via `iTime`/`iClose`/`Bars`
  parametrizados por esses inputs — não é preciso anexar a EA num
  gráfico de um período específico (ela funciona igual anexada em
  qualquer período, já que roda em cima dos handles dos indicadores, não
  do `_Period` do gráfico). O único requisito é `InpBiasTimeframe` ser
  estritamente maior que `InpTargetTimeframe`, validado no `OnInit`
  (`INIT_PARAMETERS_INCORRECT` se violado). No Strategy Tester, isso
  também simplifica a configuração — não precisa mais lembrar de trocar
  o período do gráfico do teste para bater com o timeframe alvo.
- **Sem `OnTradeTransaction`/CSV/relatório final**: arquitetura "lite"
  deliberada (ver `.claude/skills/mt5-ea-lite/SKILL.md`) — adequada
  para uma EA de alta frequência de sinais sem a sobrecarga da
  governança diária completa. Se decidir levar isso a conta real,
  vale considerar adicionar exportação de trades depois, para auditar
  o desempenho real vs. o backtest.
- **Spread no timeframe alvo**: quanto menor o `InpTargetTimeframe`
  (ex.: M1), mais o custo de spread pesa proporcionalmente em cada
  operação — `InpMaxSpreadPoints` e o próprio
  `InpStructuralLookback`/stop devem ser calibrados de olho nisso (um
  stop muito apertado em relação ao spread típico do EURUSD no seu
  broker pode inviabilizar a estratégia mesmo com sinal correto).

## 5. Como testar no Strategy Tester

1. Símbolo **EURUSD**. O período do gráfico do teste não precisa mais
   bater exatamente com `InpTargetTimeframe` (a EA agora usa os
   timeframes dos inputs, não o `_Period` do gráfico) — mas escolher o
   mesmo período de `InpTargetTimeframe` (M1 por padrão) evita
   confusão na hora de olhar o gráfico do teste.
2. Modelo de teste **"Todos os ticks"** (ou "OHLC M1") — "Apenas
   preços de abertura" não sincroniza corretamente o histórico do
   timeframe de referência usado pela perna de viés.
3. Ligue `AutoTrade = true` nos inputs (desligado por padrão, de
   propósito).
4. Rode um período de pelo menos algumas semanas para ter sinais reais
   nas duas janelas de sessão (Londres e NY).
5. Antes de tirar conclusões do backtest, calibre
   `InpMinPullbackDistance` observando o indicador de gatilho no
   período testado (ver seção 4).

## 6. Próximos passos (fora do escopo deste documento)

1. Observar visualmente o `iMomentum` do M1 e do M5 no EURUSD antes de
   fixar `InpMinPullbackDistance` e os períodos dos indicadores.
2. Rodar o backtest inicial com os defaults, depois ajustar
   stop/alvo/risco conforme o comportamento real do par nas janelas
   configuradas.
3. Compilar no MetaEditor (sem compilador disponível neste ambiente) e
   revisar manualmente antes do primeiro teste.
4. Se migrar para conta real, considerar adicionar exportação de CSV
   por trade (fora do escopo "lite" atual) para auditoria contínua.
