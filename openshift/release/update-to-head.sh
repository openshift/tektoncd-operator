#!/usr/bin/env bash

# Synchs the release-next branch to master and then triggers CI
# Usage: update-to-head.sh

set -ex
REPO_NAME=`basename $(git remote get-url origin)`
OPENSHIFT_REMOTE=${OPENSHIFT_REMOTE:-openshift}
OPENSHIFT_ORG=${OPENSHIFT_ORG:-openshift}
PIPELINE_VERSION=${PIPELINE_VERSION:-0.24.0}
TRIGGERS_VERSION=${TRIGGERS_VERSION:-0.13.1}
LABEL=nightly-ci
# The below directory will contain nightly release yaml for pipelines and trigger
PIPELINE_YAML_DIRECTORY=cmd/openshift/operator/kodata/tekton-pipeline/${PIPELINE_VERSION}-PreRelease
TRIGGERS_YAML_DIRECTORY=cmd/openshift/operator/kodata/tekton-trigger/${TRIGGERS_VERSION}-PreRelease

# Reset release-next to upstream/main.
git fetch upstream main
git checkout upstream/main --no-track -B release-next

# Update openshift's master and take all needed files from there.
git fetch ${OPENSHIFT_REMOTE} master
git checkout FETCH_HEAD openshift OWNERS_ALIASES OWNERS .tekton

mkdir -p ${TRIGGERS_YAML_DIRECTORY}
# Downloading triggers nightly release yaml
wget https://raw.githubusercontent.com/openshift/tektoncd-triggers/release-next-ci/openshift/release/tektoncd-triggers-nightly.yaml -P ${TRIGGERS_YAML_DIRECTORY}

mkdir -p ${PIPELINE_YAML_DIRECTORY}
# Downloading pipeline nightly release yaml
wget https://raw.githubusercontent.com/openshift/tektoncd-pipeline/release-next-ci/openshift/release/tektoncd-pipeline-nightly.yaml -P ${PIPELINE_YAML_DIRECTORY}
# copying role and rolebinding to pipeline yaml directory
cp cmd/openshift/operator/kodata/tekton-pipeline/0.22.0/01-clusterrole.yaml ${PIPELINE_YAML_DIRECTORY}
cp cmd/openshift/operator/kodata/tekton-pipeline/0.22.0/02-rolebinding.yaml ${PIPELINE_YAML_DIRECTORY}

git add openshift OWNERS_ALIASES OWNERS cmd/openshift/operator/kodata
git commit -m ":open_file_folder: Update openshift specific files."

git push -f ${OPENSHIFT_REMOTE} release-next

# Trigger CI
git checkout release-next -B release-next-ci
date > ci
git add ci
git commit -m ":robot: Triggering CI on branch 'release-next' after synching to upstream/master"
git push -f ${OPENSHIFT_REMOTE} release-next-ci

# removing upstream remote so that hub points origin for hub pr list command due to this issue https://github.com/github/hub/issues/1973
git remote remove upstream
already_open_github_issue_id=$(hub pr list -s open -f "%I %l%n"|grep ${LABEL}| awk '{print $1}'|head -1)
[[ -n ${already_open_github_issue_id} ]]  && {
    echo "PR for nightly is already open on #${already_open_github_issue_id}"
    #hub api repos/${OPENSHIFT_ORG}/${REPO_NAME}/issues/${already_open_github_issue_id}/comments -f body='/retest'
    exit
}

hub pull-request -m "🛑🔥 Triggering Nightly CI for ${REPO_NAME} 🔥🛑" -m "/hold" -m "Nightly CI do not merge :stop_sign:" \
    --no-edit -l "${LABEL}" -b ${OPENSHIFT_ORG}/${REPO_NAME}:release-next -h ${OPENSHIFT_ORG}/${REPO_NAME}:release-next-ci

# This fix is required while running locally, otherwise your upstream remote is removed
git remote add upstream git@github.com:tektoncd/operator.git
