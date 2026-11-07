#!/usr/bin/env bash
# Regenerate deps.nix for the monstar rev currently pinned in flake.lock.
# deps.nix = ghostty's committed deps/packages.nix (at the ghostty rev monstar
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

# Pinned either as a git url (ghostty.git#<rev>) or a GitHub tarball (archive/<rev>.tar.gz).
ghostty_rev=$(printf '%s' "$zon" | grep -oP 'ghostty(\.git#|/archive/)\K[0-9a-f]{40}' | head -1 || true)
[[ -n "$ghostty_rev" ]] || { echo "could not find ghostty rev in build.zig.zon" >&2; exit 1; }
echo "ghostty rev: $ghostty_rev"

# Base: ghostty's full transitive tree (its own committed, immutable-at-rev file).
# Ghostty moved it from build.zig.zon.nix to deps/packages.nix on 2026-11-04.
base=""
for f in deps/packages.nix build.zig.zon.nix; do
  if base=$(curl -fsSL "https://raw.githubusercontent.com/ghostty-org/ghostty/$ghostty_rev/$f" 2>/dev/null); then
    echo "ghostty deps: $f"; break
  fi
done
[[ -n "$base" ]] || { echo "ghostty $ghostty_rev has neither deps/packages.nix nor build.zig.zon.nix" >&2; exit 1; }

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
# same fetchers deps.nix uses (fetchZigGit for git, fetchzip/fetchurl for tarballs).
blocks=""
while IFS=$'\t' read -r key url hsh; do
  # The packages attrset would reject a second definition of the same hash.
  if grep -qF "\"$hsh\" =" <<< "$base"; then echo "  $key already in ghostty's tree" >&2; continue; fi
  case "$url" in
    git+*)
      giturl=${url#git+}; giturl=${giturl%%#*}; giturl=${giturl%%\?*}; grev=${url##*#}
      echo "  hashing (git) $key ..." >&2
      # Same checkout settings as deps.nix's fetchZigGit, so the hash matches.
      sri=$(GIT_ATTR_SOURCE=4b825dc642cb6eb9a060e54bf8d69288fbee4904 \
        GIT_CONFIG_COUNT=1 GIT_CONFIG_KEY_0=core.autocrlf GIT_CONFIG_VALUE_0=false \
        nix run nixpkgs#nix-prefetch-git -- --url "$giturl" --rev "$grev" --quiet 2>/dev/null | jq -r '.hash')
      fetch="fetchZigGit {
      name = \"$key\";
      url = \"$giturl\";
      rev = \"$grev\";
      hash = \"$sri\";
    };" ;;
    http*)
      # N-V-__8A hashes are packages without a manifest; zig unpacks the raw archive itself.
      if [[ "$hsh" == N-V-__8A* ]]; then
        echo "  hashing (file) $key ..." >&2
        sri=$(nix store prefetch-file --json "$url" 2>/dev/null | jq -r '.hash')
        fetch="fetchurl {
      url = \"$url\";
      hash = \"$sri\";
    };"
      else
        # Package tarballs: --unpack strips the top dir, matching fetchzip's hash.
        echo "  hashing (tarball) $key ..." >&2
        sri=$(nix store prefetch-file --unpack --json "$url" 2>/dev/null | jq -r '.hash')
        fetch="fetchzip {
      name = \"$key\";
      url = \"$url\";
      hash = \"$sri\";
    };"
      fi ;;
    *) echo "ERROR: unknown url scheme for '$key': $url" >&2; exit 1 ;;
  esac
  [[ -n "$sri" && "$sri" != null ]] || { echo "ERROR: empty hash for $key" >&2; exit 1; }
  blocks+="    \"$hsh\" = $fetch
"
done <<< "$deps"

# Splice the monstar entries in before the closing `};` of the `packages` attrset.
printf '%s\n' "$base" | awk -v blocks="$blocks" '
  /^  packages = \{$/ { inpkgs=1 }
  inpkgs && !done && /^  \};$/ { printf "%s", blocks; done=1 }
  { print }
  END { if (!done) exit 1 }
' > deps.nix || { echo "could not find the packages attrset's closing }; in ghostty's deps file" >&2; exit 1; }
echo "wrote deps.nix"

# Keep package.nix version in sync with build.zig.zon.
ver=$(printf '%s' "$zon" | grep -oP '\.version[[:space:]]*=[[:space:]]*"\K[^"]+')
if [[ -n "$ver" ]]; then
  sed -i -E "s/^(  version = \")[^\"]*(\";)/\1$ver\2/" package.nix
  echo "package.nix version: $ver"
fi

echo "done. verify with: nix build"
