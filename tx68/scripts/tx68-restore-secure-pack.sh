#!/usr/bin/env bash

set -euo pipefail

usage() {
	cat <<'EOF'
Usage: tx68/scripts/tx68-restore-secure-pack.sh [--force]

Restores TX68 private signing/packaging inputs from the owner-controlled,
age-encrypted GitHub release. The matching SSH RSA private key and its
passphrase are required. Existing files are never replaced unless --force is
explicitly supplied.
EOF
}

force=no
case "${1:-}" in
	"") ;;
	--force) force=yes ;;
	-h|--help) usage; exit 0 ;;
	*) usage >&2; exit 2 ;;
esac

for command_name in age gh sha256sum tar zstd; do
	command -v "${command_name}" >/dev/null || {
		echo "ERROR: missing command: ${command_name}" >&2
		echo "Install age with: sudo apt install age" >&2
		exit 1
	}
done

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd -- "${script_dir}/../.." && pwd)"
release_repo="minhdangoz/tx68-secure-pack"
release_tag="tx68-secure-pack-20260802"
archive_name="tx68-secure-pack-20260802.tar.zst.age"
identity="${TX68_SECURE_PACK_IDENTITY:-${HOME}/.ssh/id_rsa}"

[[ -f "${identity}" ]] || {
	echo "ERROR: SSH identity not found: ${identity}" >&2
	exit 1
}

tmpdir="$(mktemp -d)"
cleanup() {
	find "${tmpdir}" -type f -delete
	find "${tmpdir}" -depth -type d -empty -delete
}
trap cleanup EXIT

gh release download "${release_tag}" \
	--repo "${release_repo}" \
	--dir "${tmpdir}" \
	--pattern "${archive_name}" \
	--pattern SHA256SUMS

(
	cd "${tmpdir}"
	sha256sum --check SHA256SUMS
)

mkdir "${tmpdir}/restore"
age --decrypt --identity "${identity}" "${tmpdir}/${archive_name}" |
	zstd --decompress --stdout |
	tar -xf - -C "${tmpdir}/restore"

for relative_dir in tx68/android-pack tx68/uboot-debs; do
	destination="${repo_root}/${relative_dir}"
	source_dir="${tmpdir}/restore/${relative_dir}"
	[[ -d "${source_dir}" ]] || {
		echo "ERROR: archive is missing ${relative_dir}" >&2
		exit 1
	}
	if [[ -e "${destination}" && "${force}" != yes ]]; then
		echo "ERROR: refusing to replace existing ${destination}" >&2
		echo "Re-run with --force only after checking the existing files." >&2
		exit 1
	fi
	if [[ -e "${destination}" ]]; then
		find "${destination}" -type f -delete
		find "${destination}" -type l -delete
		find "${destination}" -depth -type d -empty -delete
	fi
	mkdir -p "$(dirname "${destination}")"
	mv "${source_dir}" "${destination}"
done

echo "TX68 secure pack restored successfully."
