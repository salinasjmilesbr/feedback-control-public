# Issue #373 — evidência de upgrade incremental

Validação executada no Supabase local ativo, sem `db reset`:

- estado inicial: último migration `20261012000000`;
- comando: `npx --yes supabase@2.116.0 migration up --local`;
- resultado: aplicadas `20261013000000` e `20261014000000` até o head;
- sentinela antes/depois: `public.organizations` = 1 registro,
  fingerprint `11c548a797ef9ec0f9703163666cd6bf` em ambos os lados;
- `pg_get_functiondef()` consultado após a aplicação e confirmou a RPC
  transformada com normalização UTC e guarda temporal após o advisory lock;
- Acme/runtime compartilhado não foi acessado nem alterado.

O teste estático permanece complementar: a prova de SQL executável é a
execução real acima, não a inspeção textual do arquivo.
