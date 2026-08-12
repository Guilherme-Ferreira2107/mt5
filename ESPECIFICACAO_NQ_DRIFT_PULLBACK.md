# Especificação da estratégia NQ Drift Pullback

## 1. Objetivo

Documentar as regras observadas na imagem da estratégia **NQ Drift Pullback** para futura implementação, validação e conversão em robôs de negociação.

> Status: especificação preliminar. Existem decisões importantes ainda não definidas na imagem; elas estão listadas na seção **Pendências críticas**.

## 2. Mercado e contexto

| Item | Definição observada |
|---|---|
| Ativo | E-mini Nasdaq-100 (`NQ`) |
| Série exibida | Contrato contínuo `@NQ` |
| Gráfico principal | 5 minutos |
| Gráfico auxiliar exibido | 15 minutos |
| Indicador principal | VWAP |
| Fuso horário das restrições | Eastern Time (`ET`) |

Para negociação real, o contrato contínuo deve ser substituído pelo contrato vigente do NQ ou por outro instrumento explicitamente escolhido.

## 3. Indicadores e dados necessários

- VWAP no gráfico operacional.
- Inclinação ou variação da VWAP nos últimos 15 minutos.
- Variação do preço do NQ durante a última hora.
- Cor e fechamento dos candles do gráfico operacional.
- Horário em `ET`.
- Contadores diários de operações e perdas.

## 4. Condições para compra (long)

Todas as condições abaixo devem estar satisfeitas:

1. O preço está acima da VWAP.
2. A VWAP subiu durante os últimos 15 minutos.
3. Nos últimos 60 minutos, o preço do NQ subiu pelo menos `0,1%`.
4. Não existe posição aberta.
5. Foram realizadas menos de 4 operações no dia.
6. Foram registradas menos de 2 operações perdedoras no dia.
7. O horário de entrada é anterior ou igual ao limite permitido para novas operações.
8. O filtro de direção está válido quando surge o gatilho de compra.

### Gatilho de compra

Entrar comprado no **primeiro candle vermelho em direção à VWAP**.

Interpretação preliminar:

- Candle vermelho: `fechamento < abertura`.
- O candle ocorre enquanto o preço permanece acima da VWAP.
- O movimento do candle é descendente, aproximando-se da VWAP.

Essa interpretação ainda precisa de uma definição matemática exata de “em direção à VWAP”.

## 5. Condições para venda (short)

Todas as condições abaixo devem estar satisfeitas:

1. O preço está abaixo da VWAP.
2. A VWAP caiu durante os últimos 15 minutos.
3. Nos últimos 60 minutos, o preço do NQ caiu pelo menos `0,1%`.
4. Não existe posição aberta.
5. Foram realizadas menos de 4 operações no dia.
6. Foram registradas menos de 2 operações perdedoras no dia.
7. O horário de entrada é anterior ou igual ao limite permitido para novas operações.
8. O filtro de direção está válido quando surge o gatilho de venda.

### Gatilho de venda

Entrar vendido no **primeiro candle verde em direção à VWAP**.

Interpretação preliminar:

- Candle verde: `fechamento > abertura`.
- O candle ocorre enquanto o preço permanece abaixo da VWAP.
- O movimento do candle é ascendente, aproximando-se da VWAP.

Essa interpretação ainda precisa de uma definição matemática exata de “em direção à VWAP”.

## 6. Regras de risco e operação

1. Manter somente uma posição aberta por vez.
2. Permitir no máximo 4 operações por dia.
3. Após 2 operações perdedoras no mesmo dia, bloquear novas entradas.
4. Não abrir novas posições após `15:30 ET`.
5. Encerrar qualquer posição aberta às `15:55 ET`.
6. Reiniciar os contadores de operações e perdas no começo de cada novo dia operacional.

## 7. Alvos e stops observados

A imagem contém as seguintes anotações:

- `LONG 80 to make 40`
- `SHORT 80 to make 50`

Essas anotações são ambíguas e não devem ser convertidas diretamente em código antes de confirmação.

Possíveis interpretações:

1. Compra: stop de 80 ticks/pontos e alvo financeiro de 40.
2. Compra: risco financeiro de 80 para ganho financeiro de 40.
3. Compra: quantidade 80 para obter ganho de 40.
4. Venda: stop de 80 ticks/pontos e alvo financeiro de 50.

É necessário informar a unidade de cada número: pontos, ticks, dólares, quantidade de contratos ou outra medida.

## 8. Fluxo lógico preliminar

Em cada atualização da estratégia:

1. Converter ou interpretar o horário da barra em `ET`.
2. Detectar o início de um novo dia e reiniciar os contadores.
3. Se o horário for `15:55 ET` ou posterior, encerrar a posição e bloquear entradas.
4. Se houver posição, administrar alvo e stop.
5. Se não houver posição, verificar os bloqueios diários:
   - máximo de 4 operações;
   - máximo de 2 perdas;
   - horário máximo para entrada.
