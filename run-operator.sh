#!/bin/bash

# Exit immediately if a command exits with a non-zero status and set pipefail
set -eu -o pipefail

# Declare and initialize variables
declare OPERATOR_DIR=~/operator/
declare KIND_CONFIG=""                                                        # Optional kind configuration file
declare KIND_CONTEXT=test                                                     # Default kind cluster context name
declare IMAGE_OPERATOR=quay.io/prometheus-operator/prometheus-operator        # Operator image
declare IMAGE_RELOADER=quay.io/prometheus-operator/prometheus-config-reloader # Reloader image
declare IMAGE_WEBHOOK=quay.io/prometheus-operator/admission-webhook           # Webhook image
declare VERSION_LABEL="app.kubernetes.io\/version: "                          # Label used for versioning
declare SKIP_OPERATOR_RUN_CHECK=false                                         # Skip operator existence check if true
declare DEBUG_LEVEL="default"                                                 # Default debug level
declare GOARCH                                                                # Architecture of the Go runtime
GOARCH=$(go env GOARCH)
declare ARCH=$GOARCH
declare TAG  # Tag for images
declare GOOS # Operating system of the Go runtime
GOOS=$(go env GOOS)

# Function to log the current date and time
log_time() { date +"%Y-%m-%d %H:%M:%S"; }

# Logging helper: Log info messages if DEBUG_LEVEL is set to "info"
info() {
    if [ "$DEBUG_LEVEL" == "info" ]; then
        printf "\n%s 🔔 $* \n" "$(log_time)"
    fi
}

# Logging helper: Log success messages
ok() {
    printf "%s ✅ $* \n" "$(log_time)"
}

# Error handling: Log error messages and exit
error() {
    printf "\n%s 🛑 ERROR: \n" "$(log_time)"
    local parent_lineno="$1" # Line number of the error
    local message="$2"       # Error message
    local code="${3:-1}"     # Exit code
    if [[ -n "$message" ]]; then
        echo "kind-context: \"$KIND_CONTEXT\"; error on or near line ${parent_lineno}: ${message}"
    else
        echo "error on or near line ${parent_lineno}"
    fi
    exit "${code}"
}

# Header helper: Display section headers with formatting
header() {
    local title="🔆🔆🔆  $*  🔆🔆🔆 "

    local len=40
    if [[ ${#title} -gt $len ]]; then
        len=${#title}
    fi

    echo -e "\n\n  \033[1m${title}\033[0m"
    echo -n "━━━━━"
    printf '━%.0s' $(seq "$len")
    echo "━━━━━"
}

# Argument parser: Parses command-line arguments
parse_args() {
    while [[ -n "${1+xxx}" ]]; do
        case $1 in
        --operator-dir | -o)
            if [[ -z $2 || $2 == -* ]]; then
                error $LINENO "missing or invalid value for --operator-dir flag"
            fi
            OPERATOR_DIR=$2                                                                  # Set operator directory
            cd "$OPERATOR_DIR" || error $LINENO "could not find operating dir $OPERATOR_DIR" # if the directory isn't present, fail here
            shift 2
            ;;
        --debug-level | -d)
            if [[ "$2" != "info" && "$2" != "default" ]]; then
                error $LINENO "invalid value for --debug-level flag: '$2'. Allowed values are 'default' or 'info'."
            fi
            DEBUG_LEVEL=$2 # Set debug level
            shift 2
            ;;
        --kind-context | -k)
            if [[ -z $2 || $2 == -* ]]; then
                error $LINENO "missing value for --kind-context flag"
            fi
            KIND_CONTEXT=$2 # Set kind cluster context
            shift 2
            ;;
        --kind-config | -K)
            if [[ -z $2 || $2 == -* ]]; then
                error $LINENO "missing value for --kind-context flag"
            fi
            KIND_CONTEXT=$2 # Set kind configuration
            shift 2
            ;;
        --help | -h)
            help # Display help message
            ;;
        *) ;;
        esac
    done

    return 0
}

# Initialize cluster context: Set up a kind cluster
init_cluster_context() {
    header "Set Cluster"

    if kind get clusters | grep "$KIND_CONTEXT" -cq; then
        info "kind cluster \"$KIND_CONTEXT\" already present, deleting it..."
        kind delete cluster -n "$KIND_CONTEXT"
        ok "duplicate kind cluster \"$KIND_CONTEXT\" deleted successfully"
    fi

    info "creating cluster \"$KIND_CONTEXT\""
    kind create cluster -n "$KIND_CONTEXT" --config "$KIND_CONFIG" || error $LINENO "could not create cluster"

    ok "kind cluster \"$KIND_CONTEXT\" initiated successfully"
}

