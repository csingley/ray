#!/bin/bash
# shellcheck disable=SC2086
# This script is for users to build docker images locally. It is most useful for users wishing to edit the
# base-deps, or ray images. This script is *not* tested.

GPU=""
# WHEEL_URL="https://s3-us-west-2.amazonaws.com/ray-wheels/latest/ray-3.0.0.dev0-cp39-cp39-manylinux2014_x86_64.whl"
# CPP_WHEEL_URL="https://s3-us-west-2.amazonaws.com/ray-wheels/latest/ray_cpp-3.0.0.dev0-cp39-cp39-manylinux2014_x86_64.whl"
DOCKER_PROJECT="harbor.thefacebook.com/arc/rayproject"
LOCAL_CHECKOUT="${HOME}/Code/ray"
WHEEL_URL="file://${LOCAL_CHECKOUT}/.whl/ray-3.0.0.dev0-cp39-cp39-manylinux2014_x86_64.whl"
CPP_WHEEL_URL="file://${LOCAL_CHECKOUT}/.whl/ray_cpp-3.0.0.dev0-cp39-cp39-manylinux2014_x86_64.whl"
BASE_IMAGE="ubuntu:22.04"
PYTHON_VERSION="3.9"

BUILD_ARGS=()

while [[ $# -gt 0 ]]; do
    case "$1" in
        --gpu)
            GPU="-gpu"
            BASE_IMAGE="nvidia/cuda:11.8.0-cudnn8-devel-ubuntu22.04"
        ;;
        --base-image)
            # Override for the base image.
            shift
            BASE_IMAGE="$1"
        ;;
        --no-cache-build)
            BUILD_ARGS+=("--no-cache")
        ;;
        --shas-only)
            # output the SHA sum of each build. This is useful for scripting tests,
            # especially when builds of different versions are running on the same machine.
            # It also can facilitate cleanup.
            OUTPUT_SHA=YES
            BUILD_ARGS+=("-q")
        ;;
        --python-version)
            # Python version to install. e.g. 3.9
            # Changing python versions may require a different wheel.
            # If not provided defaults to 3.9
            shift
            PYTHON_VERSION="$1"
        ;;
        *)
            echo "Usage: build-docker.sh [ --gpu ] [ --base-image ] [ --no-cache-build ] [ --shas-only ] [ --build-development-image ] [ --build-examples ] [ --python-version ]"
            exit 1
    esac
    shift
done

export DOCKER_BUILDKIT=1

# Build base-deps image
if [[ "$OUTPUT_SHA" != "YES" ]]; then
    echo "=== Building base-deps image ===" >/dev/stderr
fi

BASE_DEPS_TAG="${DOCKER_PROJECT}/base-deps0:dev$GPU"
BUILD_CMD=(
    podman build "${BUILD_ARGS[@]}"
    --format=docker
    --network=host
    --build-arg BASE_IMAGE="$BASE_IMAGE"
    --build-arg PYTHON_VERSION="${PYTHON_VERSION}"
    -t "${BASE_DEPS_TAG}" "docker/base-deps"
)

IMAGE_SHA="$("${BUILD_CMD[@]}")"
if [[ "$OUTPUT_SHA" == "YES" ]]; then
    echo "${BASE_DEPS_TAG} SHA:$IMAGE_SHA"
fi

# Build ray image
if [[ "$OUTPUT_SHA" != "YES" ]]; then
    echo "=== Building ray image ===" >/dev/stderr
fi

RAY_BUILD_DIR="$(mktemp -d)"
mkdir -p "$RAY_BUILD_DIR/.whl"
curl --silent --show-error --output-dir "$RAY_BUILD_DIR/.whl" --remote-name-all "$WHEEL_URL" "$CPP_WHEEL_URL"
cp python/requirements_compiled.txt "$RAY_BUILD_DIR"
cp docker/ray/Dockerfile "$RAY_BUILD_DIR"

WHEEL="$(basename "$RAY_BUILD_DIR"/.whl/ray-*.whl)"

RAY_TAG="${DOCKER_PROJECT}/ray:dev0$GPU"
BUILD_CMD=(
    podman build "${BUILD_ARGS[@]}"
    --format=docker
    --network=host
    --build-arg FULL_BASE_IMAGE="rayproject/base-deps:dev$GPU"
    --build-arg WHEEL_PATH=".whl/${WHEEL}"
    -t "${RAY_TAG}" "$RAY_BUILD_DIR"
)

IMAGE_SHA="$("${BUILD_CMD[@]}")"
if [[ "$OUTPUT_SHA" == "YES" ]]; then
    echo "${RAY_TAG} SHA:$IMAGE_SHA"
fi

rm -rf "$RAY_BUILD_DIR"
