# Immutable, user-owned source inputs for TX68 and KM7.
#
# Update policy: import and test a new snapshot first, then change the matching
# commit/hash here. Never point production builds at a moving branch or a
# release named "latest". The upstream commits are retained as provenance;
# builds consume the owned snapshot commits.

declare -g TX68_KERNEL_SOURCE="https://github.com/minhdangoz/linux-stable.git"
declare -g TX68_KERNEL_REF="commit:457936105aed97a31778991bff97e8a0346d1bff"
declare -g TX68_KERNEL_UPSTREAM_REF="2fe596715f840d053aed5cee5455f701bdcd2b50"

declare -g TX68_UBOOT_SOURCE="https://github.com/minhdangoz/tx68-u-boot.git"
declare -g TX68_UBOOT_REF="commit:d7e300ad8182b8fbd15f66bcb45c4e62ac23a3a2"
declare -g TX68_UBOOT_UPSTREAM_REF="66e2615a13f7e2b3ee269fd0ec027db117c493b7"

declare -g TX68_AIC8800_REPOSITORY="minhdangoz/aic8800-packages"
declare -g TX68_AIC8800_VERSION="5.0+git20260123.5f7be68d-7"
declare -g TX68_AIC8800_FIRMWARE_SHA256="627f4415974081eb15de261c60bd34b24247a147aa92a1b4fd3ea5cc420d8878"
declare -g TX68_AIC8800_SDIO_DKMS_SHA256="fc35684e77799f79f12474cdac1913f4b3ff1b0a5697f98cb48550e81e1f1b6a"

declare -g KM7_KERNEL_SOURCE="https://github.com/minhdangoz/khadas-linux.git"
declare -g KM7_KERNEL_REF="commit:ebbf016784df1436c6bdf0118f816f69042dd675"
declare -g KM7_KERNEL_UPSTREAM_REF="4e557e233b9da219f48b82bfa313f353386097ec"

declare -g KM7_COMMON_DRIVERS_SOURCE="https://github.com/minhdangoz/khadas-common-drivers.git"
declare -g KM7_COMMON_DRIVERS_REF="commit:fc43f888dfea51bcf5037623fd4b4683cd5fbf9a"
declare -g KM7_COMMON_DRIVERS_UPSTREAM_REF="3a11a86a02e759fc57fc79410215f7c0c3a0d8e0"

declare -g KM7_UBOOT_SOURCE="https://github.com/minhdangoz/coreelec-u-boot.git"
declare -g KM7_UBOOT_REF="commit:3a50f0ae983426a44940223423aa348deb909dc9"
declare -g KM7_UBOOT_UPSTREAM_REF="4a16015168d00d08487781fc914e048944554c6e"
declare -g KM7_FIP_HEADER_SHA256="5a6bd30738e5799bf87430a38b2b28b99cdf07f2c90de61fd89e1765bb3769f0"
