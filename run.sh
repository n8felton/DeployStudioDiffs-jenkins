#!/bin/bash -e
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
PROPFILE=metadata.properties
NO_PUSH=${NO_PUSH:-""}

error_exit() {
    echo "$@" 1>&2
    exit 1
}

cleanup() {
    hdiutil detach -quiet -force "$MOUNT" || echo > /dev/null
}

trap cleanup EXIT INT TERM

# Sanity checks
if [ -z "${BUILD_SPEC}" ]; then
    error_exit "You must define BUILD_SPEC in the environment for this script to run!"
fi

# Clone the diffs repo
rm -rf "${GIT_CHECKOUT_DIR}"
git clone ssh://git@github.com/timsutton/DeployStudioDiffs.git "${GIT_CHECKOUT_DIR}"

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

# Find and extract the Admin pkg
ADMIN_PKG_PATH="$(find "${MOUNT}" -name "deploystudioAdmin.pkg" -print)"
echo "Found Admin pkg path at $ADMIN_PKG_PATH"
tar -xzv \
    -C "${ADMIN_PKG_UNPACK_DEST}" \
    -f "${ADMIN_PKG_PATH}/Contents/Archive.pax.gz"

# extract the proper "build number" to append to the version
# final tag will look like: 'v1.7.3-160404'
BUILD_NUMBER=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "${GIT_CHECKOUT_DIR}/Packages/Admin/DeployStudio Admin.app/Contents/Info.plist")
if [ -z "${BUILD_NUMBER}" ]; then
    error_exit "Couldn't extract a build number from DeployStudio Admin.app Info.plist!"
fi
VERSION="${VERSION}-${BUILD_NUMBER}"

# Do Git repo stuff in a subshell
(
    cd "${GIT_CHECKOUT_DIR}" || exit
    # Depending on Jenkins we might not actually be checked-out to master
    git checkout master

    for TRACKED_PATH in "${TRACKED_PATHS[@]}"; do
        # Using --all since starting in 2.0, will also include removals
        git add --all "${TRACKED_PATH}"
    done

    git commit -m "${VERSION}"
    git tag "v${VERSION}"

    # only push to repo if NO_PUSH isn't set, otherwise just print the full log
    if [ -z "${NO_PUSH}" ]; then
        echo "Pushing changes and tag to GitHub.."
        git push --set-upstream origin master
        git push --tags
    else
        echo "NO_PUSH was set, just displaying log"
        git log -p -1
    fi
)

rm -rf "${PROPFILE}"
echo "VERSION=$VERSION" > "${PROPFILE}"
