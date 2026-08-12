# WDO Drift Pullback

Versão da estratégia adaptada especificamente para o mini dólar (`WDO`) em gráfico de 5 minutos.

## Por que a versão NQ perdeu no WDO

Os parâmetros antigos eram:

- stop de 4 pontos;
- alvo long de 2 pontos;
- alvo short de 2,5 pontos.

No WDO, cada ponto vale R$ 10 por contrato. Com slippage de um tick em cada lado e taxas, o alvo de 2 pontos praticamente desaparece. A estratégia precisaria de uma taxa de acerto excepcional apenas para empatar.

## Parâmetros iniciais desta versão

- Stop: 5 pontos, ou R$ 50 bruto por contrato.
- Alvo: 8 pontos, ou R$ 80 bruto por contrato.
- Relação retorno/risco bruta: 1,60.
- Horário de entradas: 09:15 até 13:00, no horário do gráfico.
- Máximo de 4 operações por dia.
- Máximo de 2 perdas por dia.
- Retorno mínimo em uma hora: 0,10%.
- Inclinação mínima da VWAP: 1 ponto em 3 barras.
- Médias exponenciais: 20 e 50 períodos.
- Distância máxima do pullback até a VWAP: 5 pontos.
- Confirmação válida por até 3 barras: compra após fechamento
  acima da máxima do pullback; venda após fechamento abaixo
  da mínima do pullback.
- Um novo pullback pode ser utilizado no mesmo regime após um
  intervalo mínimo de 6 barras entre entradas.

Esses valores são um ponto de partida para teste, não uma garantia de desempenho.

## Configuração do backtest

- Ativo: contrato contínuo de WDO para pesquisa; contrato vigente para simulação operacional.
- Período: 5 minutos.
- Modo: Tick a Tick.
- Slippage: testar 1 e 2 ticks.
- Executar nos limites: ligado.
- Custos: preencher taxas B3 e corretagem.

## Testes recomendados

Não escolha parâmetros apenas pelo maior lucro. Compare:

1. Stop 5 / alvo 8.
2. Stop 6 / alvo 10.
3. Stop 7 / alvo 12.
4. Retorno mínimo de 0,10%, 0,15% e 0,20%.
5. Inclinação mínima da VWAP de 0,5, 1,0 e 1,5 ponto.
6. Janelas 09:05–11:30, 09:05–12:00 e 09:05–13:00.
7. Confirmação de rompimento ligada e desligada.

Depois, valide a configuração escolhida em um período histórico que não tenha participado da seleção.
