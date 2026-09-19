# Virtus — Matriz de Aceite Visual v1.0

> Issue #312. Nenhuma tela avança apenas porque build/testes passaram. O aceite visual é explícito.

## Gate por componente/tela
Validar em **desktop e mobile** antes de avançar.

| Critério | Aceite |
|---|---|
| Asset | usa o V oficial; nenhuma reconstrução/aproximação |
| Marca | VIRTUS + tagline quando prevista; sem branding de tenant em público/plataforma |
| Paleta | somente tokens aprovados |
| Verde | somente estado de sucesso |
| CTA primário | destaque azul/violeta |
| Tipografia | Inter e hierarquia coerente; título administrativo sem escala de landing page |
| Header | simples; VIRTUS · contexto; saída; sem complexidade fictícia |
| Footer | VIRTUS · Performance & Feedback Management · versão |
| Texto | linguagem direta/profissional/humana; sem jargão técnico desnecessário |
| Espaçamento | legível, consistente e sem colisões |
| Responsividade | reorganiza sem criar outra linguagem visual |
| Segurança | nenhuma mudança visual concede autoridade ou enfraquece gates |
| Escopo | sem menus/features fictícios ou refatoração oportunista |

## Sequência de aceite
1. **Assets/tokens**
2. **Header + Footer**
3. **Login**
4. **Gestão Virtus**
5. **Nova empresa**

Cada item exige:
- implementação isolada;
- testes direcionados/build/lint proporcionais ao escopo;
- captura/validação visual desktop;
- captura/validação visual mobile;
- correção antes do próximo item.

## Reprovação automática
- V diferente do asset oficial;
- verde em CTA, link institucional, navegação ou branding;
- branding de empresa em login/`/plataforma/*`;
- título administrativo excessivamente grande;
- footer/header quebrado ou com conteúdo colidindo;
- criação de menu/avatar/hambúrguer sem necessidade funcional;
- texto “Admin Virtus” na UX onde o contrato exige **Gestão Virtus**;
- reintrodução de “Sessão de plataforma”;
- agente inventar novo padrão visual para preencher lacuna.

## Evidência
A validação automatizada não substitui a inspeção visual. Screenshot/runtime é evidência de UX; testes são evidência complementar de regressão estrutural.
