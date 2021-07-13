#!/usr/bin/env bash
set -e -u -o pipefail

declare -r SCRIPT_NAME=$(basename "$0")
declare -r SCRIPT_DIR=$(cd $(dirname "$0") && pwd)

log() {
    local level=$1; shift
    echo -e "$level: $@"
}


err() {
    log "ERROR" "$@" >&2
}

info() {
    log "INFO" "$@"
}

die() {
    local code=$1; shift
    local msg="$@"; shift
    err $msg
    exit $code
}

usage() {
  local msg="$1"
  cat <<-EOF
Error: $msg

USAGE:
    $SCRIPT_NAME CATALOG_VERSION DEST_DIR VERSION

Example:
  $SCRIPT_NAME release-v0.7 deploy/resources v0.7.0
EOF
  exit 1
}

#declare -r CATALOG_VERSION="release-v0.7"

declare -r TEKTON_CATALOG="https://raw.githubusercontent.com/openshift/tektoncd-catalog"
declare -A TEKTON_CATALOG_TASKS=(
  # Need to remove version param
  ["openshift-client"]="0.2"
  ["git-clone"]="0.4"
  # Need to fix the task upstream for removing priviledged
  # ["buildah"]="0.1"
  ["kn"]="0.1"
  ["kn-apply"]="0.1"
  ["skopeo-copy"]="0.1"
  ["tkn"]="0.2"
)

declare -r OPENSHIFT_CATALOG="https://raw.githubusercontent.com/openshift/pipelines-catalog"
declare -A OPENSHIFT_CATALOG_TASKS=(
  ["s2i-go"]="0.1"
  ["s2i-java"]="0.1"
  ["s2i-python"]="0.1"
  ["s2i-nodejs"]="0.1"
  ["s2i-perl"]="0.1"
  ["s2i-php"]="0.1"
  ["s2i-ruby"]="0.1"
  ["s2i-dotnet"]="0.1"
)


download_task() {
  local task_path="$1"; shift
  local task_url="$1"; shift

  info "downloading ... $t from $task_url"
  # validate url
  curl --output /dev/null --silent --head --fail "$task_url" || return 1


  cat <<-EOF > "$task_path"
# auto generated by script/update-tasks.sh
# DO NOT EDIT: use the script instead
# source: $task_url
#
---
$(curl -sLf "$task_url" |
  sed -e 's|^kind: Task|kind: ClusterTask|g' \
      -e "s|^\(\s\+\)workingdir:\(.*\)|\1workingDir:\2|g"  )
EOF

 # NOTE: helps when the original and the generated need to compared
 # curl -sLf "$task_url"  -o "$task_path.orig"

}

change_task_image() {
  local dest_dir="$1"; shift
  local version="${1//./-}"; shift

  local task="$1"; shift
  local task_path="$dest_dir/${task}/${task}-task.yaml"
  local task_path_version="$dest_dir/${task}/${task}-$version-task.yaml"

  local expr=$1; shift
  local image=$1; shift

  sed \
      -i "s'$expr.*'$image'" \
      $task_path

  sed \
      -i "s'$expr.*'$image'" \
      $task_path_version
}

get_tasks() {
  local dest_dir="$1"; shift
  local version="${1//./-}"; shift

  local catalog="$1"; shift
  local catalog_version="$1"; shift

  local -n tasks=$1


  info "Downloading tasks from catalog $catalog to $dest_dir directory"
  for t in ${!tasks[@]} ; do
    # task filenames do not follow a naming convention,
    # some are taskname.yaml while others are taskname-task.yaml
    # so, try both before failing
    local task_url="$catalog/$catalog_version/task/$t/${tasks[$t]}/${t}.yaml"
    echo "$catalog/$catalog_version/task/$t/${tasks[$t]}/${t}.yaml"
    mkdir -p "$dest_dir/$t/"
    local task_path="$dest_dir/$t/$t-task.yaml"

    download_task  "$task_path" "$task_url"  ||
      die 1 "Failed to download $t"

    create_version "$task_path" "$t" "$version"  ||
      die 1  "failed to convert $t to $t-$version"
  done
}


