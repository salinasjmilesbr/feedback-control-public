# Virtus — Brand Guide e Contrato Visual v1.0

> Issue #312. Documento normativo para identidade visual e linguagem de produto.
> Em conflito: **asset oficial aprovado → guidelines visuais aprovados → este contrato → implementação existente**.

## 1. Marca
- Nome: **VIRTUS**
- Tagline: **Performance & Feedback Management**
- Símbolo: **V oficial aprovado pelo orquestrador**.
- O asset oficial é soberano: agentes não podem redesenhar, aproximar, reinterpretar, distorcer, rotacionar, recolorir, remover/adicionar efeitos ou reconstruir a marca em CSS/texto/SVG aproximado.
- A aplicação deve consumir o asset oficial versionado.

## 2. Paleta

| Papel | Cor | Uso |
|---|---|---|
| Primário | `#0F172A` | texto principal, confiança, estabilidade |
| Destaque | `#6366F1` | CTA primário, seleção, foco |
| Apoio | `#0EA5E9` | apoio da identidade |
| Superfície | `#F1F5F9` | superfícies secundárias |
| Fundo | `#FFFFFF` | fundo principal |
| Borda | `#E2E8F0` | bordas/divisores |
| Sucesso | `#10B981` | sucesso somente |
| Atenção | `#F59E0B` | atenção |
| Erro | `#EF4444` | erro/destrutivo |
| Informação | `#64748B` | informação secundária |

**Regra vinculante:** verde é exclusivamente semântico de sucesso. Nunca é branding, CTA primário, navegação ou link institucional.

## 3. Tipografia e voz
- Fonte: **Inter**.
- Título de página desktop: referência de **32 px**, sem hero headings desproporcionais em telas administrativas.
- Tom: **direto, profissional, humano e orientado a resultados**.
- Preferir linguagem de produto; evitar jargão técnico como tenant, bootstrap, policy e sessão de plataforma quando houver equivalente natural.

## 4. Nomenclatura
- Na UX, **Gestão Virtus** substitui “Admin Virtus”.
- A mudança é somente de produto/UX; roles, capabilities e autorização internas permanecem inalteradas.
- Títulos e ações preferenciais: **Administração**, **Nova empresa**, **Administrador inicial**, **Criar empresa**.

## 5. Contextos de branding
### Virtus puro
Login, recuperação de acesso e `/plataforma/*` usam exclusivamente a identidade Virtus.

### Empresa/tenant
Personalização de cliente somente dentro do contexto autorizado da empresa.

**Branding de cliente nunca pode vazar para login ou Gestão Virtus.**

## 6. Header
Direção aprovada: simples, na mesma linguagem do footer.

Gestão Virtus:
`[V oficial] VIRTUS · Gestão Virtus                         Sair`

Contexto de empresa:
`[V oficial] VIRTUS · [empresa]                    [usuário] · Sair`

- fundo branco;
- borda discreta `#E2E8F0`;
- identidade navy/azul-violeta;
- sem verde institucional;
- sem avatar, menu ou navegação complexa sem necessidade funcional real.

## 7. Footer
Referência aprovada:
`[V oficial] VIRTUS · Performance & Feedback Management        Versão 1.0.0`

- fundo branco;
- borda `#E2E8F0`;
- horizontal no desktop e reorganização simples no mobile;
- sem branding de cliente em superfícies públicas/plataforma.

## 8. Login
Deve conter somente o necessário:
- marca oficial;
- tagline;
- entrada clara;
- e-mail;
- senha;
- CTA principal;
- recuperação de senha.

CTA principal usa destaque azul/violeta. **Sem signup público.**

## 9. Gestão Virtus
Não existe tela intermediária “Sessão de plataforma”.
Após autenticação válida, a entrada é a Administração.

Conteúdo mínimo inicial:
- **Administração**
- “Gerencie as empresas que utilizam o Virtus.”
- ação **Nova empresa**

Não criar menus “Empresas”, “Usuários”, “Configurações” ou similares antes de existir necessidade funcional real.

## 10. Fluxo de acesso
Fluxo de produto:
**Gestão Virtus → cria empresa → define administrador inicial → administração da empresa → estrutura/gestores → equipes.**

- ator da Gestão Virtus não se torna automaticamente membro operacional das empresas;
- autoridade continua server-side;
- UI/JWT/localStorage/estado do frontend não concedem autoridade;
- a opção **“Eu mesmo”** permanece válida conforme F6-A11/D15 até atividade específica alterar o contrato;
- sem mudança de RLS, Policy Engine ou contratos F4/F5 por este documento.

## 11. Responsividade
Desktop e mobile usam a mesma identidade.
Pode mudar organização, largura, espaçamento e alinhamento; não pode mudar marca, cores, significado ou hierarquia fundamental.
Menu hambúrguer só existe quando houver navegação real que o exija.

## 12. Processo visual
Ordem obrigatória:
**asset oficial → tokens → componente → tela isolada → validação desktop/mobile → próxima tela**.

Sequência inicial:
**Header/Footer → Login → Gestão Virtus → Nova empresa**.

Quando este contrato não definir uma decisão visual, o agente deve reutilizar padrões aprovados ou sinalizar a lacuna. **Não inventar nova linguagem visual.**
