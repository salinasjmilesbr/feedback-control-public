# F6-01 — Preparação e roteiro da auditoria visual/funcional

> **Status:** roteiro fechado para iniciar a auditoria READ-ONLY no localhost.
> **Base auditada:** `main` em `961ef1f`.
> **Escopo:** inventário de telas, jornadas e perfis realmente presentes; não é
> correção, refatoração, redesign ou proposta de arquitetura.

## 1. Invariantes da auditoria

- Inspecionar e operar o produto somente em modo READ-ONLY: não editar código,
  não corrigir dados e não transformar achado diretamente em trabalho.
- Preservar a massa **LEGACY** existente e manter a massa **GREENFIELD F6**
  isolada. Se dado LEGACY aparecer no contexto GREENFIELD, registrar o sintoma
  como possível falha de isolamento; não limpar para fazer o roteiro passar.
- Classificar cada achado exclusivamente como `QUEBRADO`, `REGRESSÃO` ou
  `MELHORIA`.
- Consolidar sintomas que compartilham causa antes de propor qualquer lote.

## 2. Inventário auditável da `main`

Fonte primária das rotas: `src/routes/AppRoutes.tsx`. A autenticação e o shell
funcional passam por `LayoutAutenticado` e `LayoutFuncional`; a navegação é
apresentação e não substitui autorização server-side.

### 2.1 Telas públicas e sessão

| Rota | Tela/jornada | Evidência |
|---|---|---|
| `/login` | entrada e autenticação | `src/routes/AppRoutes.tsx` |
| `/recuperar-senha` | solicitação de recuperação | `src/routes/AppRoutes.tsx` |
| `/redefinir-senha` | redefinição de senha | `src/routes/AppRoutes.tsx` |
| shell autenticado | bootstrap, seleção/ausência de organização, sessão indisponível e expirada | `src/auth/rotasProtegidas.ts`, `src/auth/LayoutAutenticado.tsx` |

### 2.2 Início, identidade e organização

| Rota | Tela/jornada | Evidência |
|---|---|---|
| `/` | início, resumo e entradas para jornadas de equipe | `src/routes/AppRoutes.tsx`, `src/pages/InicioPage.tsx` |
| `/convidar-usuario` | convite administrativo | `src/auth/ConvidarUsuarioPage.tsx` |
| `/colaboradores/novo` | criação de colaborador | `src/pages/NovoColaboradorPage.tsx` |
| `/colaborador/:collaboratorId` | detalhe de colaborador | `src/pages/ColaboradorDetalhePage.tsx` |
| `/colaborador/:collaboratorId/editar` | edição de colaborador | `src/pages/EditarColaboradorPage.tsx` |
| `/configuracoes/aparencia` | preferências visuais | `src/pages/ConfiguracoesAparenciaPage.tsx` |

### 2.3 Estrutura e catálogos

| Rota | Tela/jornada | Evidência |
|---|---|---|
| `/unidades` | unidades organizacionais | `src/pages/UnidadesPage.tsx` |
| `/posicoes` | posições e reporting line | `src/pages/PosicoesPage.tsx` |
| `/colegiado` | configuração colegiada | `src/pages/ColegiadoPage.tsx` |
| `/catalogos` | catálogos de estrutura | `src/pages/CatalogosPage.tsx` |

### 2.4 Avaliações e ciclos

