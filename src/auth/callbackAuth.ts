/** Marker provided by Supabase Auth callback; never persisted or authoritative. */
export function callbackAuthType(url: string): string | null {
  try {
    const parsed = new URL(url);
    return parsed.searchParams.get("type") ??
      new URLSearchParams(parsed.hash.replace(/^#/, "")).get("type");
  } catch {
    return null;
  }
}

export function isInviteCallback(url: string): boolean {
  return callbackAuthType(url) === "invite";
}
