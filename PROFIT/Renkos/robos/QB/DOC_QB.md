# MICA Robot Writer — Contexto para IA

> Este documento serve como base de conhecimento para uma inteligência artificial escrever, revisar e otimizar estratégias automatizadas na linguagem MICA (plataforma Profit / Nelogica). Ele contém sintaxe, padrões, boas práticas, exemplos reais e contexto de backtest do XAUUSD 4R.

---

## 1. Sobre a Linguagem MICA

MICA é a linguagem de script da plataforma **Profit (Nelogica)**, utilizada para criar estratégias automatizadas, indicadores e coloração de candles. É uma linguagem procedural, semelhante a Pascal/Delphi.

### Estrutura básica de uma estratégia

```pascal
// Declaração de parâmetros (configuráveis pelo usuário na interface)
Parametro
  NomeParametro(ValorDefault);

// Declaração de variáveis
var
  MinhaVariavel : real;
  MeuInteiro    : integer;
  MeuBooleano   : boolean;

// Bloco principal — executado a cada candle
begin
  // lógica aqui
end;
```

### Tipos de dados

| Tipo | Descrição | Exemplo |
|---|---|---|
| `real` | Número decimal | `3.14` |
| `integer` | Número inteiro | `14` |
| `boolean` | Verdadeiro/Falso | `True`, `False` |
| `string` | Texto | `"texto"` |

---

## 2. Sintaxe Essencial

### Operadores

```pascal
// Aritméticos
+  -  *  /

// Comparação
=   // igual
<>  // diferente
>   // maior
<   // menor
>=  // maior ou igual
<=  // menor ou igual

// Lógicos
and   // E
or    // OU
not   // NÃO

// Referência a candles anteriores
Fechamento[1]   // fechamento do candle anterior
Fechamento[2]   // fechamento de 2 candles atrás
RSI_Valor[1]    // qualquer variável pode ser indexada assim
```

### Estruturas de controle

```pascal
// Condicional simples
if (condicao) then
  acao;

// Condicional com bloco
if (condicao) then
begin
  acao1;
  acao2;
end;

// Condicional com else
if (condicao) then
  acao_se_verdadeiro
else
  acao_se_falso;

// Condicional encadeada
if (cond1) then
  acao1
else if (cond2) then
  acao2
else
  acao3;
```

---

## 3. Variáveis de Preço (Built-in)

Estas variáveis são disponibilizadas automaticamente pela plataforma a cada candle:

```pascal
Abertura        // preço de abertura do candle atual
Fechamento      // preço de fechamento do candle atual
Maxima          // máxima do candle atual
Minima          // mínima do candle atual
Volume          // volume do candle atual
Price           // preço de referência (geralmente = Fechamento)

// Indexação para candles passados
Fechamento[1]   // fechamento do candle anterior
Maxima[2]       // máxima de 2 candles atrás
```

---

## 4. Funções de Indicadores Built-in

### RSI

```pascal
// RSI(Periodo, Tipo)
// Tipo 0 = Clássico (Wilder), Tipo 1 = Simples
RSI_Valor := RSI(14, 0);

// Cruzamento de nível
CruzouAcima95 := (RSI_Valor[1] < 95) and (RSI_Valor >= 95);
CruzouAbaixo5 := (RSI_Valor[1] > 5)  and (RSI_Valor <= 5);
```

### Médias Móveis

```pascal
// Media(Periodo, Serie)
EMA20 := Media(20, Fechamento);          // EMA 20 do fechamento
EMA50 := Media(50, Fechamento);          // EMA 50
SMA200 := MediaSimples(200, Fechamento); // Média simples

// Cruzamento de médias
CruzouParaCima  := (EMA20[1] < EMA50[1]) and (EMA20 >= EMA50);
CruzouParaBaixo := (EMA20[1] > EMA50[1]) and (EMA20 <= EMA50);
```

### ATR (Average True Range)

