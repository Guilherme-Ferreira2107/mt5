# NQ Drift Pullback para Profit

## Arquivo do robô

`NQ_DriftPullback.src`

## Configuração inicial

- Tipo: estratégia de execução NTSL.
- Ativo de referência: NQ.
- Período: 5 minutos.
- Cálculo recomendado para teste: Tick a Tick.
- Horários: devem ser interpretados pelo Profit em Eastern Time (`ET`).
- Quantidade inicial: 1 contrato.

## Premissas adotadas

As regras da imagem original não eram suficientes para determinar todos os detalhes. Esta versão adota:

1. VWAP diária padrão do Profit, calculada com `VWAP(1)`.
2. VWAP ascendente/descendente pela comparação com 3 barras atrás.
3. Retorno de uma hora pela comparação do fechamento atual com 12 barras atrás.
4. Pullback long como o primeiro candle vermelho inteiramente acima e mais próximo da VWAP.
5. Pullback short como o primeiro candle verde inteiramente abaixo e mais próximo da VWAP.
6. Entrada a mercado após a confirmação do candle de gatilho.
7. Um único gatilho por regime; um novo sinal exige que o regime seja antes invalidado.
8. Uma entrada exatamente às 15:30 é permitida.
9. Zeragem obrigatória a partir de 15:55.
10. Stop/alvo derivados da leitura financeira da imagem para 1 NQ:
    - compra: stop de 4 pontos e alvo de 2 pontos;
    - venda: stop de 4 pontos e alvo de 2,5 pontos.

## Antes de usar

1. Importe ou cole o conteúdo do `.src` no Editor de Estratégias do Profit.
2. Compile como estratégia de execução.
3. Configure o gráfico para 5 minutos.
4. Confirme se o horário das barras está em ET. Se estiver em Brasília, ajuste os horários e considere as mudanças de horário de verão nos Estados Unidos.
5. Configure custos, corretagem e slippage.
6. Faça backtest Tick a Tick.
7. Valide em conta de simulação antes de qualquer uso real.

## Pontos que ainda precisam de confirmação

- NQ ou MNQ.
- Significado exato de “80 para fazer 40/50”.
- Se o candle pode tocar ou atravessar a VWAP.
- Se a entrada desejada é no fechamento, na próxima abertura ou no rompimento do candle.
- Regra exata de reinício do gatilho.
- Horário inicial e sessão usados pela estratégia original.
- Gestão adicional, como breakeven, trailing stop ou saídas parciais.

O documento completo de requisitos permanece em `../../ESPECIFICACAO_NQ_DRIFT_PULLBACK.md`.