create_version() {
  local task_path="$1"; shift
  local task="$1"; shift
  local version="$1"; shift
  local task_version_path="$(dirname $task_path)/$task-$version-task.yaml"

  sed \
    -e "s|^\(\s\+name:\)\s\+\($task\)|\1 \2-$version|g"  \
    $task_path  > "$task_version_path"
}



main() {


  local catalog_version=${1:-''}
  [[ -z "$catalog_version"  ]] && usage "missing catalog_version"
  shift

  local dest_dir=${1:-''}
  [[ -z "$dest_dir"  ]] && usage "missing destination directory"
  shift

  local version=${1:-''}
  [[ -z "$version"  ]] && usage "missing task_version"
  shift

  mkdir -p "$dest_dir" || die 1 "failed to create ${dest_dir}"

  dest_dir="$dest_dir/addons/02-clustertasks"
  mkdir -p "$dest_dir" || die 1 "failed to create catalog dir ${catalog_dir}"

  get_tasks "$dest_dir" "$version"  \
    "$TEKTON_CATALOG"   "$catalog_version"  TEKTON_CATALOG_TASKS

  get_tasks "$dest_dir" "$version"  \
    "$OPENSHIFT_CATALOG"   "$catalog_version"  OPENSHIFT_CATALOG_TASKS

  # ./manifest-tool inspect registry.redhat.io/rhel8/buildah:latest
  change_task_image "$dest_dir" "$version"  \
    "buildah"  "quay.io/buildah"  \
    "registry.redhat.io/rhel8/buildah@sha256:6a68ece207bc5fd8db2dd5cc2d0b53136236fb5178eb5b71eebe5d07a3c33d13"

  change_task_image "$dest_dir" "$version"  \
    "openshift-client"  'quay.io/openshift/origin-cli:$(params.VERSION)'  \
    'image-registry.openshift-image-registry.svc:5000/openshift/cli:$(params.VERSION)'

  # ./manifest-tool inspect registry.redhat.io/openshift-serverless-1/client-kn-rhel8:0.19
  change_task_image "$dest_dir" "$version"  \
    "kn"  "gcr.io/knative-releases/knative.dev/client/cmd/kn:latest"  \
    "registry.redhat.io/openshift-serverless-1/client-kn-rhel8@sha256:efb51d4a337566ca8532073cd598cc2cfbbec260f037ce4de19d4c67ee411358"

  change_task_image "$dest_dir" "$version"  \
    "kn-apply"  "gcr.io/knative-releases/knative.dev/client/cmd/kn:latest"  \
    "registry.redhat.io/openshift-serverless-1/client-kn-rhel8@sha256:efb51d4a337566ca8532073cd598cc2cfbbec260f037ce4de19d4c67ee411358"

  # ./manifest-tool inspect registry.redhat.io/rhel8/skopeo:latest
  change_task_image "$dest_dir" "$version"  \
    "skopeo-copy"  "quay.io/skopeo/stable"  \
    "registry.redhat.io/rhel8/skopeo@sha256:34e2d9e273bf610509984193a19aeea44e6061e86baca62a969661d122298bbf"

  # this will do the change for all pipelines catalog tasks except buildah-pr
  for t in ${!OPENSHIFT_CATALOG_TASKS[@]} ; do
    # ./manifest-tool inspect registry.redhat.io/ocp-tools-4-tech-preview/source-to-image-rhel8:v1.3.1
    change_task_image "$dest_dir" "$version"  \
      "$t"  "quay.io/openshift-pipeline/s2i"  \
      "registry.redhat.io/ocp-tools-4-tech-preview/source-to-image-rhel8@sha256:ba51e5e74ff5a29fd429b0bb77bc2130e5284826a60d042fc4e4374381a7a308"

    change_task_image "$dest_dir" "$version"  \
      "$t"  "quay.io/buildah"  \
      "registry.redhat.io/rhel8/buildah@sha256:6a68ece207bc5fd8db2dd5cc2d0b53136236fb5178eb5b71eebe5d07a3c33d13"

  done

  return $?
}

main "$@"