```pascal
// MediaATR(Periodo)
ATR14 := MediaATR(14);

// Uso típico: calcular stop dinâmico
StopDinamico := Fechamento - (ATR14 * 1.5);
```

### MACD

```pascal
// MACD(PeriodoRapido, PeriodoLento, PeriodoSinal)
MACD_Linha  := MACD(12, 26, 9);
MACD_Sinal  := MACDSinal(12, 26, 9);
MACD_Histo  := MACDHistograma(12, 26, 9);
```

### Bollinger Bands

```pascal
// BollingerSup / BollingerInf / BollingerMedio (Periodo, Desvios)
BBSup  := BollingerSup(20, 2.0);
BBInf  := BollingerInf(20, 2.0);
BBMed  := BollingerMedio(20, 2.0);
```

### Keltner Channel (manual — não há função nativa)

```pascal
// Construção manual com EMA + ATR
KeltnerMedio := Media(20, Fechamento);
KeltnerSup   := KeltnerMedio + (2.0 * MediaATR(20));
KeltnerInf   := KeltnerMedio - (2.0 * MediaATR(20));
```

### Donchian Channel (manual)

```pascal
// Máxima/Mínima dos últimos N candles
DonchianSup := Highest(Maxima,  20);  // máxima dos últimos 20
DonchianInf := Lowest(Minima, 20);    // mínima dos últimos 20
DonchianMed := (DonchianSup + DonchianInf) / 2;
```

### Outras funções úteis

```pascal
Abs(valor)                    // valor absoluto
Media(periodo, serie)         // EMA (média exponencial)
MediaSimples(periodo, serie)  // SMA (média simples)
Highest(serie, periodo)       // maior valor nos últimos N candles
Lowest(serie, periodo)        // menor valor nos últimos N candles
Stochastic(K, D, Smooth)      // Estocástico
```

---

## 5. Funções de Tempo

```pascal
// Hora atual do candle
HoraAtual := Hour(Now);         // retorna 0..23
MinutoAtual := Minute(Now);     // retorna 0..59

// Data do candle
DiaAtual    := DayOfWeek(Now);  // 1=Domingo, 2=Segunda ... 7=Sábado
MesAtual    := Month(Now);
AnoAtual    := Year(Now);

// Exemplos de filtro de horário
DentroJanelaManha := (HoraAtual >= 7) and (HoraAtual < 12);
ForaDoHorario     := (HoraAtual = 13) or (HoraAtual = 14);
```

---

## 6. Comandos de Ordem

### Entradas

```pascal
BuyAtMarket;                    // Comprar a mercado
SellShortAtMarket;              // Vender (short) a mercado

BuyLimit(preco);                // Comprar no limite
SellShortLimit(preco);          // Vender no limite

BuyStop(preco);                 // Comprar no stop
SellShortStop(preco);           // Vender no stop
```

### Saídas de posição comprada (Long)

```pascal
SellToCoverAtMarket;            // Encerrar long a mercado
SellToCoverLimit(preco);        // Encerrar long no limite (take profit)
SellToCoverStop(preco);         // Encerrar long no stop (stop loss)
```

### Saídas de posição vendida (Short)

```pascal
BuyToCoverAtMarket;             // Encerrar short a mercado
BuyToCoverLimit(preco);         // Encerrar short no limite (take profit)
BuyToCoverStop(preco);          // Encerrar short no stop (stop loss)
```

### Verificação de posição

```pascal
IsBought        // boolean: true se estiver comprado
IsSold          // boolean: true se estiver vendido
IsBought[1]     // estado do candle anterior (para detectar entrada nova)
IsSold[1]
```

---

## 7. Funções Visuais

```pascal
// Pintar candle com cor
PaintBar(clRed);      // vermelho
PaintBar(clGreen);    // verde
PaintBar(clBlue);     // azul
PaintBar(clSilver);   // cinza
PaintBar(clYellow);   // amarelo

// Plotar texto no candle
// PlotText(texto, cor, posicao, tamanho)
// posicao: 0 = acima, 2 = abaixo
PlotText("COMPRA", clBlue,   0, 8);
PlotText("VENDA",  clFucsia, 2, 8);

// Plotar valor numérico como linha
Plot(RSI_Valor);
Plot2(KeltnerSup);
Plot3(KeltnerInf);
```

