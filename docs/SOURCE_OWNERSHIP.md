# TX68 and KM7 source ownership

`config/boards/tx68-km7-source-lock.inc` is the single source of truth for
board-critical source URLs, immutable snapshot commits, upstream provenance,
package versions, and checksums.

## Current policy

- Production builds consume only repositories owned by `minhdangoz`.
- Git inputs use `commit:<sha>`, never moving branches.
- Binary packages use a fixed release tag and SHA256.
- TX68 signing keys and proprietary pack inputs are never stored in plaintext
  in Git. They are stored in the private `minhdangoz/tx68-secure-pack` release,
  encrypted to the owner's passphrase-protected SSH RSA identity.
- Ubuntu packages, compiler downloads, and generic firmware remain normal
  distribution/build dependencies. They are not board-source authorities.

## Updating later

Updates remain supported. They become explicit and reversible:

1. Import the desired upstream revision into a new owned snapshot commit.
2. Keep the old snapshot and tag; do not rewrite it.
3. Update the matching entry in `tx68-km7-source-lock.inc`.
4. Synchronize the version/snapshot tables in `README.md` and the matching
   board README (`docs/TX68_README.md` or `km7/README.md`). The source lock
   remains authoritative if documentation and code ever disagree.
5. Run `config-dump`, build the image, and test it on the matching device.
6. Commit the lock and documentation change only after hardware acceptance.

For AIC8801, upload the new `.deb` files to a new immutable release under
`minhdangoz/aic8800-packages`, then update both the version and SHA256 values.

For TX68 secure material, create a new dated encrypted release. Never delete
the last hardware-accepted release until its replacement has been restored and
tested. A second encrypted copy on offline/removable storage is still strongly
recommended because one GitHub account is one failure domain.

## Restore TX68 private inputs

Install `age` and authenticate `gh`, then run:

```bash
sudo apt install age
./tx68/scripts/tx68-restore-secure-pack.sh
```

The command asks for the SSH RSA key passphrase locally. The passphrase and
plaintext signing keys are never uploaded by the script.