| Rota | Tela/jornada | Evidência |
|---|---|---|
| `/minha-avaliacao` | lista de avaliações próprias | `src/pages/MinhaAvaliacaoPage.tsx` |
| `/minha-avaliacao/:feedbackId` | detalhe/transparência da avaliação própria | `src/pages/MinhaAvaliacaoDetalhePage.tsx` |
| `/ciclos` | listagem e gestão de ciclos | `src/pages/CiclosAvaliacaoPage.tsx` |
| `/ciclos/:cicloId` | painel do ciclo | `src/pages/PainelCicloPage.tsx` |
| `/painel-ciclos` | painel de ciclos do coordenador | `src/pages/PainelCiclosCoordenadorPage.tsx` |
| `/colaborador/:id/novo-feedback` | criação de avaliação por colaborador | `src/pages/NovoFeedbackPage.tsx` |
| `/colaborador/:id/feedback/:feedbackId` | detalhe de avaliação | `src/pages/FeedbackDetalhePage.tsx` |
| `/colaborador/:id/feedback/:feedbackId/editar` | edição de avaliação | `src/pages/EditarFeedbackPage.tsx` |

### 2.5 Metas, observações e relatórios

| Rota | Tela/jornada | Evidência |
|---|---|---|
| `/minhas-metas` | metas próprias | `src/pages/MinhasMetasPage.tsx` |
| `/ciclos/:cicloId/colaborador/:id/metas` | acompanhamento de metas de colaborador | `src/pages/AcompanhamentoMetasPage.tsx` |
| observações em telas de colaborador/avaliação | leitura e operações de observação conforme o fluxo da tela | `src/components/ObservacoesColaborador.tsx`, `src/pages/observacoesSoberanasDaPagina.ts` |
| `/relatorios` | relatórios e histórico | `src/pages/RelatoriosPage.tsx` |

As observações não possuem rota própria no roteador atual; devem ser auditadas
nos pontos de integração realmente renderizados.

### 2.6 Perfis e estados observáveis

O código declara fluxos próprios para `COORDENADOR`, `CONSULTOR`, `ANALISTA` e
`ESTAGIARIO` em `src/authorization/perfisOperacionaisAtuais.ts`. A auditoria
deve distinguir esse campo funcional dos acessos administrativos efetivos,
resolvidos por capabilities, scopes, membership e estado do perfil; não criar
personas não presentes no produto.

Executar, quando disponível na massa de teste, pelo menos estes estados:

1. usuário não autenticado;
2. usuário autenticado sem organização ativa;
3. usuário com seleção pendente entre organizações;
4. usuário com perfil/membership ativos e fluxos próprios;
5. usuário com capability administrativa efetiva;
6. usuário com capability ausente/revogada ou estado inativo.

## 3. Ordem prática no localhost

1. Registrar commit, ambiente, navegador, viewport, banco e identidade de teste.
2. Abrir `/login` e verificar bootstrap, recuperação e redefinição sem alterar
   credenciais ou dados.
3. Exercitar os estados de sessão acima, incluindo ausência/seleção de
   organização e bloqueios fail-closed.
4. Percorrer a navegação visível e as rotas diretamente, anotando divergências
   entre link, rota e resposta efetiva — sem considerar ocultação de UI como
   autorização.
5. Percorrer a jornada GREENFIELD na ordem: organização/identidade → estrutura
   e catálogos → colaborador → ciclo → avaliação → metas → observações →
   relatórios.
6. Repetir as leituras equivalentes no contexto LEGACY, preservando seus dados;
   comparar apenas comportamento observável contratado, sem exigir que LEGACY
   tenha o mesmo cutover dos domínios já soberanos.
7. Repetir pontos sensíveis após refresh, troca de organização, logout/login,
   revogação/inativação preparada no ambiente e acesso direto por URL.
8. Fechar cada jornada com evidência mínima e consolidar causas somente depois
   de concluir o percurso finito.

## 4. Estratégia LEGACY × GREENFIELD

| Contexto | Preparação | Regra de isolamento |
|---|---|---|
| LEGACY | usar a massa existente, sem reset destrutivo ou limpeza de `localStorage` | preservar compatibilidade dos consumidores legados ainda contratados |
| GREENFIELD F6 | organização de teste separada, construída progressivamente pelos fluxos reais | nenhum dado, usuário, ciclo ou colaborador LEGACY deve aparecer; se aparecer, registrar como achado potencial |