---

## 8. Padrão de Gerenciamento de Posição

Este é o padrão recomendado para gerenciar entradas, stops e alvos:

```pascal
var
  PrecoEntradaLong, PrecoEntradaShort : real;
  StopLong, StopShort                 : real;
  TakeLong, TakeShort                 : real;

begin
  // Preservar valores do candle anterior (memória de estado)
  PrecoEntradaLong  := PrecoEntradaLong[1];
  PrecoEntradaShort := PrecoEntradaShort[1];
  StopLong          := StopLong[1];
  StopShort         := StopShort[1];

  // ── Gerenciamento LONG ──────────────────────────────────────
  if IsBought then
  begin
    // Capturar preço na entrada (primeira vez)
    if (IsBought[1] = false) then
    begin
      PrecoEntradaLong := Price;
      StopLong  := Price - (TamanhoTijolo * ParametroStop);
      TakeLong  := Price + (TamanhoTijolo * ParametroTake);
    end;

    SellToCoverStop(StopLong);
    SellToCoverLimit(TakeLong);

    // Fallback a mercado se o candle fechou além do stop
    if (Fechamento <= StopLong) then
      SellToCoverAtMarket;
  end;

  // ── Gerenciamento SHORT ─────────────────────────────────────
  if IsSold then
  begin
    if (IsSold[1] = false) then
    begin
      PrecoEntradaShort := Price;
      StopShort  := Price + (TamanhoTijolo * ParametroStop);
      TakeShort  := Price - (TamanhoTijolo * ParametroTake);
    end;

    BuyToCoverStop(StopShort);
    BuyToCoverLimit(TakeShort);

    if (Fechamento >= StopShort) then
      BuyToCoverAtMarket;
  end;
end;
```

---

## 9. Padrão de Trailing Stop

```pascal
var
  MaiorStopLong, MaiorStopShort : real;

begin
  MaiorStopLong  := MaiorStopLong[1];
  MaiorStopShort := MaiorStopShort[1];

  if IsBought then
  begin
    if (IsBought[1] = false) then
      MaiorStopLong := Price - (TamanhoTijolo * Stop);

    // Trailing: stop sobe conforme preço avança
    if (Price - (TamanhoTijolo * Stop)) > MaiorStopLong then
      MaiorStopLong := Price - (TamanhoTijolo * Stop);

    SellToCoverStop(MaiorStopLong);
    SellToCoverLimit(Price + (TamanhoTijolo * Take));

    if (Fechamento <= MaiorStopLong) then
      SellToCoverAtMarket;
  end;

  if IsSold then
  begin
    if (IsSold[1] = false) then
      MaiorStopShort := Price + (TamanhoTijolo * Stop);

    // Trailing: stop cai conforme preço cai
    if (Price + (TamanhoTijolo * Stop)) < MaiorStopShort then
      MaiorStopShort := Price + (TamanhoTijolo * Stop);

    BuyToCoverStop(MaiorStopShort);
    BuyToCoverLimit(Price - (TamanhoTijolo * Take));

    if (Fechamento >= MaiorStopShort) then
      BuyToCoverAtMarket;
  end;
end;
```

---

## 10. Estratégia de Referência — RSI + Keltner (XAUUSD 4R)

Esta é a estratégia base desenvolvida e testada em backtest real. Use como referência de estrutura e padrão de código.

