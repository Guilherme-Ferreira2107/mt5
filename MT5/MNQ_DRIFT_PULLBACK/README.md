# MNQ Drift Pullback — MT5

Primeira versão do Expert Advisor para validar no Micro E-mini Nasdaq-100 (`MNQ`) através do MetaTrader 5.

## Arquivo

`MNQ_DriftPullback.mq5`

## Regras implementadas

- Gráfico operacional padrão: M5.
- VWAP da sessão calculada internamente com preço típico e volume real; quando indisponível, usa tick volume.
- Long:
  - preço acima da VWAP;
  - VWAP ascendente em 15 minutos;
  - valorização mínima de 0,10% em uma hora;
  - primeiro candle vermelho aproximando-se da VWAP.
- Short: regras simétricas.
- Uma posição por símbolo e Magic Number.
- Máximo de quatro entradas e duas perdas por dia.
- Bloqueio de novas entradas depois de 15:30.
- Zeragem obrigatória a partir de 15:55.
- Filtro EMA 20/50 disponível, desligado inicialmente.

## Premissa de risco inicial

O MNQ vale aproximadamente US$2 por ponto por contrato. A anotação original foi interpretada como:

- Long: arriscar US$80 para buscar US$40:
  - stop de 40 pontos;
  - alvo de 20 pontos.
- Short: arriscar US$80 para buscar US$50:
  - stop de 40 pontos;
  - alvo de 25 pontos.

Esses valores são parâmetros editáveis e precisam ser validados.

## Informações críticas da corretora

O MT5 pode apresentar o MNQ como futuro listado, CFD ou símbolo sintético. Antes do backtest, confirme:

1. Nome exato do símbolo, por exemplo `MNQ`, `MNQZ26` ou um nome com sufixo.
2. `SYMBOL_TRADE_TICK_SIZE`.
3. `SYMBOL_TRADE_TICK_VALUE`.
4. Volume mínimo e passo de volume.
5. Horário do servidor.
6. Disponibilidade de volume real.

O EA registra essas propriedades no Diário durante a inicialização.

## Horário

As regras originais usam Eastern Time. O input `InpStrategyTimeOffsetMinutes` converte o horário do servidor para o horário da estratégia.

Exemplo:

- servidor mostra 14:30;
- Nova York está em 09:30;
- diferença: `-300` minutos.

O horário de verão pode alterar essa diferença e precisa ser tratado na configuração do teste.

## Primeiro teste

1. Compile no MetaEditor.
2. Selecione o símbolo MNQ disponibilizado pela corretora.
3. Use M5 e ticks reais, quando disponíveis.
4. Defina corretamente o offset de horário.
5. Mantenha `InpAutoTrade=false` para inspeção dos logs.
6. Depois, no Strategy Tester, ligue `InpAutoTrade=true`.
7. Teste inicialmente com volume mínimo.

Não use em conta real antes de validar símbolo, unidade de volume, tick value, sessão, custos e execução em conta demo.
