export interface PropsVirtusLogo {
  readonly variant?: "horizontal" | "symbol";
  readonly theme?: "light" | "dark";
  readonly className?: string;
}

export default function VirtusLogo({
  variant = "horizontal",
  theme = "light",
  className,
}: PropsVirtusLogo) {
  const classes = ["virtus-logo", `virtus-logo--${variant}`, `virtus-logo--${theme}`, className]
    .filter(Boolean)
    .join(" ");
  return (
    <span className={classes} aria-label="Virtus">
      <svg className="virtus-logo__symbol" viewBox="0 0 40 32" aria-hidden="true">
        <defs>
          <linearGradient id="virtus-logo-gradient" x1="0" y1="1" x2="1" y2="0">
            <stop offset="0" stopColor="#0EA5E9" />
            <stop offset="1" stopColor="#6366F1" />
          </linearGradient>
        </defs>
        <path d="M4 6 12 26 20 13 28 26 36 6" fill="none" stroke="url(#virtus-logo-gradient)" strokeLinecap="round" strokeLinejoin="round" strokeWidth="5" />
      </svg>
      {variant === "horizontal" && <span className="virtus-logo__wordmark">VIRTUS</span>}
    </span>
  );
}
