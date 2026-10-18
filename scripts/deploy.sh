#!/usr/bin/env bash
# Build the Poll application images, push them to ACR, and deploy them on the
# current kubectl context.
#
# Usage: ACR_NAME=<registry> [TAG=<tag>] [POSTGRES_PASSWORD=<pw>] scripts/deploy.sh
# Rollback to an existing tag: ACR_NAME=<registry> TAG=<old-tag> SKIP_BUILD=1 scripts/deploy.sh
#
# Prerequisites: az (logged in), docker, kubectl pointing at the AKS cluster,
# the cluster attached to the registry (az aks update --attach-acr).
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APPS="$ROOT/project-applications/poll-application"
NAMESPACE=bernstein
SERVICES=(poll worker result)

: "${ACR_NAME:?set ACR_NAME to the Azure Container Registry name (e.g. myregistry)}"
REGISTRY="$ACR_NAME.azurecr.io"

# One immutable tag per deployment: the git commit, or a timestamp before the
# first commit. Never "latest": an unchanged tag does not trigger a rollout.
if [[ -z "${TAG:-}" ]]; then
  if TAG="$(git -C "$ROOT" rev-parse --short HEAD 2>/dev/null)"; then
    [[ -n "$(git -C "$ROOT" status --porcelain)" ]] && TAG="$TAG-dirty-$(date +%s)"
  else
    TAG="build-$(date +%Y%m%d-%H%M%S)"
  fi
fi
export REGISTRY TAG

for cmd in az docker kubectl envsubst; do
  command -v "$cmd" >/dev/null || { echo "error: $cmd is not installed" >&2; exit 1; }
done
echo "==> Registry $REGISTRY, tag $TAG, cluster $(kubectl config current-context)"

if [[ "${SKIP_BUILD:-0}" == 1 ]]; then
  # Rollback / redeploy: reuse images already in the registry, never rebuild
  # (rebuilding would overwrite the old tag with the current source code).
  echo "==> Skip build, check that tag $TAG exists"
  for svc in "${SERVICES[@]}"; do
    az acr repository show -n "$ACR_NAME" --image "$svc:$TAG" >/dev/null \
      || { echo "error: $svc:$TAG is not in $REGISTRY" >&2; exit 1; }
  done
else
  echo "==> Build and push"
  az acr login --name "$ACR_NAME"
  for svc in "${SERVICES[@]}"; do
    docker build --platform linux/amd64 -t "$REGISTRY/$svc:$TAG" "$APPS/$svc"
    docker push "$REGISTRY/$svc:$TAG"
  done
fi

echo "==> Namespace and secret"
kubectl apply -f "$ROOT/k8s/00-namespace.yaml"
if ! kubectl get secret postgres-secret -n "$NAMESPACE" >/dev/null 2>&1; then
  : "${POSTGRES_PASSWORD:?secret postgres-secret is missing: set POSTGRES_PASSWORD for the first deployment}"
  kubectl create secret generic postgres-secret -n "$NAMESPACE" \
    --from-literal=POSTGRES_PASSWORD="$POSTGRES_PASSWORD"
fi

echo "==> Apply manifests"
# Only REGISTRY and TAG are substituted; any other "$" in the manifests is kept.
for file in "$ROOT"/k8s/*.yaml; do
  envsubst '${REGISTRY} ${TAG}' < "$file"
  printf '\n---\n'   # newline first: a file may lack a trailing one
done | kubectl apply -f -

echo "==> Wait for rollouts"
kubectl rollout status statefulset/postgres -n "$NAMESPACE" --timeout=300s
for deploy in redis "${SERVICES[@]}"; do
  kubectl rollout status "deployment/$deploy" -n "$NAMESPACE" --timeout=300s
done

echo "==> Public addresses (may take a minute on the first deployment)"
for svc in poll result; do
  ip=""
  for _ in $(seq 1 60); do
    ip="$(kubectl get svc "$svc" -n "$NAMESPACE" -o jsonpath='{.status.loadBalancer.ingress[0].ip}')"
    [[ -n "$ip" ]] && break
    sleep 5
  done
  echo "$svc: http://${ip:-<pending>}"
done