# Build and load operator images into the kind cluster
build_and_load_operator() {
    header "Build images"
    info "building operator image"
    docker build --build-arg ARCH="$ARCH" --build-arg GOARCH="$GOARCH" --build-arg OS="$GOOS" -t "$IMAGE_OPERATOR":"$TAG" . || error $LINENO "could not build operator image"
    ok "operator image built successfully"

    info "building reloader image"
    docker build --build-arg ARCH="$ARCH" --build-arg GOARCH="$GOARCH" --build-arg OS="$GOOS" -t "$IMAGE_RELOADER":"$TAG" -f cmd/prometheus-config-reloader/Dockerfile . || error $LINENO "could not build reloader image"
    ok "reloader image built successfully"

    info "building webhook image"
    docker build --build-arg ARCH="$ARCH" --build-arg GOARCH="$GOARCH" --build-arg OS="$GOOS" -t "$IMAGE_WEBHOOK":"$TAG" -f cmd/admission-webhook/Dockerfile . || error $LINENO "could not build webhook image"
    ok "webhook image built successfully"

    header "Load images"
    info "loading operator image into kind cluster \"$KIND_CONTEXT\""
    kind load docker-image -n "$KIND_CONTEXT" "$IMAGE_OPERATOR":"$TAG" || error $LINENO "could not load operator image into kind cluster"
    ok "operator image loaded into kind cluster \"$KIND_CONTEXT\""

    info "loading reloader image into kind cluster \"$KIND_CONTEXT\""
    kind load docker-image -n "$KIND_CONTEXT" "$IMAGE_RELOADER":"$TAG" || error $LINENO "could not load reloader image into kind cluster"
    ok "reloader image loaded into kind cluster \"$KIND_CONTEXT\""

    info "loading webhook image into kind cluster \"$KIND_CONTEXT\""
    kind load docker-image -n "$KIND_CONTEXT" "$IMAGE_WEBHOOK":"$TAG" || error $LINENO "could not load webhook image into kind cluster"
    ok "webhook image loaded into kind cluster \"$KIND_CONTEXT\""

    return 0
}

# Ensure no other Prometheus Operator is running in the cluster
ensure_operator_not_running() {
    header "Ensure no other prometheus-operator is running"

    $SKIP_OPERATOR_RUN_CHECK && {
        info "skipping operator run check"
        return 0
    }

    local po_label='app.kubernetes.io/name=prometheus-operator'

    local po_pods
    po_pods=$(kubectl get pods -A -l "$po_label" -o name | wc -l ||
        error $LINENO "could not get response from API server in kind cluster \"$KIND_CONTEXT\"")

    [[ "$po_pods" -gt 0 ]] && {
        info "If it is safe to continue, rerun the script with --skip-operator-check option"
        error $LINENO "running operator found in the cluster \"$KIND_CONTEXT\""
    }

    ok "no operators found, good to go!"

    return 0
}

# Deploy the Prometheus Operator bundle
deploy_operator() {
    header "Deploying the operator bundle"

    value=$(grep -e "$VERSION_LABEL" -m 1 bundle.yaml | sed "s/$VERSION_LABEL//" | xargs) || error $LINENO "could not find the current version of prometheus-operator"

    info "deploying prometheus-operator bundle into kind cluster \"$KIND_CONTEXT\""

    kubectl config use-context "kind-$KIND_CONTEXT" >/dev/null 2>&1
    kubectl create -f <(sed "/quay.io/s/v$value/$TAG/g" bundle.yaml) ||
        error $LINENO "could not deploy the prometheus-operator bundle to kind cluster \"$KIND_CONTEXT\""

    ok "operator deployed successfully to cluster \"$KIND_CONTEXT\""
}

# Tear down the kind cluster
tear_down() {
    info "tearing down cluster \"$KIND_CONTEXT\""
    kind delete cluster -n "$KIND_CONTEXT" || error $LINENO "could not tear down the kind cluster \"$KIND_CONTEXT\""
    ok "kind cluster \"$KIND_CONTEXT\" removed successfully"
    exit
}

# Check required dependencies
check_dependencies() {
    for cmd in kubectl docker kind; do
        command -v "$cmd" >/dev/null 2>&1 || error $LINENO "$cmd is required but not installed"
    done
}

# Display help message
help() {
    cat <<EOF
Usage: $0 [OPTIONS]

This script automates the setup and deployment of Prometheus Operator in a Kubernetes cluster created with kind.

OPTIONS:
  --multinode-cluster, -m        Enable multi-node cluster creation in kind.
  --skip-operator-check, -s      Skip the check for existing Prometheus Operator instances in the cluster.
  --operator-dir DIR, -o DIR     Specify the operator's working directory. Required to point to the directory containing the operator.
  --debug-level LEVEL, -d LEVEL  Set the debug level. Allowed values are "info" (default) or "debug".
  --kind-context CONTEXT, -k CONTEXT
                                 Set the name of the kind cluster context. Defaults to "test".
  --help, -h                     Display this help message.

EXAMPLES:
  1. Create a single-node kind cluster and deploy the operator:
     $0 --operator-dir /path/to/operator

  2. Create a multi-node cluster and skip existing operator checks:
     $0 --multinode-cluster --skip-operator-check --operator-dir /path/to/operator

  3. Use a specific kind cluster context with debug-level set to "debug":
     $0 --kind-context my-cluster --debug-level debug --operator-dir /path/to/operator

NOTES:
  - All required dependencies (e.g., kubectl, docker, kind) must be installed and accessible in PATH.
  - Ensure the working directory specified with --operator-dir contains the operator GitHub repository.
EOF
    exit
}

# Main function: Executes the script steps
main() {
    check_dependencies

    if [[ $# -gt 0 && $1 == "teardown" ]]; then
        tear_down
    fi

    parse_args "$@"
    init_cluster_context

    TAG=$(git rev-parse --short HEAD || echo "latest") # Get Git tag or use "latest"

    build_and_load_operator
    ensure_operator_not_running
    deploy_operator
}

main "$@"