```pascal
Parametro
  Stop(0.25);
  Take(3.0);
  PeriodoRSI(14);
  NivelVenda(95);
  NivelCompra(5);
  PeriodoKeltner(20);
  MultiplKeltner(2.0);
  MediaTijolo(10);
  AtivarGerenciamento(True);

var
  TamanhoTijolo                       : real;
  RSI_Valor                           : real;
  PadraoVenda_RSI, PadraoCompra_RSI  : boolean;
  CondicoesCompra, CondicoesVenda     : boolean;
  KeltnerMedio, KeltnerSup, KeltnerInf: real;
  MediaTamanhoTijolo                  : real;
  TijoloFiltrado                      : boolean;
  TendenciaEMA                        : integer;
  HoraAtual                           : integer;
  DentroJanela                        : boolean;
  PrecoEntradaLong, PrecoEntradaShort : real;
  MaiorStopLong, MaiorStopShort       : real;

begin
  // ── Indicadores ──────────────────────────────────────────────
  RSI_Valor := RSI(PeriodoRSI, 0);

  KeltnerMedio := Media(PeriodoKeltner, Fechamento);
  KeltnerSup   := KeltnerMedio + (MultiplKeltner * MediaATR(PeriodoKeltner));
  KeltnerInf   := KeltnerMedio - (MultiplKeltner * MediaATR(PeriodoKeltner));

  TamanhoTijolo      := Abs(Fechamento - Abertura);
  MediaTamanhoTijolo := Media(MediaTijolo, TamanhoTijolo);
  TijoloFiltrado     := TamanhoTijolo >= MediaTamanhoTijolo;

  // ── Direção da EMA central ───────────────────────────────────
  if KeltnerMedio > KeltnerMedio[3] then TendenciaEMA := 1
  else if KeltnerMedio < KeltnerMedio[3] then TendenciaEMA := -1
  else TendenciaEMA := 0;

  // ── Filtro de horário ────────────────────────────────────────
  HoraAtual := Hour(Now);
  DentroJanela := not (
    (HoraAtual = 6)  or
    (HoraAtual = 13) or
    (HoraAtual = 14) or
    (HoraAtual = 21)
  );

  // ── Gatilhos RSI ─────────────────────────────────────────────
  PadraoCompra_RSI := (RSI_Valor[1] < NivelCompra) and (RSI_Valor > NivelCompra);
  PadraoVenda_RSI  := (RSI_Valor[1] > NivelVenda)  and (RSI_Valor < NivelVenda);

  // ── Confluência ──────────────────────────────────────────────
  CondicoesCompra :=
    DentroJanela        and
    TijoloFiltrado      and
    (Minima <= KeltnerInf)   and
    (Fechamento > KeltnerInf) and
    (TendenciaEMA <> 1);

  CondicoesVenda :=
    DentroJanela        and
    TijoloFiltrado      and
    (Maxima >= KeltnerSup)   and
    (Fechamento < KeltnerSup) and
    (TendenciaEMA <> -1);

  // ── Pintura visual ───────────────────────────────────────────
  if RSI_Valor > NivelVenda then PaintBar(clRed)
  else if RSI_Valor < NivelCompra then PaintBar(clGreen)
  else PaintBar(clSilver);

  if PadraoVenda_RSI  then PlotText("QB_V", clFucsia, 2, 8);
  if PadraoCompra_RSI then PlotText("QB_C", clBlue,   0, 8);

  // ── Preservar estado ─────────────────────────────────────────
  PrecoEntradaLong  := PrecoEntradaLong[1];
  PrecoEntradaShort := PrecoEntradaShort[1];
  MaiorStopLong     := MaiorStopLong[1];
  MaiorStopShort    := MaiorStopShort[1];

  // ── Gerenciamento LONG ───────────────────────────────────────
  if (IsBought and AtivarGerenciamento) then
  begin
    if (IsBought[1] = false) then
    begin
      PrecoEntradaLong := Price;
      MaiorStopLong    := Price - (TamanhoTijolo * Stop);
    end;

    if (Price - (TamanhoTijolo * Stop)) > MaiorStopLong then
      MaiorStopLong := Price - (TamanhoTijolo * Stop);

    SellToCoverStop(MaiorStopLong);
    SellToCoverLimit(Price + (TamanhoTijolo * Take));

    if (Fechamento <= MaiorStopLong) then
      SellToCoverAtMarket;
  end

  // ── Gerenciamento SHORT ──────────────────────────────────────
  else if (IsSold and AtivarGerenciamento) then
  begin
    if (IsSold[1] = false) then
    begin
      PrecoEntradaShort := Price;
      MaiorStopShort    := Price + (TamanhoTijolo * Stop);
    end;

    if (Price + (TamanhoTijolo * Stop)) < MaiorStopShort then
      MaiorStopShort := Price + (TamanhoTijolo * Stop);

    BuyToCoverStop(MaiorStopShort);
    BuyToCoverLimit(Price - (TamanhoTijolo * Take));

    if (Fechamento >= MaiorStopShort) then
      BuyToCoverAtMarket;
  end;

  // ── Entradas ─────────────────────────────────────────────────
  if (not IsBought) and (not IsSold) and CondicoesCompra and PadraoCompra_RSI then
    BuyAtMarket;

  if (not IsBought) and (not IsSold) and CondicoesVenda and PadraoVenda_RSI then
    SellShortAtMarket;
end;
```

