# Ambiente do frontend

`ambiente.ts` é o único leitor de `import.meta.env`. Consumidores usam
`configuracaoAmbiente`, sem acessar as variáveis do Vite diretamente.

| VITE_APP_ENV | Resultado |
| --- | --- |
| ausente/vazio | development se DEV=true e PROD=false; production nos demais casos |
| development | exige DEV=true e PROD=false; caso contrário, erro explícito |
| homologation | homologation, com reset desabilitado mesmo no servidor DEV |
| production | production, com reset desabilitado mesmo no servidor DEV |
| outro valor | erro explícito, sem fallback para DEV |

Copie `.env.example` para `.env.local` se precisar configurar um ambiente.
Para homologação, use `VITE_APP_ENV=homologation` ao iniciar ou gerar o build.
O nome do modo (`--mode`) sozinho não seleciona o ambiente da aplicação.
Sem configuração adicional, `npm run dev` e `npm run build` mantêm seus padrões.
As variáveis são resolvidas ao iniciar o Vite/gerar o bundle, não por um serviço
de configuração remoto. Alterações exigem reinício/rebuild.

O gate `resetDesenvolvimentoPermitido` exige contexto DEV do Vite e ambiente
development. Bootstrap e função de reset continuam protegidos pela mesma decisão.
Versão, chaves e comportamento do reset em DEV não mudam.

`VITE_PUBLIC_API_URL` reserva uma configuração pública opcional, sem fornecedor
ou integração ativa. Quando preenchida, deve ser uma URL HTTP(S) absoluta sem
credenciais. Um futuro consumidor deve chamar `exigirUrlApiPublica` apenas quando
sua operação exigir a URL; a ausência então gera erro com o nome da variável e
o ambiente. Nenhuma operação atual a exige, inclusive em HOMOLOG/PROD.

Tudo que usa `VITE_*` é público no frontend. Não coloque senhas, tokens privados,
credenciais em URLs ou outros segredos nesses campos. Segredos server-side
pertencerão exclusivamente à infraestrutura de servidor futura e não devem ser
adicionados a este módulo nem ao arquivo exemplo. Nenhuma infraestrutura de
ambientes ou integração externa é implementada nesta etapa.
