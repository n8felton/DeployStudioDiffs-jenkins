#!/bin/bash
#
# Downloads a DeployStudio installer dmg, extracts it and commits
# certain paths to a Git repo so that changes can be more easily
# tracked. Used for https://github.com/timsutton/DeployStudioDiffs
#
# This script assumes you define BUILD_SPEC as an environment variable.
# It can be "Nightly", "Release" to get the latest from that branch,
# or a specific version, ie. "1.6.4-NB140303" or "1.6.3"

# GIT_CHECKOUT_DIR is a dir relative to the workspace where this scripts expects
# the public Git repo to be. In Jenkins, you would configure this as an additional
# behavior for the Git plugin.
GIT_CHECKOUT_DIR="repo"

error_exit() {
    echo "$@" 1>&2
    exit 1
}

# Sanity checks
if [ -z "${BUILD_SPEC}" ]; then
    error_exit "You must define BUILD_SPEC in the environment for this script to run!"
fi
if [ ! -d "${GIT_CHECKOUT_DIR}" ]; then
    error_exit "Public Git repo should have been checked out to ${GIT_CHECKOUT_DIR}!"
fi

# Set up some dirs
INSTALLERS_DIR="$(pwd)/installers"
REPO_PKGS_PREFIX="Packages"
REPO_ADMIN_PKG_PREFIX="${REPO_PKGS_PREFIX}/Admin"
ADMIN_PKG_UNPACK_DEST="${GIT_CHECKOUT_DIR}/${REPO_ADMIN_PKG_PREFIX}"
for REQ_DIR in "${ADMIN_PKG_UNPACK_DEST}" "${INSTALLERS_DIR}"; do
    [ -d "${REQ_DIR}" ] || mkdir -p "${REQ_DIR}"
done

# Define the paths we'll be tracking
# declare -a TRACKED_PATHS=(
#     "${REPO_ADMIN_PKG_PREFIX}/DeployStudio Admin.app/Contents/Applications/DeployStudio Assistant.app"
#     "${REPO_ADMIN_PKG_PREFIX}/DeployStudio Admin.app/Contents/Plugins"
#     "${REPO_ADMIN_PKG_PREFIX}/DeployStudio Admin.app/Contents/Frameworks/DSCore.framework/Versions/A/Resources"
# )
declare -a TRACKED_PATHS=(
    "${REPO_ADMIN_PKG_PREFIX}/DeployStudio Admin.app"
)

DS_BASEURL="http://deploystudio.com/Downloads"
# Find our download URL
if [ "$BUILD_SPEC" == "Nightly" ]; then
    CHECK_FILE="_nb.current"
elif [ "$BUILD_SPEC" == "Stable" ]; then
    CHECK_FILE="_dss.current"
fi

if [ -n "${CHECK_FILE}" ]; then
    # Find either the latest version, or..
    VERSION=$(curl -s -f "$DS_BASEURL/$CHECK_FILE")
    echo "Latest version for "${BUILD_SPEC} branch: "${VERSION}"
else
    # Pass the requested version directly to the download URL
    VERSION="${BUILD_SPEC}"
fi

URL="http://deploystudio.com/Downloads/DeployStudioServer_v${VERSION}.dmg"

# Download it
OUTFILE="${INSTALLERS_DIR}/DeployStudioServer_v${VERSION}.dmg"
if [ ! -e "${OUTFILE}" ]; then
    echo "Downloading: ${URL}"
    curl -s -f -o "${OUTFILE}" "${URL}"
fi

# Mount it
MOUNT=$(mktemp -d /tmp/dsdiff-XXXX)
hdiutil attach -mountpoint "${MOUNT}" "${OUTFILE}"
[ "$?" -ne 0 ] && exit 1

# Find and extract the Admin pkg
ADMIN_PKG_PATH="$(find "${MOUNT}" -name "deploystudioAdmin.pkg" -print 2> /dev/null)"
echo "Found Admin pkg path at $ADMIN_PKG_PATH"
tar -xzv \
    -C "${ADMIN_PKG_UNPACK_DEST}" \
    -f "${ADMIN_PKG_PATH}/Contents/Archive.pax.gz"

# Do Git stuff
cd "${GIT_CHECKOUT_DIR}"
# Depending on Jenkins we might not actually be checked-out to master
git checkout master

for TRACKED_PATH in "${TRACKED_PATHS[@]}"; do
    # Using --all since starting in 2.0, will also include removals
    git add --all "${TRACKED_PATH}"
done

git commit -m "${VERSION}"
git tag "v${VERSION}"
#debug
# git log
git push
git push --tags
cd "${WORKSPACE}"

# Unmount
hdiutil detach "${MOUNT}"

# Clean up
rm -rf "${GIT_CHECKOUT_DIR}"