---

## 11. Dados de Backtest — XAUUSD 4R (dez/2025–mar/2026)

Use estes dados como referência para calibrar parâmetros e filtros em novas estratégias para o mesmo ativo/timeframe.

### Estatísticas gerais

| Métrica | Valor |
|---|---|
| Total de operações | 1.101 |
| Win rate geral | 56,1% |
| Resultado total | $1.407 |
| Resultado médio por operação | $1,28 |
| Melhor operação | +$74,99 |
| Pior operação | -$9,30 |
| Operações Long (C) | 560 — WR 58,4% — resultado $951 |
| Operações Short (V) | 541 — WR 53,8% — resultado $456 |

### Performance por hora (UTC-3)

| Hora | Ops | Win Rate | Resultado | Classificação |
|---|---|---|---|---|
| 00h | 28 | 60,7% | +$54 | Bom |
| 01h | 13 | 76,9% | +$63 | Excelente |
| 02h | 34 | 50,0% | -$0 | Neutro |
| 03h | 53 | 54,7% | +$47 | Ok |
| 04h | 44 | 61,4% | +$90 | Bom |
| 05h | 42 | 64,3% | +$114 | Bom |
| 06h | 38 | 44,7% | -$37 | **BLOQUEADO** |
| 07h | 19 | 73,7% | +$81 | Excelente |
| 08h | 50 | 60,0% | +$92 | Bom |
| 09h | 36 | 58,3% | +$54 | Bom |
| 10h | 55 | 50,9% | +$9 | Neutro |
| 11h | 77 | 64,9% | +$207 | Excelente |
| 12h | 110 | 59,1% | +$259 | Excelente |
| 13h | 52 | 48,1% | -$18 | **BLOQUEADO** |
| 14h | 36 | 41,7% | -$54 | **BLOQUEADO** |
| 15h | 52 | 57,7% | +$72 | Ok |
| 16h | 40 | 60,0% | +$72 | Bom |
| 17h | 32 | 50,0% | -$0 | Neutro |
| 18h | 12 | 83,3% | +$138 | Excelente |
| 19h | 17 | 64,7% | +$45 | Bom |
| 20h | 79 | 49,4% | +$26 | Ok |
| 21h | 54 | 42,6% | -$72 | **BLOQUEADO** |
| 22h | 84 | 59,5% | +$147 | Bom |
| 23h | 44 | 52,3% | +$21 | Ok |

### Performance por dia da semana

| Dia | Ops | Win Rate | Resultado |
|---|---|---|---|
| Segunda | 277 | 55,2% | +$268 |
| Terça | 129 | 50,4% | +$11 |
| Quarta | 157 | 58,6% | +$242 |
| Quinta | 248 | 60,5% | +$520 |
| Sexta | 180 | 57,8% | +$350 |
| Domingo | 110 | 49,1% | +$17 |

