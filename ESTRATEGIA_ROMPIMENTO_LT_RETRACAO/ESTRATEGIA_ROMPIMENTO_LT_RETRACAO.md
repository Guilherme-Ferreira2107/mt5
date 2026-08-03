# Estratégia: Rompimento de Estrutura + Entrada na Retração de 50%

## 1. Visão geral

Identifica-se uma linha de tendência (LT) via pivôs do ZigZag. Quando o preço
rompe a LT com fechamento além do último topo/fundo estrutural (quebra de
estrutura), mede-se o movimento que causou o rompimento. A entrada é uma ordem
pendente no nível de 50% de retração desse movimento, com stop no extremo de
origem do movimento e alvo no extremo final do movimento (100%).

**Importante — é uma estratégia de reversão em relação à LT**: o rompimento
operado é contrário à inclinação da própria LT, não a favor dela. Uma LTB
(linha de tendência de baixa, ligando topos descendentes) é rompida **para
cima**, gerando uma **compra**; uma LTA (linha de tendência de alta, ligando
fundos ascendentes) é rompida **para baixo**, gerando uma **venda**. Ou seja,
a estratégia entra na reversão do movimento que a LT representava, não na
continuação dele.

## 2. Passo a passo

1. **Traçar a LT**: conectar os 2 últimos pivôs confirmados do ZigZag do mesmo
   tipo — 2 fundos ascendentes para LTA, 2 topos descendentes para LTB. Pivô
   "confirmado" = todo pivô do ZigZag exceto o mais recente (que ainda pode
   repintar).
2. **Aguardar rompimento confirmado**: um candle precisa **fechar** além do
   último topo/fundo estrutural (não vale só pavio/intrabar), com margem
   mínima de `0.2 × ATR` além do nível — isso filtra falsos rompimentos por
   ruído. O múltiplo de ATR é um parâmetro calibrável. O "último topo/fundo
   estrutural" é o pivô confirmado mais recente do ZigZag na direção
   contrária ao rompimento — **não é necessariamente um dos dois pivôs
   usados para traçar a LT** (passo 1). É comum existir um pivô mais recente
   e mais interno à estrutura, formado depois dos dois pontos que definiram
   a LT, e é esse pivô mais recente que precisa ser rompido para confirmar a
   quebra de estrutura.
3. **Registrar início do movimento**: mínima (rompimento de alta) ou máxima
   (rompimento de baixa) imediatamente antes do candle de rompimento — esse é
   o ponto de origem do movimento (0% / extremo de stop).
4. **Aguardar fim do movimento confirmado**: o preço pode continuar andando
   depois do candle de rompimento. O fim do movimento (100% / extremo de
   alvo) só é fixado quando o ZigZag confirma um novo pivô na direção do
   rompimento (reversão real, não o extremo do próprio candle de rompimento).
5. **Calcular os níveis**:
   - Entrada = 50% da distância entre início e fim do movimento.
   - Stop = extremo de início do movimento (passo 3).
   - Alvo = extremo de fim do movimento (passo 4).
6. **Enviar ordem pendente**: Buy Limit (rompimento de alta) ou Sell Limit
   (rompimento de baixa) no nível de entrada, com SL e TP já definidos no
   envio da ordem.
7. **Invalidar/cancelar a pendente** se, antes do preço atingir a entrada, a
   retração formar seu próprio pivô confirmado do ZigZag e esse pivô for
   rompido na direção da tendência — isso indica que o recuo foi raso demais
   e o preço já está indo em direção ao alvo sem passar pelos 50%, então não
   faz mais sentido perseguir essa entrada.

## 3. Parâmetros a calibrar

| Parâmetro | Descrição |
|---|---|
| ZigZag Depth / Deviation / Backstep | Sensibilidade da detecção de pivôs (estrutura) |
| Período ATR | Base para a margem de tolerância do rompimento |
| Multiplicador de ATR | Tamanho da margem de tolerância (ex.: 0.2×ATR) |
| Ativo(s) e timeframe | Mercado e período gráfico onde a estratégia roda |
| % de risco por trade | Tamanho de posição via risco monetário/percentual |
| Filtros opcionais | ADX (força de tendência), sessão de horário — só se quiser herdar a arquitetura "full" do repo |
| Nº de candles para expiração de segurança | Teto de tempo para cancelar pendentes esquecidas (ver seção 4) |

## 4. Casos de borda / pontos de atenção

- **Repaint do último pivô do ZigZag**: nunca tratar o pivô mais recente como
  confirmado — mesma regra já usada em `zig-zag_rsi_adx.mq5`.
- **Retração além de 100%**: se o preço romper o início do movimento (extremo
  de stop) antes de qualquer confirmação de entrada, tratar como falso
  rompimento / estrutura invalidada, cancelando a pendente.
- **Rede de segurança por tempo**: além da invalidação por pivô (passo 7),
  manter um teto de N candles para cancelar pendentes muito antigas, para
  mercados que fiquem muito tempo sem formar um novo pivô de recuo.

## 5. Próximos passos (fora do escopo deste documento)

1. Validar as regras visualmente em gráfico/replay antes de codificar.
2. Escolher ativo/timeframe definitivos.
3. Implementar como EA em MQL5, reaproveitando:
   - `zig-zag_rsi_adx.mq5` (leitura do indicador ZigZag e detecção de
     estrutura via `GetConfirmedAscendingLows` / `GetConfirmedDescendingHighs`,
     linhas 128-276).
   - `.claude/skills/mt5-ea/structural-stop.mqh` (stop estrutural via pivôs
     confirmados, empacotado para reuso).
   - Skill `mt5-ea` como scaffold da arquitetura (risco, posição única,
     governança diária opcional).
4. Back-test no Strategy Tester do MT5.
