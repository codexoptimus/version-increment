#!/bin/bash
set -euo pipefail

# https://stackoverflow.com/questions/59895/get-the-source-directory-of-a-bash-script-from-within-the-script-itself
script_dir="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )"
# shellcheck source=shared.sh
source "${script_dir}/shared.sh"

if [[ "${input_errors}" == 'true' ]] ; then
    exit 8
fi

##==----------------------------------------------------------------------------
##  Get tags from GitHub repo

# Skip if testing, or if use_api is true, otherwise pull tags
if [[ -z "${BATS_VERSION:-}" ]] ; then
    if [[ "${use_api:-}" != 'true' ]] ; then
        git fetch --quiet --force origin 'refs/tags/*:refs/tags/*'
    fi
fi

##==----------------------------------------------------------------------------
##  Version parsing

# Function to extract the semver part from the tag
extract_semver() {
    local tag="$1"
    if [[ -n "${tag_prefix:-}" ]]; then
        # Escape special characters in tag_prefix
        local escaped_prefix
        escaped_prefix=$(printf '%s\n' "$tag_prefix" | sed 's/[][\/.^$*]/\\&/g')

        # Use | as the delimiter to avoid conflicts with /
        echo "${tag}" | sed "s|^${escaped_prefix}||"
    else
        echo "${tag}"
    fi
}

# detect current version - removing "v" from start of tag if it exists
if [[ "${use_api:-}" == 'true' ]] ; then
    current_version="$(
        curl -fsSL \
            -H "Accept: application/vnd.github+json" \
            -H "Authorization: Bearer ${github_token}" \
            -H "X-GitHub-Api-Version: 2022-11-28" \
            "${GITHUB_API_URL}/repos/${GITHUB_REPOSITORY}/git/matching-refs/tags/" \
        | jq -r '.[].ref' | sed 's|refs/tags/||g' \
        | { grep_p "${pcre_allow_vprefix}" || true; } \
        | sed 's/^v//g' \
        | while read -r tag; do extract_semver "$tag"; done \
        | sort -V | tail -n 1
    )"
else
    current_version="$(
        git tag -l \
        | { grep_p "${pcre_allow_vprefix}" || true; } \
        | sed 's/^v//g' \
        | while read -r tag; do extract_semver "$tag"; done \
        | sort -V | tail -n 1
    )"
fi

# handle no version detected - start versioning!
if [[ -z "${current_version:-}" ]] ; then
    echo "⚠️ No previous release version identified in git tags"
    # brand new repo! (probably)
    case "${scheme}" in
        semver | conventional_commits)
            current_version="0.0.0"
        ;;
        calver)
            current_version="$(date '+%Y.%-m.0')"
        ;;
    esac
fi

echo "ℹ️ The current normal version is ${current_version}"

echo "CURRENT_VERSION=${current_version}" >> "${GITHUB_OUTPUT}"
echo "CURRENT_V_VERSION=v${current_version}" >> "${GITHUB_OUTPUT}"
