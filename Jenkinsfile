// Deploy the Poll application from Jenkins ("Build with Parameters").
// Leave TAG empty to build and deploy the current commit; set TAG and tick
// ROLLBACK to redeploy an existing version without rebuilding.
//
// Steps run inside the tools image ci/Dockerfile (az, kubectl, envsubst, git),
// built by Jenkins with the Docker Pipeline plugin. Images are built by the
// host's Docker: its binary and socket are mounted, and 988 is the gid of the
// host "docker" group that owns the socket (stat -c %g /var/run/docker.sock).
// Jenkins credential "azure-deploy-sp" (Username with password):
//   username = service principal appId, password = its secret.
// Setup: docs/deployment-guide.md, step 13.
pipeline {
  agent {
    dockerfile {
      dir 'ci'
      args '-v /var/run/docker.sock:/var/run/docker.sock -v /usr/bin/docker:/usr/bin/docker --group-add 988'
    }
  }

  parameters {
    string(name: 'TAG', defaultValue: '', description: 'Image tag (empty = current commit)')
    booleanParam(name: 'ROLLBACK', defaultValue: false, description: 'Redeploy the existing TAG without rebuilding')
  }

  options {
    disableConcurrentBuilds()   // never two deployments at the same time
    timeout(time: 30, unit: 'MINUTES')
  }

  environment {
    AZURE_TENANT_ID       = '00000000-0000-0000-0000-000000000000'
    AZURE_SUBSCRIPTION_ID = '00000000-0000-0000-0000-000000000000'
    RESOURCE_GROUP        = 'bernstein-spain-rg'
    CLUSTER               = 'bernstein-aks'
    ACR_NAME              = 'myregistry'
    // Keep Azure and kubectl state per build, outside the agent's home and
    // outside the checkout (files there would make the git tag "-dirty").
    HOME                  = "${WORKSPACE}@tmp/home"   // uid 1000 has no home in the image
    AZURE_CONFIG_DIR      = "${WORKSPACE}@tmp/azure"
    KUBECONFIG            = "${WORKSPACE}@tmp/kube/config"
    DOCKER_CONFIG         = "${WORKSPACE}@tmp/docker"  // ACR login token
  }

  stages {
    stage('Check parameters') {
      steps {
        sh '''#!/bin/bash
          set -euo pipefail
          mkdir -p "$HOME"
          # Parameters do not exist yet on the very first build of the job
          # (Jenkins discovers them from this file), hence the defaults.
          TAG="${TAG:-}"; ROLLBACK="${ROLLBACK:-false}"
          if [ "$ROLLBACK" = true ] && [ -z "$TAG" ]; then
            echo "A rollback needs the TAG to redeploy" >&2; exit 1
          fi
          # The tag ends up in image names: only allow characters valid there.
          if [ -n "$TAG" ] && ! [[ "$TAG" =~ ^[A-Za-z0-9_][A-Za-z0-9_.-]{0,127}$ ]]; then
            echo "Invalid TAG: $TAG" >&2; exit 1
          fi
        '''
      }
    }

    stage('Azure login') {
      steps {
        withCredentials([usernamePassword(credentialsId: 'azure-deploy-sp',
                                          usernameVariable: 'AZURE_CLIENT_ID',
                                          passwordVariable: 'AZURE_CLIENT_SECRET')]) {
          sh '''#!/bin/bash
            set -euo pipefail
            az login --service-principal -u "$AZURE_CLIENT_ID" -p "$AZURE_CLIENT_SECRET" \
              --tenant "$AZURE_TENANT_ID" -o none
            az account set --subscription "$AZURE_SUBSCRIPTION_ID"
          '''
        }
      }
    }

    stage('Start cluster if stopped') {
      steps {
        sh '''#!/bin/bash
          set -euo pipefail
          state="$(az aks show -g "$RESOURCE_GROUP" -n "$CLUSTER" --query powerState.code -o tsv)"
          echo "Cluster power state: $state"
          if [ "$state" = Stopped ]; then az aks start -g "$RESOURCE_GROUP" -n "$CLUSTER" -o none; fi
          az aks get-credentials -g "$RESOURCE_GROUP" -n "$CLUSTER" --overwrite-existing
        '''
      }
    }

    stage('Deploy') {
      steps {
        sh '''#!/bin/bash
          set -euo pipefail
          export TAG="${TAG:-}" SKIP_BUILD=0
          if [ "${ROLLBACK:-false}" = true ]; then SKIP_BUILD=1; fi
          # Only used if the postgres-secret Secret does not exist yet (first
          # deployment on a fresh cluster); it then lives only in Kubernetes.
          POSTGRES_PASSWORD="$(openssl rand -hex 24)"
          export POSTGRES_PASSWORD
          scripts/deploy.sh
        '''
      }
    }
  }

  post {
    success {
      sh '''#!/bin/bash
        echo "Deployed image: $(kubectl get deploy poll -n bernstein -o jsonpath='{.spec.template.spec.containers[0].image}')"
      '''
    }
    always {
      // Do not leave Azure or cluster credentials on the agent.
      sh 'az logout || true; rm -rf "$AZURE_CONFIG_DIR" "$(dirname "$KUBECONFIG")" "$DOCKER_CONFIG" "$HOME"'
    }
  }
}
