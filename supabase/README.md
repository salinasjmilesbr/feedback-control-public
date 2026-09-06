# Supabase local — F1-01

Estrutura inicial gerada com `npx --yes supabase@2.116.0 init`. A configuração
foi reduzida aos serviços locais necessários: PostgreSQL 17, API e Studio.
Auth, Realtime, Storage, SMTP, Edge Runtime, Analytics e seed estão desabilitados.
Não há migrations ou seed funcionais. Os arquivos SQL serão criados pelas etapas
posteriores (F1-03 em diante); o diretório migrations/ contém apenas a
documentação de convenções (F1-02) e esta versão da CLI gera somente config.toml
e .gitignore. As convenções estão em [migrations/README.md](migrations/README.md).

## Pré-requisitos

- Node.js 20 ou superior para executar a CLI por npm/npx; use Node 24 LTS para
  manter compatibilidade com o React/Vite e o CI deste repositório.
- npm/npx disponível e acesso à internet para obter a CLI e as imagens oficiais.
- Docker Desktop instalado e em execução, com containers Linux (no Windows,
  configure o backend WSL 2 conforme os requisitos do Docker Desktop), ou runtime
  com API Docker compatível suportado pela CLI.
- Portas locais 54321 (API), 54322 (PostgreSQL) e 54323 (Studio) disponíveis.
  A configuração reserva 54320 para o banco temporário de diff em etapas futuras.

A CLI é fixada em **2.116.0** em todos os comandos. O npx usa seu cache de
ferramentas; não adiciona a CLI ou o cliente Supabase ao package.json/lockfile
da aplicação. Não é necessária instalação global nem conta/projeto remoto.

## Iniciar e parar

Execute na raiz do repositório, com Docker iniciado. Em um clone existente,
não execute init novamente: a configuração já está versionada.

```sh
docker version
npx --yes supabase@2.116.0 --version
npx --yes supabase@2.116.0 start
npx --yes supabase@2.116.0 status
```

O primeiro start baixa imagens e pode demorar. Após sucesso, confira o status e
abra o Studio em http://127.0.0.1:54323. A API fica em http://127.0.0.1:54321.
São serviços de desenvolvimento local; não publique essas portas na internet.
O PostgreSQL pode conter schemas internos da distribuição Supabase; isso não
representa criação de tabelas do domínio Virtus ou implementação de Auth/RLS.

Para parar sem solicitar descarte dos dados locais:

```sh
npx --yes supabase@2.116.0 stop
```

Não use login, link, db push, deploy ou integração GitHub ↔ Supabase nesta etapa.
Não há vínculo com virtus-team-dev. O project_id é apenas um identificador local
para distinguir containers, não uma referência a projeto hospedado.

## Aplicação independente

O frontend continua iniciando com `npm run dev`, mesmo sem Docker ou Supabase.
localStorage permanece a única persistência funcional. Não há alteração de
adapters, configuração de URL da aplicação, autenticação, UI ou regras de negócio.
Não é necessário preencher VITE_PUBLIC_API_URL para usar esta infraestrutura.

## Arquivos seguros

Versione somente configuração pública e documentação. .branches e .temp são
ignorados pela configuração oficial, assim como arquivos locais de ambiente.
Nunca copie saída de status, credenciais geradas, tokens, senhas ou arquivos de
chaves para commits, exemplos ou PRs. Nenhuma credencial real é necessária aqui.
Não habilite provedores externos ou adicione segredos a variáveis VITE_*.

## Validação desta entrega

- CLI 2.116.0 executada via npx; init oficial concluído.
- TOML verificado estruturalmente e aceito pela leitura inicial da CLI.
- start foi tentado e retornou LegacyDockerLifecycleInspectError:
  `docker: command not found (podman also not found)`.
- O ambiente do agente não possui Docker/Podman disponível. Containers não
  foram iniciados; download das imagens, saúde dos serviços, conectividade
  PostgreSQL/API/Studio e ciclo start/status/stop não foram validados em runtime.
- Para completar essa validação, execute os comandos acima em uma máquina com
  runtime compatível e confirme os serviços antes de avançar para F1-02.

Essa limitação não é uma aprovação do runtime: validação estrutural e testes da
aplicação não substituem a subida real da infraestrutura.

Referências: [CLI oficial](https://supabase.com/docs/guides/local-development/cli/getting-started),
[configuração](https://supabase.com/docs/guides/local-development/cli/config) e
[Docker Desktop no Windows](https://docs.docker.com/desktop/setup/install/windows-install/).
