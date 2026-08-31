import type { ReactNode } from "react";

type CriterionIconProps = {
  index: number;
};

function IconFrame({ children }: { children: ReactNode }) {
  return (
    <svg
      viewBox="0 0 24 24"
      fill="none"
      stroke="currentColor"
      strokeWidth="1.8"
      strokeLinecap="round"
      strokeLinejoin="round"
      aria-hidden="true"
    >
      {children}
    </svg>
  );
}

/*
  Mapeamento semântico oficial dos 8 critérios do Virtus:
  0 Desempenho técnico               -> ferramentas/engrenagem
  1 Produtividade                    -> gráfico de barras
  2 Comunicação                      -> balão de conversa
  3 Trabalho em equipe               -> pessoas/equipe
  4 Proatividade e iniciativa        -> raio
  5 Adaptação e flexibilidade        -> setas de adaptação
  6 Comprometimento e responsabilidade -> escudo + check
  7 Desenvolvimento profissional     -> tendência crescente
*/
export default function CriterionIcon({ index }: CriterionIconProps) {
  switch (index) {
    case 0:
      return (
        <IconFrame>
          <circle cx="12" cy="12" r="3" />
          <path d="M19.4 15a1.7 1.7 0 0 0 .34 1.88l.06.06-2.83 2.83-.06-.06A1.7 1.7 0 0 0 15 19.4a1.7 1.7 0 0 0-1 .6 1.7 1.7 0 0 0-.4 1.1V21h-4v-.09a1.7 1.7 0 0 0-1.1-1.58 1.7 1.7 0 0 0-1.88.34l-.06.06-2.83-2.83.06-.06A1.7 1.7 0 0 0 4.6 15a1.7 1.7 0 0 0-.6-1 1.7 1.7 0 0 0-1.1-.4H3v-4h.09A1.7 1.7 0 0 0 4.67 8.5a1.7 1.7 0 0 0-.34-1.88l-.06-.06 2.83-2.83.06.06A1.7 1.7 0 0 0 9 4.6a1.7 1.7 0 0 0 1-.6 1.7 1.7 0 0 0 .4-1.1V3h4v.09A1.7 1.7 0 0 0 15.5 4.67a1.7 1.7 0 0 0 1.88-.34l.06-.06 2.83 2.83-.06.06A1.7 1.7 0 0 0 19.4 9c.13.37.34.72.6 1 .3.3.69.48 1.1.5H21v4h-.09A1.7 1.7 0 0 0 19.4 15Z" />
        </IconFrame>
      );

    case 1:
      return (
        <IconFrame>
          <path d="M4 20V10M10 20V4M16 20v-7M22 20H2" />
        </IconFrame>
      );

    case 2:
      return (
        <IconFrame>
          <path d="M4 5.5h16v11H9l-5 4v-15Z" />
          <path d="M8 10h8M8 13h5" />
        </IconFrame>
      );

    case 3:
      return (
        <IconFrame>
          <circle cx="9" cy="8" r="3" />
          <path d="M3.5 19c.6-3.4 2.5-5.2 5.5-5.2s4.9 1.8 5.5 5.2" />
          <circle cx="17" cy="9" r="2.2" />
          <path d="M15.7 14.2c2.9-.4 4.6 1 5 3.8" />
        </IconFrame>
      );

    case 4:
      return (
        <IconFrame>
          <path d="m13 2-7 11h6l-1 9 7-12h-6l1-8Z" />
        </IconFrame>
      );

    case 5:
      return (
        <IconFrame>
          <path d="M20 7h-5V2" />
          <path d="M20 7a8 8 0 0 0-13.7-2.2L4.5 6.6" />
          <path d="M4 17h5v5" />
          <path d="M4 17a8 8 0 0 0 13.7 2.2l1.8-1.8" />
        </IconFrame>
      );

    case 6:
      return (
        <IconFrame>
          <path d="M12 3 20 6v5c0 5.2-2.8 8.5-8 10-5.2-1.5-8-4.8-8-10V6l8-3Z" />
          <path d="m8.5 12 2.2 2.2 4.8-5" />
        </IconFrame>
      );

    case 7:
      return (
        <IconFrame>
          <path d="m4 17 6-6 4 4 6-8" />
          <path d="M15 7h5v5" />
        </IconFrame>
      );

    default:
      return null;
  }
}
