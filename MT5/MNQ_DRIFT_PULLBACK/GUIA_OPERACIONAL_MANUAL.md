# Guia operacional manual — MNQ Drift Pullback

Este documento descreve como identificar e executar manualmente a estratégia **Drift Pullback** no MNQ usando o indicador `DriftPullback_Indicador.mq5` no MetaTrader 5.

O indicador é uma ferramenta visual de apoio. A seta não é uma ordem automática nem garante que o preço de entrada, stop ou alvo ainda esteja disponível.

## 1. Objetivo da estratégia

A estratégia procura uma continuação de movimento depois de um pequeno recuo em direção à VWAP da sessão:

- compra quando o mercado está valorizando, acima de uma VWAP ascendente, e surge o primeiro candle vermelho aproximando-se da VWAP;
- venda quando o mercado está desvalorizando, abaixo de uma VWAP descendente, e surge o primeiro candle verde aproximando-se da VWAP.

O candle de pullback precisa estar fechado. Não tome uma decisão apenas com uma seta no candle ainda em formação.

## 2. Preparação do gráfico

Configuração recomendada para reproduzir as regras originais:

- símbolo: MNQ disponibilizado pela corretora;
- período gráfico: M5;
- VWAP: iniciada às 10:30 no horário da estratégia;
- janela de entrada: das 10:30 às 15:30;
- zeragem obrigatória: 15:55;
- inclinação da VWAP: 3 candles, correspondentes a 15 minutos no M5;
- retorno: 12 candles, correspondentes a 1 hora no M5;
- retorno mínimo: 0,10%;
- filtro EMA 20/50: desligado inicialmente.

### Parâmetros que devem ser conferidos no indicador

Use os seguintes valores:

| Parâmetro | Valor |
|---|---:|
| `InpSessionStartHHMM` | `1030` |
| `InpEntryStartHHMM` | `1030` |
| `InpLastEntryHHMM` | `1530` |
| `InpForceCloseHHMM` | `1555` |
| `InpVWAPSlopeBars` | `3` |
| `InpReturnBars` | `12` |
| `InpMinimumReturnPct` | `0.10` |
| `InpLongStopPoints` | `40.0` |
| `InpLongTargetPoints` | `20.0` |
| `InpShortStopPoints` | `40.0` |
| `InpShortTargetPoints` | `25.0` |
| `InpMaxTradesPerDay` | `4` |
| `InpMaxLossesPerDay` | `2` |

Os valores padrão da versão 1.00 do indicador não são todos iguais aos do EA. Confira essa tabela antes de utilizá-lo.

## 3. Ajuste do horário

Todos os horários da estratégia são interpretados em Eastern Time, o horário de Nova York.

O parâmetro `InpStrategyTimeOffsetMinutes` deve converter o horário do servidor da corretora para o horário da estratégia:

`horário da estratégia = horário do servidor + offset`

Exemplo:

- servidor da corretora: 14:30;
- Nova York: 09:30;
- offset: `-300` minutos.

O horário de verão pode mudar a diferença entre o servidor e Nova York. Confira o offset sempre que houver mudança de horário ou troca de corretora.

## 4. Checklist para compra

Só considere uma compra depois do fechamento do candle quando todas as condições abaixo forem verdadeiras:

- o horário está entre 10:30 e 15:30;
- o fechamento está acima da VWAP;
- a VWAP atual está acima da VWAP de 15 minutos atrás;
- o preço valorizou pelo menos 0,10% na última hora;
- o candle fechado é vermelho, isto é, fechou abaixo da abertura;
- o candle anterior não era vermelho;
- o fechamento do candle atual está mais próximo da VWAP do que o fechamento do candle anterior;
- os limites de quatro operações e duas perdas no dia ainda não foram atingidos;
- não existe outra posição da estratégia aberta.

Com `InpRequireWholeCandleSide=true`, a mínima inteira do candle também precisa estar acima da VWAP.

### Execução da compra

1. Aguarde o candle de sinal fechar.
2. Verifique novamente o checklist antes de enviar a ordem.
3. Considere a entrada no preço disponível no início do candle seguinte.
4. Posicione o stop 40 pontos abaixo do preço real de entrada.
5. Posicione o alvo 20 pontos acima do preço real de entrada.
6. Não amplie o stop depois de entrar.
7. Encerre qualquer posição ainda aberta às 15:55.

## 5. Checklist para venda

Só considere uma venda depois do fechamento do candle quando todas as condições abaixo forem verdadeiras:

