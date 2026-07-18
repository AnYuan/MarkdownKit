# Mermaid Provenance

MarkdownKit vendors the monolithic UMD bundle from Mermaid 10.9.5. The Python
verifier for vendored provenance is intentionally offline: it verifies the
checked-in bundle, inventory, report, notices, and release-policy anchors
without downloading or executing third-party code. The release wrapper first
resolves the Swift package graph, then invokes that offline verifier.

Refreshing Mermaid provenance is a separate, networked release-maintenance
operation. Perform it in a temporary directory, review every generated diff,
and never run it as part of normal CI.

## Authoritative Inputs

- Git tag: `v10.9.5`
- Git commit: `665b3d05cbe1ac7b78b154a464de39c5d17ba7b9`
- Package manager: `pnpm@8.15.4`
- Source tarball SHA-256:
  `883893d7ff503704d8f7356ee4c4a4d98f8286b4243803b1f92f7f004a54ccbd`
- npm tarball SHA-256:
  `56aa81c2fa6f229f8cd9d8a66f7b2b895ad76db3c3abd9aac11e549204274cd5`
- `pnpm-lock.yaml` SHA-256:
  `22adf8b174c018035398709f56f107735687c6d0e485030b4771bbb6320fbff9`
- Expected `mermaid.min.js` SHA-256:
  `616a109f19cd186842e11d45b35ac07456b3a75513310f6ea075351aa430b1e2`

## Reproduce the Bundle

The following commands reproduce the byte comparison recorded by the checked-in
inventory. They require Node.js, npm, `curl`, `tar`, `shasum`, and `cmp`.

```bash
WORK="$(mktemp -d)"
COMMIT="665b3d05cbe1ac7b78b154a464de39c5d17ba7b9"

curl -L --fail --silent --show-error \
  -o "$WORK/mermaid-source.tar.gz" \
  "https://github.com/mermaid-js/mermaid/archive/$COMMIT.tar.gz"
curl -L --fail --silent --show-error \
  -o "$WORK/mermaid-npm.tgz" \
  "https://registry.npmjs.org/mermaid/-/mermaid-10.9.5.tgz"

shasum -a 256 "$WORK/mermaid-source.tar.gz" "$WORK/mermaid-npm.tgz"

mkdir "$WORK/source" "$WORK/npm"
tar -xzf "$WORK/mermaid-source.tar.gz" -C "$WORK/source" --strip-components=1
tar -xzf "$WORK/mermaid-npm.tgz" -C "$WORK/npm"

cd "$WORK/source"
shasum -a 256 pnpm-lock.yaml
npm exec --yes pnpm@8.15.4 -- install \
  --frozen-lockfile \
  --ignore-scripts \
  --store-dir "$WORK/pnpm-store"
npm exec --yes pnpm@8.15.4 -- run build:mermaid

shasum -a 256 \
  "$WORK/npm/package/dist/mermaid.min.js" \
  "$WORK/source/packages/mermaid/dist/mermaid.min.js"
cmp \
  "$WORK/npm/package/dist/mermaid.min.js" \
  "$WORK/source/packages/mermaid/dist/mermaid.min.js"
```

## Refresh the Dependency Inventory

1. Export the production dependency closure:

   ```bash
   cd "$WORK/source"
   npm exec --yes pnpm@8.15.4 -- list \
     --filter ./packages/mermaid \
     --prod \
     --depth Infinity \
     --json > "$WORK/production-closure.json"
   ```

2. Capture Rollup's `modules` keys for the monolithic UMD output during the
   `build:mermaid` run. Normalize installed paths to exact `name@version`
   package instances from the frozen pnpm closure.
3. Add the three documented embedded prebundles (`heap`, `lodash`, and
   `web-worker`) whose code enters through Cytoscape or ELK rather than a
   separate Rollup module root.
4. Re-extract license evidence from the exact npm tarballs identified by each
   package's `resolved` and `integrity` fields. Keep DOMPurify's dual license,
   retain the Apache-2.0 redistribution choice, and derive `khroma@2.1.0` as MIT
   from its shipped `license` file.
5. Regenerate the normalized inventory and consolidated report, then update the
   corresponding hashes and reviewed policy anchors in
   `ThirdParty/provenance.lock.json` and `scripts/verify_provenance.py`.
6. Run `bash scripts/verify_provenance.sh` and review the complete inventory,
   report, notices, and policy-anchor diff before committing.

The checked-in inventory is the normalized release record. Temporary source
trees, package-manager stores, raw Rollup module maps, and downloaded tarballs
must not be committed.