6. Calcular VWAP, direção da VWAP em 15 minutos e variação do preço em 60 minutos.
7. Verificar as condições direcionais de compra ou venda.
8. Identificar o primeiro candle de pullback em direção à VWAP.
9. Enviar a ordem conforme o modelo de execução definido.
10. Registrar a operação e, depois de encerrada, atualizar o contador de perdas.

## 9. Parâmetros recomendados para implementação

Todos estes valores devem ser editáveis:

| Parâmetro | Valor inicial observado |
|---|---:|
| Período operacional | 5 minutos |
| Janela da direção da VWAP | 15 minutos |
| Janela de variação do preço | 60 minutos |
| Variação mínima do preço | 0,1% |
| Máximo de operações por dia | 4 |
| Máximo de perdas por dia | 2 |
| Horário limite para novas entradas | 15:30 ET |
| Horário de encerramento obrigatório | 15:55 ET |
| Stop da compra | A confirmar |
| Alvo da compra | A confirmar |
| Stop da venda | A confirmar |
| Alvo da venda | A confirmar |
| Quantidade de contratos | A confirmar |
| Slippage | A confirmar |
| Custos operacionais | A confirmar |

## 10. Pendências críticas

As informações abaixo são necessárias antes de criar um robô confiável:

### 10.1 Instrumento

- O robô operará `NQ`, `MNQ` ou outro ativo?
- Será usado o contrato vigente, e como será feita a troca de vencimento?

### 10.2 VWAP

- Qual VWAP será usada: diária, semanal, ancorada ou outra?
- A VWAP deve reiniciar em qual sessão e horário?
- “VWAP rising/falling over the past 15 minutes” significa comparar:
  - valor atual com o valor de 15 minutos atrás;
  - regressão/inclinação durante a janela;
  - todos os valores da janela obrigatoriamente ascendentes/descendentes?

### 10.3 Variação de 0,1% em uma hora

- Comparar o fechamento atual com o fechamento de exatamente 60 minutos atrás?
- Usar abertura, fechamento, máxima/mínima ou retorno desde o início da janela?
- A janela é móvel ou composta pelas últimas barras fechadas?

### 10.4 Definição do gatilho

- O que caracteriza matematicamente um candle “em direção à VWAP”?
- O candle precisa permanecer completamente do mesmo lado da VWAP?
- Pode tocar ou atravessar a VWAP?
- A entrada ocorre:
  - no fechamento do candle;
  - na abertura do candle seguinte;
  - no rompimento da máxima/mínima do candle de gatilho;
  - imediatamente durante a formação do candle?
- “Primeiro candle” significa o primeiro candle de cor oposta após quantos candles de impulso?
- Quando a busca pelo “primeiro candle” deve ser reiniciada?
- Dojis são ignorados ou cancelam a sequência?

### 10.5 Gestão da posição

- Confirmar o significado e as unidades de `LONG 80 to make 40` e `SHORT 80 to make 50`.
- Stop e alvo são fixos desde o preço real de execução?
- Existe breakeven, trailing stop, saída parcial ou encerramento por sinal contrário?
- O que acontece se o alvo e o stop forem tocados dentro do mesmo candle?

### 10.6 Limites diários

- Uma tentativa rejeitada ou ordem cancelada conta como operação?
- Uma operação no zero conta como perda?
- Custos e slippage entram na classificação de operação perdedora?
- Depois da quarta operação ou segunda perda, ordens pendentes devem ser canceladas?

### 10.7 Horários

- Uma entrada exatamente às `15:30 ET` é permitida?
- A estratégia usa horário de Nova York com ajuste automático de horário de verão?
- Qual é o horário inicial permitido para operar?
- A estratégia funciona em dias de pregão reduzido?

### 10.8 Execução e backtest

- Ordem de entrada a mercado, limite ou stop?
- Cálculo por fechamento de candle ou tick a tick?
- Quantidade fixa ou dimensionada pelo risco?
- Slippage esperado e custos da corretora/bolsa?
- As regras serão implementadas em qual plataforma e linguagem?

## 11. Critérios mínimos de validação

Antes de operar em conta real:

1. Validar visualmente uma amostra de sinais de compra e venda.
2. Testar com dados intrabar ou tick a tick.
3. Incluir custos e slippage realistas.
4. Separar amostra de desenvolvimento e amostra fora do período de ajuste.
5. Testar diferentes regimes de volatilidade.
6. Confirmar o comportamento na mudança do horário de verão dos Estados Unidos.
7. Confirmar o encerramento forçado e os limites diários em simulação.
8. Executar inicialmente em conta simulada.

## 12. Resumo operacional

**Compra:** tendência intradiária positiva acima da VWAP, VWAP ascendente e valorização mínima de 0,1% na última hora; comprar no primeiro candle vermelho de pullback em direção à VWAP.

**Venda:** tendência intradiária negativa abaixo da VWAP, VWAP descendente e desvalorização mínima de 0,1% na última hora; vender no primeiro candle verde de pullback em direção à VWAP.

**Proteções:** uma posição por vez, até quatro operações e duas perdas por dia, sem novas entradas depois de 15:30 ET e zeragem obrigatória às 15:55 ET.
