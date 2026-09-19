interface VirtusBrandProps {
  readonly context?: string;
}

function VirtusBrand({ context }: VirtusBrandProps) {
  return (
    <div className="virtus-shell-brand" aria-label={context ? `Virtus · ${context}` : "Virtus"}>
      <img
        src="/brand/virtus-symbol.png"
        alt=""
        aria-hidden="true"
        className="virtus-shell-brand__symbol"
      />
      <strong className="virtus-shell-brand__wordmark">VIRTUS</strong>
      {context && (
        <>
          <span className="virtus-shell-brand__separator" aria-hidden="true">·</span>
          <span className="virtus-shell-brand__context">{context}</span>
        </>
      )}
    </div>
  );
}

export default VirtusBrand;
