#!/usr/bin/env bash

set -o errexit -o nounset -o pipefail

# Set by GH actions, see
# https://docs.github.com/en/actions/learn-github-actions/environment-variables#default-environment-variables
TAG=${GITHUB_REF_NAME}
# The prefix is chosen to match what GitHub generates for source archives
PREFIX="rules_vhdl-${TAG:1}"
ARCHIVE="rules_vhdl-$TAG.tar.gz"
ARCHIVE_TMP=$(mktemp)

# NB: configuration for 'git archive' is in /.gitattributes
git archive --format=tar --prefix=${PREFIX}/ ${TAG} > $ARCHIVE_TMP

gzip < $ARCHIVE_TMP > $ARCHIVE
SHA=$(shasum -a 256 $ARCHIVE | awk '{print $1}')

cat << EOF
Add to your \`MODULE.bazel\` file:

\`\`\`starlark
bazel_dep(name = "gateweavers_rules_vhdl", version = "${TAG:1}")
\`\`\`

And also register a vhdl simulator toolchain. For example:

\`\`\`starlark
vhdl_toolchains = use_extension("gateweavers_rules_vhdl//simulator:extensions.bzl", "vhdl_toolchains")
vhdl_toolchains.ghdl(
    name = "ghdl_6_0_mcode",
    backend = "mcode",
    is_default = True,
    sha256 = "30d6a977b8456d140bbafecbbe64b1947a3d92eeae8f5e6d9f528a174f9566e7",
    strip_prefix = "ghdl-mcode-6.0.0-ubuntu24.04-x86_64",
    url = "https://github.com/ghdl/ghdl/releases/download/v6.0.0/ghdl-mcode-6.0.0-ubuntu24.04-x86_64.tar.gz",
    version = "6.0",
)
\`\`\`

EOF