### Janelas de operação testadas

| Janela | Trades | Resultado | WR | Média/op |
|---|---|---|---|---|
| Tudo (sem filtro) | 1.101 | $1.407 | 56,1% | $1,28 |
| Excluir 6h, 13h, 14h, 21h | 921 | $1.589 | 58,4% | $1,73 |
| Janela ouro (07h–12h) | 347 | $702 | 59,9% | $2,02 |
| Madrugada (00h–05h) | 214 | $368 | 59,3% | $1,72 |
| Apenas horas cirúrgicas | 624 | $1.487 | 61,9% | $2,38 |

---

## 12. Regras para a IA Escrever Novos Robôs

Ao gerar uma nova estratégia MICA, sempre seguir estas regras:

### Estrutura obrigatória

1. **Sempre declarar parâmetros** no bloco `Parametro` — nunca hardcodar valores no código
2. **Sempre declarar variáveis** com tipo explícito no bloco `var`
3. **Preservar estado entre candles** — variáveis de controle devem ter `variavel := variavel[1]` no início do `begin`
4. **Separar claramente** os blocos de: indicadores → filtros → gatilhos → gerenciamento → entradas
5. **Nunca colocar entradas antes do gerenciamento** — o gerenciamento de posição aberta deve ser processado primeiro

### Padrão de comentários

```pascal
// ── Nome do bloco ────────────────────────────────────────────
// Use comentários de bloco para separar seções
// Use comentários inline para explicar lógica não óbvia
```

### Boas práticas de código

```pascal
// ✅ CORRETO — verificar se não há posição antes de entrar
if (not IsBought) and (not IsSold) and CondicoesCompra then
  BuyAtMarket;

// ❌ ERRADO — entrar sem verificar posição existente
if CondicoesCompra then
  BuyAtMarket;

// ✅ CORRETO — sempre ter fallback a mercado
SellToCoverStop(MeuStop);
if (Fechamento <= MeuStop) then
  SellToCoverAtMarket;   // fallback se o candle fechou além do stop

// ✅ CORRETO — preservar estado corretamente
MinhaVar := MinhaVar[1];   // no início do begin, antes de qualquer lógica

// ❌ ERRADO — não preservar o estado (variável perde valor a cada candle)
// (ausência do MinhaVar := MinhaVar[1])
```

### Filtros recomendados para XAUUSD 4R

Ao escrever estratégias para XAUUSD no timeframe 4R, incluir por padrão:

```pascal
// 1. Filtro de horário (baseado em backtest real)
DentroJanela := not (
  (HoraAtual = 6)  or
  (HoraAtual = 13) or
  (HoraAtual = 14) or
  (HoraAtual = 21)
);

// 2. Filtro de tamanho de tijolo (evitar candles de ruído)
MediaTamanhoTijolo := Media(10, Abs(Fechamento - Abertura));
TijoloFiltrado     := TamanhoTijolo >= MediaTamanhoTijolo;

// 3. Filtro de confluência com Keltner (validar extensão do preço)
KeltnerMedio := Media(20, Fechamento);
KeltnerSup   := KeltnerMedio + (2.0 * MediaATR(20));
KeltnerInf   := KeltnerMedio - (2.0 * MediaATR(20));
```

### Parâmetros padrão testados para XAUUSD 4R

| Parâmetro | Valor testado | Observação |
|---|---|---|
| Stop | 0,25 × tijolo | Stop apertado — adequado para Renko |
| Take | 3,0 × tijolo | Relação risco/retorno 1:12 |
| Período RSI | 14 | Clássico |
| Nível venda RSI | 95 | Sobrecompra extrema |
| Nível compra RSI | 5 | Sobrevenda extrema |
| Período Keltner | 20 | EMA 20 |
| Multiplicador ATR | 2,0 | Bandas padrão |
| Média de tijolos | 10 | Filtro de ruído |

---

