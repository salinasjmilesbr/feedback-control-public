# Instruções permanentes para agentes

## Projeto

Este repositório contém o Vivo Virtus (`feedback-control`), uma aplicação de gestão de avaliações, observações, metas e estrutura organizacional.

A stack principal é:

- React;
- TypeScript;
- Vite;
- React Router;
- Vitest;
- ESLint;
- jsPDF.

O GitHub é a fonte de verdade para Issues, requisitos, histórico de mudanças e Pull Requests. Antes de implementar uma Issue, leia integralmente seu escopo, critérios de aceite e itens explicitamente fora do escopo.

## Regras de implementação

- Preserve a compatibilidade com dados antigos persistidos em `localStorage`.
- Não inclua dados pessoais ou corporativos reais em código, fixtures, testes, documentação, commits ou Pull Requests. Use somente dados fictícios.
- Preserve os históricos e trilhas de auditoria de avaliações, observações, metas e estrutura organizacional.
- Não duplique regras de autorização em páginas ou componentes. Use a policy e as capabilities centrais existentes em `src/authorization`.
- Preserve a separação entre autorização, workflow, cálculos, persistência e auditoria.
- Não trate ocultação de elementos na interface como autorização efetiva de uma operação.
- Exiba notas sempre com uma casa decimal, reutilizando os formatadores existentes quando aplicável.
- Evite alterações fora do escopo solicitado, refactors oportunistas e mudanças de comportamento não requeridas.
- Preserve regras de negócio existentes, salvo quando uma mudança estiver explicitamente descrita e aprovada na Issue.
- Prefira APIs públicas e padrões já adotados pelo projeto.

## Qualidade e validação

Antes de concluir uma alteração, execute e registre no Pull Request:

```bash
npm test
npm run build
npm run lint
git diff --check
```

- Todos os comandos devem passar antes da entrega.
- Se uma validação não puder ser executada ou falhar por motivo externo ao escopo, registre claramente o comando, o resultado e a limitação no Pull Request.
- Adicione ou atualize testes proporcionais ao risco da mudança, preservando os testes de caracterização existentes.
- Revise `git status --short` e o diff final para garantir que somente arquivos previstos estejam incluídos.

## Fluxo GitHub

- Trabalhe em uma branch específica para a Issue.
- Use commits objetivos e compatíveis com o padrão do histórico do repositório.
- Abra um Pull Request usando `.github/pull_request_template.md`.
- Referencie a Issue com `Closes #<número>` na descrição do Pull Request quando a entrega resolver integralmente seu escopo.
- Não faça merge do Pull Request sem solicitação explícita.