- o horário está entre 10:30 e 15:30;
- o fechamento está abaixo da VWAP;
- a VWAP atual está abaixo da VWAP de 15 minutos atrás;
- o preço desvalorizou pelo menos 0,10% na última hora;
- o candle fechado é verde, isto é, fechou acima da abertura;
- o candle anterior não era verde;
- o fechamento do candle atual está mais próximo da VWAP do que o fechamento do candle anterior;
- os limites de quatro operações e duas perdas no dia ainda não foram atingidos;
- não existe outra posição da estratégia aberta.

Com `InpRequireWholeCandleSide=true`, a máxima inteira do candle também precisa estar abaixo da VWAP.

### Execução da venda

1. Aguarde o candle de sinal fechar.
2. Verifique novamente o checklist antes de enviar a ordem.
3. Considere a entrada no preço disponível no início do candle seguinte.
4. Posicione o stop 40 pontos acima do preço real de entrada.
5. Posicione o alvo 25 pontos abaixo do preço real de entrada.
6. Não amplie o stop depois de entrar.
7. Encerre qualquer posição ainda aberta às 15:55.

## 6. Limites diários

Interrompa novas entradas quando ocorrer primeiro:

- quatro operações abertas no mesmo dia; ou
- duas operações encerradas com prejuízo no mesmo dia; ou
- chegada do horário limite de 15:30.

Uma saída forçada às 15:55 deve ser contabilizada pelo resultado financeiro real. Se a posição for encerrada com lucro, ela não é uma perda diária.

Mantenha um registro próprio das operações. O histórico visual do indicador é uma aproximação e não deve substituir o diário operacional.

## 7. Tamanho da posição e risco

Os stops e alvos acima são distâncias em pontos de preço, não valores monetários fixos.

No contrato futuro MNQ listado na CME, um ponto normalmente corresponde a aproximadamente US$ 2 por contrato. Entretanto, no MT5 o símbolo pode ser oferecido como futuro, CFD ou instrumento sintético. Antes de operar, confirme na especificação do ativo:

- tamanho e valor do tick;
- volume mínimo e incremento de volume;
- moeda da conta;
- spread e comissões;
- horário de negociação;
- nome e vencimento corretos do contrato.

Com a premissa aproximada de US$ 2 por ponto e um contrato:

- stop de 40 pontos: risco bruto aproximado de US$ 80;
- alvo long de 20 pontos: ganho bruto aproximado de US$ 40;
- alvo short de 25 pontos: ganho bruto aproximado de US$ 50.

Esses valores não incluem spread, slippage, comissão, taxas nem conversão cambial.

## 8. Filtros opcionais

### EMA 20/50

Quando ativado:

- compra: fechamento acima da EMA 20 e EMA 20 acima da EMA 50;
- venda: fechamento abaixo da EMA 20 e EMA 20 abaixo da EMA 50.

Como o filtro está desligado na regra inicial, sua ativação cria uma variante da estratégia e deve ser validada separadamente.

### Distância máxima da VWAP

`InpMaxDistanceFromVWAPPoints` limita a distância entre o fechamento do candle de sinal e a VWAP. O valor `0` desliga o filtro.

### Corpo mínimo e máximo

`InpMinBodyPoints` e `InpMaxBodyPoints` limitam o tamanho do corpo do candle de sinal. O valor `0` desliga o limite correspondente.

## 9. Quando não operar

Não execute a entrada quando:

- a seta apareceu no candle ainda aberto;
- o preço cruzou a VWAP e já não atende ao regime direcional;
- a entrada só seria possível muito distante do fechamento do candle de sinal;
- o spread está anormal;
- faltam dados de volume ou a VWAP aparenta estar incorreta;
- o offset de horário não foi conferido;
- o limite diário foi atingido;
- já existe uma posição aberta;
- passou das 15:30;
- há dúvida sobre o contrato ou vencimento selecionado.

## 10. Limitações do indicador

- A seta histórica usa dados OHLC e não conhece necessariamente a sequência dos preços dentro de cada candle.
- Quando stop e alvo são tocados no mesmo candle histórico, não é possível determinar apenas pelo OHLC qual ocorreu primeiro.
- A entrada real acontece no preço disponível, incluindo spread e possível slippage, e não obrigatoriamente no fechamento mostrado pela seta.
- A simulação interna de operações e limites diários pode divergir do histórico real da conta.
- O indicador pode recalcular o candle atual; utilize apenas sinais de candles fechados.
- Os resultados podem variar entre corretoras devido a preço, volume, sessão e especificação do símbolo.

## 11. Registro recomendado

Para cada entrada, registre:

- data e horário de Nova York;
- compra ou venda;
- preço da seta e preço real de execução;
- valor da VWAP;
- retorno percentual da última hora;
- stop e alvo;
- horário e motivo da saída;
- resultado líquido após custos;
- captura de tela do gráfico.

Valide a estratégia em conta demo e em uma amostra significativa antes de considerar seu uso em conta real.

