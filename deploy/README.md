# Deploy to Kubernetes from the container runner

The self-hosted GitHub Actions runner can deploy `hongsait/cpsy-350-ci-python`
directly with `kubectl` when the runner container runs on a private network that
can reach the Kubernetes API server.

This repository includes a dedicated deploy service account for the
`self-hosted` namespace:

- ServiceAccount: `self-hosted/cicd-demo-deployer`
- Role: `self-hosted/cicd-demo-deployer`
- RoleBinding: `self-hosted/cicd-demo-deployer`
- Target deployment: `deployment.apps/cicd-demo-deployment`
- Target service: `service/cicd-demo-service`
- Target container: `cicd-demo`

The Role is intentionally narrow. It grants only `get`, `patch`, `update`, and
`watch` on `deployment.apps/cicd-demo-deployment`, plus `get`, `patch`, and
`update` on `service/cicd-demo-service`, in the `self-hosted` namespace.
It does not grant `create` or `delete`, so the deployment and service must
already exist before this account can apply updates.

## Apply the RBAC

```bash
kubectl apply -f deploy/cicd-demo-deployer-rbac.yaml
```

Verify the effective permissions:

```bash
kubectl auth can-i patch deployment/cicd-demo-deployment \
  -n self-hosted \
  --as system:serviceaccount:self-hosted:cicd-demo-deployer

kubectl auth can-i patch deployment/searxng-deployment \
  -n self-hosted \
  --as system:serviceaccount:self-hosted:cicd-demo-deployer

kubectl auth can-i patch service/cicd-demo-service \
  -n self-hosted \
  --as system:serviceaccount:self-hosted:cicd-demo-deployer
```

The first and third commands should print `yes`; the second should print `no`.

## Create a kubeconfig for the runner

Create a token for the deploy service account:

```bash
TOKEN="$(kubectl -n self-hosted create token cicd-demo-deployer --duration=8760h)"
CLUSTER_NAME="$(kubectl config view --minify -o jsonpath='{.clusters[0].name}')"
SERVER="$(kubectl config view --minify -o jsonpath='{.clusters[0].cluster.server}')"
CA_DATA="$(kubectl config view --raw --minify -o jsonpath='{.clusters[0].cluster.certificate-authority-data}')"
printf '%s' "$CA_DATA" | base64 -d > ./runner-ca.crt
```

Write a kubeconfig that uses that token:

```bash
kubectl config set-cluster "$CLUSTER_NAME" \
  --server="$SERVER" \
  --certificate-authority=./runner-ca.crt \
  --embed-certs=true \
  --kubeconfig ./runner-kubeconfig

kubectl config set-credentials cicd-demo-deployer \
  --token="$TOKEN" \
  --kubeconfig ./runner-kubeconfig

kubectl config set-context cicd-demo-deployer \
  --cluster="$CLUSTER_NAME" \
  --user=cicd-demo-deployer \
  --namespace=self-hosted \
  --kubeconfig ./runner-kubeconfig

kubectl config use-context cicd-demo-deployer \
  --kubeconfig ./runner-kubeconfig

rm ./runner-ca.crt
```

Store this kubeconfig outside the repository and mount it read-only into the
runner container.

The kubeconfig must be readable by the `runner` user inside the container. The
official runner image uses UID/GID `1001` for that user:

```bash
sudo chown 1001:1001 ./runner-kubeconfig
chmod 0400 ./runner-kubeconfig
```

After restarting the container, verify the mounted file from inside the runner:

```bash
docker exec github-actions-runner \
  runuser --user runner -- kubectl config current-context
```

Mount `cicd-demo.yaml` read-only too if the workflow should apply the checked
deployment manifest from the runner host instead of from the application
repository.

## Mount the kubeconfig into the runner

Add the kubeconfig mount to `docker-compose.yml`:

```yaml
services:
  github-runner:
    volumes:
      - ./runner-state:/runner-state
      - runner-work:/home/runner/_work
      - /var/run/docker.sock:/var/run/docker.sock
      - ./runner-kubeconfig:/home/runner/.kube/config:ro
      - ./deploy/cicd-demo.yaml:/home/runner/deploy/cicd-demo.yaml:ro
```

The runner image also needs `kubectl` installed. Pin the `kubectl` version close
to the Kubernetes control plane version.

## GitHub Actions image tags and deployment

Push both an immutable commit tag and the moving `latest` tag. The immutable tag
uses the first 12 characters of `github.sha`, which is short enough to read but
still tied to a specific commit.

```yaml
env:
  IMAGE_NAME: hongsait/cpsy-350-ci-python

push_to_dockerhub:
  needs: build_and_test
  name: Push OCI image to Docker Hub
  runs-on: [self-hosted, docker]

  steps:
    - uses: actions/checkout@v6

    - name: Set image tag
      id: image
      run: echo "tag=${GITHUB_SHA::12}" >> "$GITHUB_OUTPUT"

    - name: Log in to Docker Hub
      uses: docker/login-action@v4
      with:
        username: ${{ secrets.DOCKERHUB_USERNAME }}
        password: ${{ secrets.DOCKERHUB_PASSWORD }}

    - name: Build and push Docker image
      uses: docker/build-push-action@v6
      with:
        context: .
        push: true
        tags: |
          ${{ env.IMAGE_NAME }}:${{ steps.image.outputs.tag }}
          ${{ env.IMAGE_NAME }}:latest

deploy_to_k8s:
  needs: push_to_dockerhub
  name: Deploy the OCI image to K8s cluster
  runs-on: [self-hosted, docker]

  steps:
    - name: Set image tag
      id: image
      run: echo "tag=${GITHUB_SHA::12}" >> "$GITHUB_OUTPUT"

    - name: Deploy to Kubernetes
      run: |
        kubectl apply -f /home/runner/deploy/cicd-demo.yaml
        kubectl -n self-hosted set image deployment/cicd-demo-deployment \
          cicd-demo=${{ env.IMAGE_NAME }}:${{ steps.image.outputs.tag }}
        kubectl -n self-hosted rollout status deployment/cicd-demo-deployment --timeout=300s
```

Use GitHub expression syntax, such as `${{ env.IMAGE_NAME }}`, inside action
inputs like `with.tags`. Shell syntax like `$IMAGE_NAME` only expands inside
`run` steps.

## Deploying latest

If you deploy `:latest` instead of the immutable commit tag, keep
`rollout restart`. When the tag value is already `latest`, `kubectl set image`
does not change the pod template, so Kubernetes does not create replacement
Pods. The restart forces a pod-template annotation change, creates a new
ReplicaSet, and pulls the image again.

```bash
kubectl -n self-hosted set image deployment/cicd-demo-deployment \
  cicd-demo=hongsait/cpsy-350-ci-python:latest
kubectl -n self-hosted rollout restart deployment/cicd-demo-deployment
kubectl -n self-hosted rollout status deployment/cicd-demo-deployment --timeout=300s
```

## Security notes

- Mount the kubeconfig read-only.
- Do not use a cluster-admin kubeconfig in the runner.
- Keep the runner restricted to trusted repositories and trusted workflows.
- The existing Docker socket mount is root-equivalent access to the Docker host,
  so this runner should not process untrusted pull requests.