## 13. Checklist de Qualidade — Validação da IA

Antes de entregar qualquer código MICA gerado, verificar:

- [ ] Parâmetros declarados no bloco `Parametro`?
- [ ] Todas as variáveis declaradas com tipo no bloco `var`?
- [ ] Estado preservado com `var := var[1]` no início do `begin`?
- [ ] Verificação `(not IsBought) and (not IsSold)` antes de qualquer entrada?
- [ ] Gerenciamento de posição antes das entradas?
- [ ] `SellToCoverStop` / `BuyToCoverStop` configurados?
- [ ] Fallback `AtMarket` caso o candle feche além do stop?
- [ ] Filtro de horário incluído (para XAUUSD 4R)?
- [ ] Filtro de tamanho de tijolo incluído?
- [ ] Comentários de bloco separando as seções?
- [ ] Nenhum valor hardcoded que deveria ser parâmetro?
- [ ] Lógica de Long e Short simétricas e completas?

---

## 14. Exemplos de Gatilhos Comuns

### Cruzamento de médias

```pascal
// Golden cross / Death cross
GoldenCross := (EMA20[1] < EMA50[1]) and (EMA20 >= EMA50);
DeathCross  := (EMA20[1] > EMA50[1]) and (EMA20 <= EMA50);
```

### Price Action — rompimento de máxima/mínima

```pascal
// Rompe máxima dos últimos N candles
RompeMaxima := (Fechamento > Highest(Maxima, 20)[1]);

// Rompe mínima dos últimos N candles
RompeMInima := (Fechamento < Lowest(Minima, 20)[1]);
```

### Candle de reversão (engolfo)

```pascal
// Engolfo de alta: candle atual engole o anterior
EngolfoAlta  := (Abertura < Fechamento[1]) and (Fechamento > Abertura[1])
                and (Fechamento > Abertura);   // candle atual de alta

// Engolfo de baixa
EngolfoBaixa := (Abertura > Fechamento[1]) and (Fechamento < Abertura[1])
                and (Fechamento < Abertura);   // candle atual de baixa
```

### RSI com divergência simples

```pascal
// Preço faz nova mínima, RSI não confirma (divergência de alta)
DivergenciaAlta :=
  (Fechamento < Lowest(Fechamento, 5)[1]) and   // novo fundo no preço
  (RSI_Valor > Lowest(RSI_Valor, 5)[1]);         // RSI não faz novo fundo

// Preço faz nova máxima, RSI não confirma (divergência de baixa)
DivergenciaBaixa :=
  (Fechamento > Highest(Fechamento, 5)[1]) and  // novo topo no preço
  (RSI_Valor < Highest(RSI_Valor, 5)[1]);        // RSI não faz novo topo
```

### MACD cruzamento com histograma

```pascal
MACD_Linha := MACD(12, 26, 9);
MACD_Sinal := MACDSinal(12, 26, 9);
MACD_Histo := MACDHistograma(12, 26, 9);

// Cruzamento bullish: linha cruza acima do sinal
MACDCruzaBull := (MACD_Linha[1] < MACD_Sinal[1]) and (MACD_Linha >= MACD_Sinal);

// Histograma mudando de negativo para positivo
MACDHist_Bull := (MACD_Histo[1] < 0) and (MACD_Histo >= 0);
```

---

## 15. Template de Nova Estratégia

Use este template como ponto de partida para qualquer nova estratégia:

```pascal
{ ============================================================
  Nome da Estratégia
  Ativo: XAUUSD | Timeframe: 4R
  Lógica: [descrever aqui]
  Autor: [nome]
  Data: [data]
  ============================================================ }

Parametro
  Stop(0.25);
  Take(3.0);
  AtivarGerenciamento(True);
  // adicionar parâmetros específicos da lógica aqui

var
  TamanhoTijolo                        : real;
  CondicoesCompra, CondicoesVenda      : boolean;
  HoraAtual                            : integer;
  DentroJanela                         : boolean;
  KeltnerMedio, KeltnerSup, KeltnerInf : real;
  MediaTamanhoTijolo                   : real;
  TijoloFiltrado                       : boolean;
  TendenciaEMA                         : integer;
  PrecoEntradaLong, PrecoEntradaShort  : real;
  MaiorStopLong, MaiorStopShort        : real;
  // declarar variáveis específicas da lógica aqui

begin
  { ── Preservar estado ──────────────────────────────────────── }
  PrecoEntradaLong  := PrecoEntradaLong[1];
  PrecoEntradaShort := PrecoEntradaShort[1];
  MaiorStopLong     := MaiorStopLong[1];
  MaiorStopShort    := MaiorStopShort[1];

  { ── Indicadores base ──────────────────────────────────────── }
  TamanhoTijolo      := Abs(Fechamento - Abertura);
  MediaTamanhoTijolo := Media(10, TamanhoTijolo);
  TijoloFiltrado     := TamanhoTijolo >= MediaTamanhoTijolo;

  KeltnerMedio := Media(20, Fechamento);
  KeltnerSup   := KeltnerMedio + (2.0 * MediaATR(20));
  KeltnerInf   := KeltnerMedio - (2.0 * MediaATR(20));

  if KeltnerMedio > KeltnerMedio[3] then TendenciaEMA := 1
  else if KeltnerMedio < KeltnerMedio[3] then TendenciaEMA := -1
  else TendenciaEMA := 0;

  { ── Filtro de horário ─────────────────────────────────────── }
  HoraAtual := Hour(Now);
  DentroJanela := not (
    (HoraAtual = 6)  or
    (HoraAtual = 13) or
    (HoraAtual = 14) or
    (HoraAtual = 21)
  );

  { ── Indicadores específicos da estratégia ─────────────────── }
  // adicionar aqui

  { ── Condições de entrada ──────────────────────────────────── }
  CondicoesCompra := DentroJanela and TijoloFiltrado; // adicionar mais condições
  CondicoesVenda  := DentroJanela and TijoloFiltrado; // adicionar mais condições

  { ── Visualização ──────────────────────────────────────────── }
  // PaintBar, PlotText, Plot aqui

  { ── Gerenciamento LONG ────────────────────────────────────── }
  if (IsBought and AtivarGerenciamento) then
  begin
    if (IsBought[1] = false) then
    begin
      PrecoEntradaLong := Price;
      MaiorStopLong    := Price - (TamanhoTijolo * Stop);
    end;

    if (Price - (TamanhoTijolo * Stop)) > MaiorStopLong then
      MaiorStopLong := Price - (TamanhoTijolo * Stop);

    SellToCoverStop(MaiorStopLong);
    SellToCoverLimit(Price + (TamanhoTijolo * Take));

    if (Fechamento <= MaiorStopLong) then
      SellToCoverAtMarket;
  end

  { ── Gerenciamento SHORT ───────────────────────────────────── }
  else if (IsSold and AtivarGerenciamento) then
  begin
    if (IsSold[1] = false) then
    begin
      PrecoEntradaShort := Price;
      MaiorStopShort    := Price + (TamanhoTijolo * Stop);
    end;

    if (Price + (TamanhoTijolo * Stop)) < MaiorStopShort then
      MaiorStopShort := Price + (TamanhoTijolo * Stop);

    BuyToCoverStop(MaiorStopShort);
    BuyToCoverLimit(Price - (TamanhoTijolo * Take));

    if (Fechamento >= MaiorStopShort) then
      BuyToCoverAtMarket;
  end;

  { ── Entradas ──────────────────────────────────────────────── }
  if (not IsBought) and (not IsSold) and CondicoesCompra then
    BuyAtMarket;

  if (not IsBought) and (not IsSold) and CondicoesVenda then
    SellShortAtMarket;
end;
```

---

*Documento gerado com base em estratégia real testada em XAUUSD 4R — dez/2025 a mar/2026 — 1.101 operações.*