Não misturar identidade, organização ativa, origem de dados ou URLs entre os
contextos. Registrar IDs técnicos fictícios apenas no artefato privado de
execução, nunca em código ou documentação versionada.

## 5. Evidência e registro de achados

Cada jornada deve produzir, no mínimo: contexto (`LEGACY`/`GREENFIELD`), perfil
e estado, pré-condições, rota, passos, resultado esperado, resultado observado,
timestamp/viewport, evidência visual ou textual, commit auditado e classificação.

Formato do registro:

```text
ID: F6-01-###
Contexto: LEGACY | GREENFIELD
Perfil/estado: [somente perfil existente + estado observado]
Jornada/rota: [item do inventário]
Pré-condições: ...
Passos: 1. ... 2. ...
Esperado: ...
Observado: ...
Evidência: screenshot/log/URL/arquivo:linha
Classificação: QUEBRADO | REGRESSÃO | MELHORIA
Sintoma relacionado: ...
Causa consolidada: [preencher somente após comparação]
Impacto: ...
Proposta de lote: [somente após consolidação; não é Issue automática]
```

`QUEBRADO` indica falha funcional concreta no comportamento esperado; `REGRESSÃO`
indica quebra de comportamento anteriormente válido; `MELHORIA` indica mudança
opcional sem falha contratual. Achados de segurança, isolamento ou perda de
dados devem conservar a evidência de condição de reprodução e impacto concreto.

## 6. Próximos lotes READ-ONLY da F6

Os lotes abaixo são sequenciais e ajustáveis ao inventário real; não fixam
quantidade artificial de atividades nem autorizam correção nesta fase:

1. **Lote F6-A — acesso e shell:** sessão, organização ativa, navegação,
   rotas diretas, refresh/logout e estados fail-closed.
2. **Lote F6-B — GREENFIELD estrutural:** organização de teste, estrutura,
   catálogos, colaborador e transições observáveis.
3. **Lote F6-C — GREENFIELD de ciclo a avaliação:** ciclo, painel, criação,
   leitura, edição e transparência da avaliação.
4. **Lote F6-D — metas e observações:** metas próprias/gestão, observações nos
   pontos de integração e lifecycle de comunicação/revogação observável.
5. **Lote F6-E — LEGACY e comparação:** jornadas legadas preservadas,
   compatibilidade contratada e detecção de vazamento LEGACY/GREENFIELD.
6. **Lote F6-F — consolidação transversal:** agrupar sintomas por causa,
   classificar achados e produzir uma fila priorizada de decisões/lotes futuros.

Um lote só deve virar trabalho posterior quando a consolidação demonstrar uma
causa material ou uma decisão de produto necessária. Melhorias cosméticas sem
falha contratual permanecem classificadas como `MELHORIA`, sem correção
automática.

## 7. Autoauditoria F6-01

- [x] Documento baseado nas rotas, páginas e perfis presentes na `main`.
- [x] Nenhuma tela, perfil ou jornada foi inventado além dos pontos de
  integração explicitamente identificados.
- [x] LEGACY e GREENFIELD permanecem separados e o aparecimento de dados
  cruzados é tratado como achado, não como limpeza.
- [x] O roteiro é finito, ordenado, READ-ONLY e rastreável.
- [x] As classificações estão limitadas a `QUEBRADO`, `REGRESSÃO` e
  `MELHORIA`.
- [x] Os lotes seguintes derivam do inventário e não criam quantidade artificial
  de atividades.
- [x] Nenhum código funcional, arquitetura, roadmap, dívida ou Issue foi
  alterado/criado nesta atividade.

**Dúvidas/bloqueios para iniciar a auditoria:** o ambiente precisa fornecer as
identidades fictícias, organizações separadas e uma forma segura de observar o
estado LEGACY sem apagá-lo. A confirmação do comportamento visual exige
execução posterior no localhost; este documento não afirma resultados de
auditoria que ainda não foram observados.
