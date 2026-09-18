# Etapa 6 — Registro incremental de findings

> Registro canônico da auditoria visual/funcional runtime da Etapa 6.
> Um finding registrado aqui não autoriza correção automática. Antes de virar trabalho, deve ser classificado conforme a governança do Plano Mestre.
> Issue de rastreabilidade: #293.

## Findings consolidados antes do registro incremental

| ID | Classificação atual | Finding | Evidência/observação |
|---|---|---|---|
| F6-A01 | MELHORIA | Espaçamento vertical insuficiente em estado restrito. | Finding anterior da F6. |
| F6-A02 | MELHORIA | `Tentar novamente` sem efeito perceptível útil quando nenhuma organização é resolvida. | Finding anterior da F6. |
| F6-A06 | MELHORIA | Estado autenticado sem tenant usa mensagem de “Acesso negado”, semanticamente inadequada. | Finding anterior da F6. |
| F6-A10 | MELHORIA | UX das telas de entrada/autenticação e seleção de organização precisa revisão de layout, hierarquia e linguagem. | Consolida também header/footer, CTA de criar organização e equilíbrio visual. |
| F6-A15 | MELHORIA | Revisão transversal de linguagem e apresentação para termos de gestão/RH, removendo jargão técnico e detalhes internos. | Detalhamento incremental abaixo. |
| F6-A16 | MELHORIA FUNCIONAL | Bootstrap do primeiro Admin deve capturar data de admissão e persistir no histórico. | Não altera D23 sem decisão formal. |
| F6-A18 | BACKLOG / MELHORIA | Administração segura de organizações pelo Admin Virtus, incluindo exclusão fortemente confirmada e auditável. | Backlog; não é blocker da auditoria. |
| F6-EDGE-AVALIACOES | DEFEITO PENDENTE, SEPARADO | Edge `avaliacoes` retorna 503/`BOOT_ERROR` por bare specifier em `assignedSupabase.ts`. | Não confundir com DT-013. |

## F6-A15 — linguagem e apresentação

Achados observados até 18/09/2026:

- Home/Colaboradores expõe linguagem técnica como “cadastro soberano”, PostgreSQL, “ocupação vigente” e explicações de persistência.
- Ficha/edição de colaborador expõe termos como “versão da projeção”, UUID/identificador funcional, “cadastro soberano”, PostgreSQL, “operações soberanas”, “ocupação soberana”, “reporting line”, “controle otimista”, “leitura soberana”, “trilha soberana append-only”, legado/arquivo e linguagem excessivamente técnica de vigência. Também há `Status: active` em inglês no histórico.
- Unidades expõe “entidade formal com vigência própria”, “relação pai/filho é temporal”, “não admite ciclo”, “versão 0”, “relação pai registrada” e “decisão D21”.
- Fluxo Definir/Alterar unidade pai expõe UUID como `identidade <uuid>`.
- Posições expõe “IMUTÁVEIS”, “D5”, “I4”, “reporting line”, “recusado pelo servidor”, “versão 0” e UUID/`identidade`.
- Catálogos expõe “RÓTULOS”, UUID, “code imutável por contrato”, “verificadas no servidor” e “versão 0”.
- Código do cargo é exibido de forma redundante junto ao nome em seletores/cards, por exemplo `GER-VENDAS — Gerente de Vendas`. Para superfícies operacionais, o nome `Gerente de Vendas` é suficiente; o código pode permanecer onde tiver função administrativa/integracional.

## Findings de UX observados durante a estrutura ORG5

### F6-UX-01 — campos de texto estreitos em Unidades
**Classificação:** MELHORIA.

No desktop, especialmente `Nome da unidade` e `Motivo` usam pouco do espaço horizontal disponível, dificultando visualizar o texto digitado. Rever largura/distribuição do formulário sem prejudicar mobile.

### F6-UX-02 — estado vazio de estrutura semanticamente incorreto
**Classificação:** MELHORIA / UX.

Após criar `Diretoria Comercial` e `Gerência de Vendas`, telas como Posições e Catálogos continuaram exibindo:

> “Sem estrutura cadastrada: nenhuma unidade, posição, cargo ou senioridade foi registrada nesta organização.”

Os seletores de Posições reconhecem corretamente as duas unidades, portanto não há evidência de falha de persistência. O problema é a condição/texto do estado vazio.

## Evidência funcional da estrutura ORG5 até este checkpoint

- F6-A17: navegação do Admin apareceu no runtime após #290; RESOLVIDA + VALIDADA.
- Unidades: criação de `Diretoria Comercial` e `Gerência de Vendas` funcionou.
- Hierarquia de unidades: `Gerência de Vendas → Diretoria Comercial` funcionou.
- Catálogos: cargo `Gerente de Vendas`, código `GER-VENDAS`, criado com sucesso.
- Posições: posição `Gerência de Vendas + Gerente de Vendas`, sem senioridade, criada com sucesso e exibida como sem ocupante.
- Fluxo de alocação foi descoberto pela própria UI: `Ver histórico → Administrar alocação` abre `Editar colaborador`, seção `04 Alocação`.
- A tela de edição oferece `Posição vigente`, vigência e motivo para `Definir ocupação`; a posição criada apareceu no seletor e James Salinas foi alocado com sucesso em `Gerência de Vendas / Gerente de Vendas`.
- Após a alocação, a seção passa a mostrar a ocupação vigente e ações `Trocar posição`, `Encerrar ocupação` e `Definir gestor`. Como só existe uma posição vigente, os seletores de nova posição/gestor ficam sem alternativas; isso é coerente com os dados atuais.
- A apresentação pós-alocação reforça F6-A15 ao expor `GER-VENDAS` junto ao cargo, UUID da posição, `reporting line`, `posição raiz` e texto técnico sobre duas operações soberanas/ausência de transação única no cliente.

## Regra de manutenção

Durante a Etapa 6, novos achados relevantes devem ser acrescentados a este arquivo antes de depender de consolidação futura. Duplicidades devem ser absorvidas por findings transversais existentes (especialmente F6-A15) em vez de criar IDs desnecessários.
