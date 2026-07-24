#!/usr/bin/env bash
# Regenerate deps.nix for the monstar rev currently pinned in flake.lock.
# deps.nix = ghostty's committed build.zig.zon.nix (at the ghostty rev monstar
# pins) + monstar's own direct deps spliced in, with fresh nix hashes.
# Run after `nix flake update monstar-src`; then `nix build` to verify.
set -euo pipefail
cd "$(dirname "$0")"

need() { command -v "$1" >/dev/null || { echo "missing: $1" >&2; exit 1; }; }
need curl; need jq; need awk; need sed

rev=$(jq -r '.nodes["monstar-src"].locked.rev' flake.lock)
[[ "$rev" =~ ^[0-9a-f]{40}$ ]] || { echo "no locked monstar rev in flake.lock" >&2; exit 1; }
echo "monstar rev: $rev"

zon=$(curl -fsSL "https://raw.githubusercontent.com/rockorager/monstar/$rev/build.zig.zon")

ghostty_rev=$(printf '%s' "$zon" | grep -oP 'ghostty\.git#\K[0-9a-f]{40}' | head -1)
[[ -n "$ghostty_rev" ]] || { echo "could not find ghostty rev in build.zig.zon" >&2; exit 1; }
echo "ghostty rev: $ghostty_rev"

# Base: ghostty's full transitive tree (its own committed, immutable-at-rev file).
base=$(curl -fsSL "https://raw.githubusercontent.com/ghostty-org/ghostty/$ghostty_rev/build.zig.zon.nix")

# Pull each direct dep (key, url, zig-hash) out of monstar's build.zig.zon.
deps=$(printf '%s\n' "$zon" | awk '
  /^[[:space:]]*\.dependencies[[:space:]]*=[[:space:]]*\.\{/ { indeps=1; next }
  indeps==0 { next }
  /^[[:space:]]*\.[A-Za-z0-9_]+[[:space:]]*=[[:space:]]*\.\{/ {
    key=$0; sub(/^[[:space:]]*\./,"",key); sub(/[[:space:]]*=.*/,"",key)
    url=""; hsh=""; next
  }
  /^[[:space:]]*\.url[[:space:]]*=/  { v=$0; sub(/^[^"]*"/,"",v); sub(/".*/,"",v); url=v; next }
  /^[[:space:]]*\.hash[[:space:]]*=/ { v=$0; sub(/^[^"]*"/,"",v); sub(/".*/,"",v); hsh=v; next }
  /^[[:space:]]*\},/ {
    if (key!="" && url!="" && hsh!="") print key "\t" url "\t" hsh
    key=""; url=""; hsh=""; next
  }
')
[[ -n "$deps" ]] || { echo "parsed no dependencies from build.zig.zon" >&2; exit 1; }

# Build the linkFarm entries for monstar's direct deps, hashing each with the
# same fetcher deps.nix uses (fetchgit for git, fetchurl for raw tarballs).
blocks=""
while IFS=$'\t' read -r key url hsh; do
  case "$url" in
    git+*)
      giturl=${url#git+}; giturl=${giturl%%#*}; grev=${url##*#}
      echo "  hashing (git) $key ..." >&2
      sri=$(nix run nixpkgs#nix-prefetch-git -- --url "$giturl" --rev "$grev" --quiet 2>/dev/null | jq -r '.hash')
      unpack=true ;;
    http*)
      # N-V-__8A hashes are single-file artifacts zig fetches raw (unpack=false).
      if [[ "$hsh" == N-V-__8A* ]]; then
        echo "  hashing (file) $key ..." >&2
        sri=$(nix store prefetch-file --json "$url" 2>/dev/null | jq -r '.hash')
        unpack=false
      else
        echo "ERROR: '$key' is an https package dir (unpack=true); add a case for it." >&2
        exit 1
      fi ;;
    *) echo "ERROR: unknown url scheme for '$key': $url" >&2; exit 1 ;;
  esac
  [[ -n "$sri" && "$sri" != null ]] || { echo "ERROR: empty hash for $key" >&2; exit 1; }
  blocks+="    {
      name = \"$hsh\";
      path = fetchZigArtifact {
        name = \"$key\";
        url = \"$url\";
        hash = \"$sri\";
        unpack = $unpack;
      };
    }
"
done <<< "$deps"

# Splice the monstar entries in just before the linkFarm's closing `]`.
printf '%s\n' "$base" | awk -v blocks="$blocks" '
  { lines[NR]=$0 }
  END {
    last=NR; while (last>0 && lines[last] ~ /^[[:space:]]*$/) last--
    for (i=1;i<last;i++) print lines[i]
    printf "%s", blocks
    print lines[last]
  }
' > deps.nix
echo "wrote deps.nix"

# Keep package.nix version in sync with build.zig.zon.
ver=$(printf '%s' "$zon" | grep -oP '\.version[[:space:]]*=[[:space:]]*"\K[^"]+')
if [[ -n "$ver" ]]; then
  sed -i -E "s/^(  version = \")[^\"]*(\";)/\1$ver\2/" package.nix
  echo "package.nix version: $ver"
fi

echo "done. verify with: nix build"
