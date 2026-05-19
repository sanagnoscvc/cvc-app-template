# ts-flavor-tools — install Go-binary gate tools (gitleaks, osv-scanner).
# Both pinned. Idempotent: skipped if already on PATH.
GITLEAKS_VERSION=8.21.2
OSV_SCANNER_VERSION=1.9.2

arch=$(uname -m)
case "$arch" in
  x86_64)  gl_arch="x64";  osv_asset="osv-scanner_linux_amd64" ;;
  aarch64) gl_arch="arm64"; osv_asset="osv-scanner_linux_arm64" ;;
  *) echo "  WARN: unknown arch '$arch' — install gitleaks + osv-scanner manually" >&2;
     gl_arch=""; osv_asset="" ;;
esac

if [ -n "$gl_arch" ] && ! command -v gitleaks >/dev/null 2>&1; then
  echo -e "${cyan}→ Installing gitleaks v${GITLEAKS_VERSION}...${reset}"
  tmpdir=$(mktemp -d)
  curl -fsSL "https://github.com/gitleaks/gitleaks/releases/download/v${GITLEAKS_VERSION}/gitleaks_${GITLEAKS_VERSION}_linux_${gl_arch}.tar.gz" \
    | tar -xz -C "$tmpdir" gitleaks
  sudo mv "$tmpdir/gitleaks" /usr/local/bin/gitleaks
  rm -rf "$tmpdir"
fi

if [ -n "$osv_asset" ] && ! command -v osv-scanner >/dev/null 2>&1; then
  echo -e "${cyan}→ Installing osv-scanner v${OSV_SCANNER_VERSION}...${reset}"
  sudo curl -fsSL -o /usr/local/bin/osv-scanner \
    "https://github.com/google/osv-scanner/releases/download/v${OSV_SCANNER_VERSION}/${osv_asset}"
  sudo chmod +x /usr/local/bin/osv-scanner
fi
