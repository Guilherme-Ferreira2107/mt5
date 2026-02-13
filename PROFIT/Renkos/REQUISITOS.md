# Correção de sintaxe (Renko 3-1-1) — guia rápido + código ajustado

Você já está bem perto. Os erros que você recebeu indicam **dois problemas clássicos**:

## 1) Erro: “Função ou variável inválida: Maximo”
Isso significa que, **na sua linguagem/plataforma**, `Maximo` **não existe** com esse nome.

Em plataformas de trading, o “máximo/mínimo da barra” costuma variar, por exemplo:
- `Maxima` / `Minima`
- `High` / `Low`
- `Maximo` / `Minimo` (em algumas, mas não na sua)

✅ **Como resolver**
- Troque `Maximo` e `Minimo` pelos identificadores corretos da sua plataforma.
- Se você não souber os nomes corretos, procure na lista de “séries de preço” (Open/High/Low/Close).

> No código abaixo eu deixei uma versão usando **Maxima/Minima** (bem comum).  
> Se no seu caso for `High/Low`, é só substituir.

---

## 2) Erro: “Não é possível começar um statement com SENAO”
Em sintaxe estilo Pascal, **não pode existir `;` antes do `Senao`**.

No seu código original você tem:

```pascal
Se PadraoAlta ou PadraoBaixa entao
    PaintBar(clAmarelo);
Senao Se Pavio entao
    PaintBar(clVermelho);