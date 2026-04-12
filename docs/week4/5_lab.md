# Lab

실습 스크립트와 매니페스트는 [:octicons-mark-github-16: labs/week4/](https://github.com/pyy0715/eks-pratice/tree/main/labs/week4) 디렉터리를 참고하세요.

이 실습은 `myeks` 클러스터(Terraform)에서 진행합니다. [Operator Authentication](2_operator-auth.md)의 Token/Access Entry 흐름, [RBAC](3_rbac.md)의 Role/ClusterRole, [Pod Workload Identity](4_pod-workload-identity.md)의 IRSA와 Pod Identity를 순차적으로 실습합니다. 동일한 S3 버킷에 대해 IRSA와 Pod Identity를 각각 적용한 뒤 환경변수, 토큰 경로, Trust Policy를 비교합니다.

Week 3과 달리 `authentication_mode = "API"` (Access Entry 전용)로 클러스터를 생성하고, AWS LBC는 Terraform `helm_release`로 배포하며, ExternalDNS는 node role 대신 Pod Identity로 권한을 부여합니다.

---

## Environment Setup

### Terraform Deploy

Week 3와 동일하게 노드가 private subnet에 배치됩니다. 이번 주는 Terraform에 `helm`/`kubernetes` provider가 추가되어 AWS LBC를 `helm_release`로 직접 배포합니다. 스케일링 관련 리소스(Karpenter, CAS, optional node group)는 포함되지 않습니다.

```bash
cd labs/week4
terraform init && terraform apply -auto-approve
```

!!! warning "Initial Apply"
    `helm`/`kubernetes` provider가 EKS 클러스터 endpoint에 의존합니다. 첫 apply에서 클러스터 생성 후 LBC Helm chart 설치까지 20분 이상 소요될 수 있습니다. provider 초기화 에러가 발생하면 `terraform apply -target=module.eks`로 클러스터를 먼저 생성한 뒤 `terraform apply`를 다시 실행하세요.

### Configure kubectl

```bash
eval $(terraform output -raw configure_kubectl)
kubectl config rename-context $(kubectl config current-context) myeks
kubectl get node -owide
```

### Verify Addons

```bash
aws eks list-addons --cluster-name myeks | jq
```

=== "LBC (Helm + IRSA)"

    Terraform `helm_release`로 배포된 AWS Load Balancer Controller를 확인합니다. Week 2-3의 shell script 방식과 달리 Terraform이 IRSA role annotation까지 함께 설정합니다.

    ```bash
    kubectl get deploy -n kube-system aws-load-balancer-controller
    helm list -n kube-system
    ```

=== "ExternalDNS (Pod Identity)"

    ExternalDNS는 EKS addon으로 설치되며, Week 3의 node role 방식 대신 Pod Identity로 Route53 권한을 부여받습니다.

    ```bash
    kubectl get pod -n external-dns -l app.kubernetes.io/name=external-dns \
      -o jsonpath='{.items[0].spec.containers[0].env}' | jq

    aws eks list-pod-identity-associations --cluster-name myeks \
      --query 'associations[?serviceAccount==`external-dns`]' | jq
    ```

=== "SSM Access"

    노드에 SSH 대신 SSM Session Manager로 접근합니다.

    ```bash
    aws ssm describe-instance-information \
      --query "InstanceInformationList[*].{InstanceId:InstanceId, Status:PingStatus, OS:PlatformName}" \
      --output table
    ```

### Environment Variables

이후 모든 실습에서 사용할 환경변수를 설정합니다.

```bash
source labs/week4/00_env.sh
```

---

## Operator Authentication

[Operator Authentication and Authorization](2_operator-auth.md)에서 다룬 Token → TokenReview → Access Entry 흐름을 직접 확인합니다.

### Token Structure

`aws eks get-token`은 STS `GetCallerIdentity`의 Pre-signed URL을 base64 인코딩한 Bearer token을 생성합니다. 이 토큰을 디코딩하여 서명 범위에 클러스터 이름이 포함되는 구조를 확인합니다.

```bash
TOKEN=$(aws eks get-token --cluster-name myeks --query 'status.token' --output text)

# k8s-aws-v1. 접두사 제거 후 base64 decode → Pre-signed URL
echo $TOKEN | sed 's/k8s-aws-v1\.//' | base64 -d \
  | python3 -c "import sys,urllib.parse; print(urllib.parse.unquote(sys.stdin.read()))"
```

???+ info "Pre-signed URL Structure"
    디코딩된 URL에서 다음 파라미터를 확인할 수 있습니다.

    `x-k8s-aws-id=myeks`
    :   클러스터 이름이 서명 범위에 포함됩니다. 다른 클러스터에 같은 토큰을 제출해도 서명 검증에 실패하므로 cross-cluster 토큰 재사용이 방지됩니다.

    `X-Amz-Expires=60`
    :   Pre-signed URL 자체는 60초간 유효합니다. 그러나 aws-iam-authenticator가 부여하는 토큰 TTL은 15분이며, kubectl은 만료 시 자동으로 새 토큰을 생성합니다.

    `X-Amz-Credential`
    :   IAM Access Key ID, 날짜, 리전, `sts` 서비스 스코프가 포함됩니다.

생성한 Bearer token으로 클러스터 API를 직접 호출합니다.

```bash
curl -sk -H "Authorization: Bearer $TOKEN" \
  $(terraform output -raw cluster_endpoint)/api/v1/namespaces \
  | jq '.items[].metadata.name'
```

### Access Entry and Viewer Role Test

`authentication_mode = "API"`로 생성한 클러스터는 Access Entry만으로 IAM principal과 Kubernetes 권한을 매핑합니다. Terraform에서 Viewer role에 `AmazonEKSViewPolicy`를 연결했으므로 이를 확인하고, 실제로 assume하여 권한 경계를 테스트합니다.

=== "Access Entry Inspection"

    ```bash
    aws eks list-access-entries --cluster-name myeks | jq

    aws eks describe-access-entry --cluster-name myeks \
      --principal-arn $VIEWER_ROLE_ARN | jq

    aws eks list-associated-access-policies --cluster-name myeks \
      --principal-arn $VIEWER_ROLE_ARN | jq
    ```

=== "Viewer Role Assume"

    ```bash
    aws sts assume-role --role-arn $VIEWER_ROLE_ARN --role-session-name viewer-test \
      --query 'Credentials' --output json > /tmp/viewer-creds.json

    export AWS_ACCESS_KEY_ID=$(jq -r '.AccessKeyId' /tmp/viewer-creds.json)
    export AWS_SECRET_ACCESS_KEY=$(jq -r '.SecretAccessKey' /tmp/viewer-creds.json)
    export AWS_SESSION_TOKEN=$(jq -r '.SessionToken' /tmp/viewer-creds.json)

    aws eks update-kubeconfig --name myeks --alias myeks-viewer
    kubectl config use-context myeks-viewer
    ```

=== "Permission Check"

    ```bash
    # 읽기 — 허용 (AmazonEKSViewPolicy = view ClusterRole)
    kubectl get pods -A
    kubectl get nodes

    # 쓰기 — 거부 (403 Forbidden)
    kubectl run test --image=nginx
    ```

=== "Cleanup"

    ```bash
    unset AWS_ACCESS_KEY_ID AWS_SECRET_ACCESS_KEY AWS_SESSION_TOKEN
    kubectl config use-context myeks
    kubectl config delete-context myeks-viewer
    ```

???+ info "ConfigMap vs Access Entry"
    EKS는 두 가지 IAM-to-K8s 매핑 방식을 지원합니다. `aws-auth` ConfigMap은 deprecated 상태이며, Access Entry가 권장됩니다.

    | 항목 | aws-auth ConfigMap | Access Entry (EKS API) |
    |---|---|---|
    | **Data store** | etcd (K8s ConfigMap) | EKS managed (AWS API) |
    | **Management** | `kubectl edit` | `aws eks` CLI / Terraform |
    | **Recovery** | ConfigMap 삭제 시 lockout 위험 | AWS API로 복구 가능 |
    | **Audit** | K8s audit log만 | CloudTrail 통합 |
    | **Status** | Deprecated | Recommended |

    이 lab에서는 `authentication_mode = "API"`로 ConfigMap을 완전히 비활성화했습니다. mode 전환은 `CONFIG_MAP` → `API_AND_CONFIG_MAP` → `API` 단방향만 가능합니다.

`enabled_log_types = ["authenticator"]`로 활성화한 인증 로그에서 TokenReview 결과도 확인할 수 있습니다.

```bash
aws logs filter-log-events --log-group-name /aws/eks/myeks/cluster \
  --log-stream-name-prefix "authenticator" \
  --filter-pattern "access granted" \
  --limit 5 | jq '.events[].message'
```

---

## RBAC

[Kubernetes RBAC](3_rbac.md)에서 다룬 Role, ClusterRole, RoleBinding을 생성하고, Pod 내부에서 ServiceAccount Token으로 Kubernetes API를 호출하여 허용/거부를 확인합니다.

### Deploy and Verify

```bash
kubectl apply -f labs/week4/manifests/rbac/
```

| Resource | Name | Scope |
|---|---|---|
| Namespace | `dev-team` | — |
| ServiceAccount | `dev-k8s` | `dev-team` |
| Role | `pod-reader` | `dev-team` — pods get/list/watch |
| RoleBinding | `dev-k8s-pod-reader` | `dev-k8s` → `pod-reader` |
| ClusterRole | `node-viewer` | nodes get/list |
| ClusterRoleBinding | `node-viewer-binding` | `dev-k8s` → `node-viewer` |
| Pod | `rbac-test` | `dev-team` — curl image |

`kubectl create token`으로 SA Token을 생성하고 JWT payload를 디코딩합니다.

```bash
SA_TOKEN=$(kubectl create token dev-k8s -n dev-team --duration=1h)
echo $SA_TOKEN | cut -d. -f2 | base64 -d 2>/dev/null | jq
```

???+ info "Projected Token JWT Payload"
    디코딩된 payload에서 다음 필드를 확인할 수 있습니다.

    `iss`
    :   OIDC issuer URL. EKS 클러스터의 `https://oidc.eks.<region>.amazonaws.com/id/<id>` 형식입니다.

    `sub`
    :   `system:serviceaccount:dev-team:dev-k8s` — namespace와 SA 이름이 포함됩니다.

    `aud`
    :   `["https://kubernetes.default.svc"]` — Kubernetes API 전용 audience입니다. IRSA 토큰의 `sts.amazonaws.com`이나 Pod Identity 토큰의 `pods.eks.amazonaws.com`과 구분됩니다.

### K8s API Call from Inside Pod

`rbac-test` Pod 내부에서 마운트된 SA Token으로 Kubernetes API를 직접 호출합니다. Role(namespace-scoped)과 ClusterRole(cluster-scoped)의 권한 경계를 확인합니다.

```bash
kubectl exec -it rbac-test -n dev-team -- sh
```

```bash
TOKEN=$(cat /var/run/secrets/kubernetes.io/serviceaccount/token)
APISERVER=https://kubernetes.default.svc
CACERT=/var/run/secrets/kubernetes.io/serviceaccount/ca.crt

# dev-team namespace pods — 허용 (pod-reader Role)
curl -s --cacert $CACERT -H "Authorization: Bearer $TOKEN" \
  $APISERVER/api/v1/namespaces/dev-team/pods | head -c 200

# default namespace pods — 거부 (Role은 dev-team에만 바인딩)
curl -s --cacert $CACERT -H "Authorization: Bearer $TOKEN" \
  $APISERVER/api/v1/namespaces/default/pods

# nodes — 허용 (node-viewer ClusterRole)
curl -s --cacert $CACERT -H "Authorization: Bearer $TOKEN" \
  $APISERVER/api/v1/nodes | head -c 200

# secrets — 거부 (권한 없음)
curl -s --cacert $CACERT -H "Authorization: Bearer $TOKEN" \
  $APISERVER/api/v1/namespaces/dev-team/secrets
```

`exit`로 Pod shell에서 나옵니다.

---

## Baseline: Pod without ServiceAccount

IRSA와 Pod Identity를 설정하기 전에 baseline을 확인합니다. `automountServiceAccountToken: false`로 설정하면 Pod에 K8s SA 토큰이 마운트되지 않고, IRSA/Pod Identity webhook도 credential을 주입하지 않습니다.

```bash
cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: Pod
metadata:
  name: eks-iam-test-no-sa
spec:
  automountServiceAccountToken: false
  containers:
    - name: aws-cli
      image: amazon/aws-cli:latest
      args: ['s3', 'ls']
  restartPolicy: Never
  terminationGracePeriodSeconds: 0
EOF

kubectl get pod eks-iam-test-no-sa
kubectl logs eks-iam-test-no-sa
kubectl delete pod eks-iam-test-no-sa
```

SA 토큰이 없으므로 SDK는 credential chain의 마지막 단계인 EC2 IMDS까지 내려갑니다. `http_put_response_hop_limit = 2`이므로 IMDS 접근 자체는 가능하지만, node role에 S3 권한이 없으면 `AccessDenied`가 발생합니다. Pod 단위 자격 증명(IRSA/Pod Identity) 없이 node role에 의존할 때의 위험입니다.

---

## IRSA (S3 Access)

[Pod Workload Identity](4_pod-workload-identity.md)의 IRSA 절에서 다룬 OIDC Federation → `AssumeRoleWithWebIdentity` 흐름을 S3 접근으로 실습합니다. Terraform에서 IRSA role의 Trust Policy를 raw `aws_iam_role`로 정의하여 OIDC 조건(`sub`, `aud`)이 명시적으로 드러나도록 구성했습니다.

### OIDC and Trust Policy

EKS 클러스터의 OIDC Provider 엔드포인트에서 메타데이터와 공개키를 확인하고, Trust Policy 구조를 검사합니다.

```bash
# OIDC discovery endpoint
curl -s $OIDC_ISSUER/.well-known/openid-configuration | jq

# JWKS (RSA 공개키 — STS가 토큰 서명 검증에 사용)
curl -s $OIDC_ISSUER/keys | jq

# Trust Policy 확인
aws iam get-role --role-name ${CLUSTER_NAME}-irsa-s3-role \
  --query 'Role.AssumeRolePolicyDocument' | jq
```

???+ info "IRSA Trust Policy Structure"
    Trust Policy의 핵심 요소:

    `Principal.Federated`
    :   EKS OIDC Provider의 IAM ARN. STS가 이 OIDC issuer가 서명한 토큰만 수락합니다.

    `Action: sts:AssumeRoleWithWebIdentity`
    :   OIDC 토큰을 IAM 임시 자격 증명으로 교환하는 STS 동작입니다.

    `Condition.StringEquals` — `sub`
    :   `system:serviceaccount:default:s3-irsa-sa` — 특정 namespace의 특정 SA만 이 role을 assume할 수 있습니다.

    `Condition.StringEquals` — `aud`
    :   `sts.amazonaws.com` — audience가 STS인 토큰만 허용합니다.

### Deploy and Verify

SA를 배포하면 Pod Identity Webhook이 Pod spec에 `AWS_ROLE_ARN`, `AWS_WEB_IDENTITY_TOKEN_FILE` 환경변수와 `aws-iam-token` projected volume을 추가합니다.

```bash
envsubst < labs/week4/manifests/irsa/s3-irsa-sa.yaml | kubectl apply -f -
kubectl apply -f labs/week4/manifests/irsa/s3-irsa-pod.yaml
kubectl wait --for=condition=Ready pod/s3-irsa-test --timeout=60s

# Webhook이 주입한 환경변수 확인
kubectl get pod s3-irsa-test -o yaml | grep -A2 'AWS_ROLE_ARN\|AWS_WEB_IDENTITY_TOKEN_FILE'

# Projected volume 확인
kubectl get pod s3-irsa-test -o yaml | grep -A5 'aws-iam-token'

# AWS API 호출
kubectl exec s3-irsa-test -- aws sts get-caller-identity
kubectl exec s3-irsa-test -- aws s3 ls s3://$S3_BUCKET
kubectl exec s3-irsa-test -- sh -c "echo 'hello from irsa' | aws s3 cp - s3://$S3_BUCKET/irsa-test.txt"
kubectl exec s3-irsa-test -- aws s3 cp s3://$S3_BUCKET/irsa-test.txt -
```

IRSA 전용 projected volume의 토큰을 디코딩하면 `aud`가 `["sts.amazonaws.com"]`입니다. 이 토큰은 STS에서만 유효하며, K8s API나 EKS Auth API에 제출하면 audience 불일치로 거부됩니다.

```bash
kubectl exec s3-irsa-test -- cat /var/run/secrets/eks.amazonaws.com/serviceaccount/token \
  | cut -d. -f2 | base64 -d 2>/dev/null | jq
```

=== "LBC IRSA Verification"

    Terraform `helm_release`로 배포된 AWS LBC도 동일한 IRSA 메커니즘으로 동작합니다.

    ```bash
    kubectl get pod -n kube-system -l app.kubernetes.io/name=aws-load-balancer-controller \
      -o jsonpath='{.items[0].spec.containers[0].env}' | jq

    kubectl exec -n kube-system \
      $(kubectl get pod -n kube-system -l app.kubernetes.io/name=aws-load-balancer-controller -o name | head -1) \
      -- env | grep AWS_ROLE_ARN
    ```

=== "CloudTrail: AssumeRoleWithWebIdentity"

    IRSA를 통한 AWS API 호출은 CloudTrail에 `AssumeRoleWithWebIdentity` 이벤트로 기록됩니다. `eventSource`는 `sts.amazonaws.com`입니다.

    ```bash
    aws cloudtrail lookup-events \
      --lookup-attributes AttributeKey=EventName,AttributeValue=AssumeRoleWithWebIdentity \
      --max-items 1 | jq '.Events[] | (.CloudTrailEvent | fromjson) | {
        eventName,
        eventSource,
        userIdentity: .userIdentity.type,
        principal: .userIdentity.userName,
        roleArn: .requestParameters.roleArn,
        audience: .responseElements.audience
      }'
    ```

---

## Pod Identity (S3 Access)

[Pod Workload Identity](4_pod-workload-identity.md)의 Pod Identity 절에서 다룬 eks-pod-identity-agent → EKS Auth API → `AssumeRoleForPodIdentity` 흐름을 실습합니다. IRSA와 동일한 S3 버킷에 접근하되, OIDC 등록 없이 `pods.eks.amazonaws.com` Service principal을 Trust Policy에 사용합니다.

### Pod Identity Agent

Pod Identity는 각 노드에서 실행되는 `eks-pod-identity-agent` DaemonSet이 필요합니다. `hostNetwork: true`로 실행되며, link-local 주소 `169.254.170.23:80`에서 credential endpoint를, `:2703`에서 health check를 제공합니다.

```bash
kubectl get ds -n kube-system eks-pod-identity-agent
kubectl get pod -n kube-system -l app.kubernetes.io/name=eks-pod-identity-agent -owide
kubectl get ds -n kube-system eks-pod-identity-agent \
  -o jsonpath='{.spec.template.spec.containers[0].ports}' | jq
```

Agent가 토큰을 수신하면 EKS Auth API의 `AssumeRoleForPodIdentity`를 호출합니다. 이때 노드의 IAM role에 `eks-auth:AssumeRoleForPodIdentity` 권한이 필요하며, `AmazonEKSWorkerNodePolicy`에 포함되어 있습니다.

### Pod Identity Association and Trust Policy

Association은 EKS API에 저장되며(K8s etcd가 아님), namespace + ServiceAccount와 IAM role을 매핑합니다. IRSA의 Trust Policy와 비교하면 `Principal`이 OIDC issuer ARN 대신 `pods.eks.amazonaws.com` Service로 바뀌고, `Condition` 블록이 없습니다.

```bash
# Association 목록 확인
aws eks list-pod-identity-associations --cluster-name myeks | jq

# Trust Policy 확인 — pods.eks.amazonaws.com Service principal
aws iam get-role --role-name ${CLUSTER_NAME}-pod-identity-s3-role \
  --query 'Role.AssumeRolePolicyDocument' | jq
```

???+ info "Pod Identity Association Fields"
    `list-pod-identity-associations` 응답의 주요 필드:

    `associationId`
    :   Association의 고유 ID. 클러스터당 최대 5,000개까지 생성할 수 있습니다.

    `namespace` + `serviceAccount`
    :   이 조합에 매칭되는 Pod에 credential이 주입됩니다.

    `ownerArn`
    :   Association을 생성한 주체의 ARN. EKS addon이 생성한 경우 addon ARN이 표시됩니다.

### Deploy and Verify

SA를 배포하면 Pod Identity Webhook이 `AWS_CONTAINER_CREDENTIALS_FULL_URI=http://169.254.170.23/v1/credentials`와 `AWS_CONTAINER_AUTHORIZATION_TOKEN_FILE`을 주입합니다. IRSA와 달리 SA에 annotation이 필요 없습니다.

```bash
kubectl apply -f labs/week4/manifests/pod-identity/
kubectl wait --for=condition=Ready pod/s3-pod-identity-test --timeout=60s

# Webhook이 주입한 환경변수 확인
kubectl get pod s3-pod-identity-test -o yaml \
  | grep -A2 'AWS_CONTAINER_CREDENTIALS_FULL_URI\|AWS_CONTAINER_AUTHORIZATION_TOKEN_FILE'

# AWS API 호출 — session tags 포함
kubectl exec s3-pod-identity-test -- aws sts get-caller-identity | jq
kubectl exec s3-pod-identity-test -- aws s3 ls s3://$S3_BUCKET
kubectl exec s3-pod-identity-test -- sh -c \
  "echo 'hello from pod-identity' | aws s3 cp - s3://$S3_BUCKET/pod-identity-test.txt"
```

Pod Identity 전용 토큰을 디코딩하면 `aud`가 `["pods.eks.amazonaws.com"]`입니다. IRSA의 `sts.amazonaws.com`과 구분되며, EKS Auth API에서만 유효합니다.

```bash
kubectl exec s3-pod-identity-test -- \
  cat /var/run/secrets/pods.eks.amazonaws.com/serviceaccount/eks-pod-identity-token \
  | cut -d. -f2 | base64 -d 2>/dev/null | jq
```

???+ info "Session Tags (ABAC)"
    `sts get-caller-identity`의 `Arn`에 session name이 포함됩니다. EKS Auth API가 `AssumeRoleForPodIdentity` 시 자동으로 4개 태그를 부여합니다.

    `eks:cluster-name` / `kubernetes-namespace` / `kubernetes-service-account` / `eks:cluster-arn`

    IAM policy에서 `aws:PrincipalTag` 조건으로 같은 role이라도 namespace별, SA별 접근 제한이 가능합니다.

    ```json
    { "Condition": { "StringEquals": { "aws:PrincipalTag/kubernetes-namespace": "production" } } }
    ```

### Deep Dive

=== "Credential Endpoint"

    Pod 내부에서 eks-pod-identity-agent의 credential endpoint를 직접 호출합니다. SDK가 내부적으로 수행하는 동작과 동일합니다.

    ```bash
    kubectl exec -it s3-pod-identity-test -- bash

    # Pod shell 내부
    EKS_POD_IDENTITY_TOKEN=$(cat $AWS_CONTAINER_AUTHORIZATION_TOKEN_FILE)
    curl -s 169.254.170.23/v1/credentials \
      -H "Authorization: $EKS_POD_IDENTITY_TOKEN" | python3 -m json.tool

    exit
    ```

    응답에 `AccessKeyId`, `SecretAccessKey`, `Token`, `Expiration`이 포함됩니다.

=== "Node Network (SSM)"

    SSM으로 노드에 접속하여 Agent의 link-local 인터페이스와 포트를 확인합니다.

    ```bash
    aws ssm start-session --target <INSTANCE_ID>

    # 노드 shell 내부
    sudo ss -tnlp | grep eks-pod-identit
    sudo ip -c addr show dev pod-id-link0
    ```

    `pod-id-link0` 인터페이스에 `169.254.170.23/32`가 할당되어 있고, `:80`(credential)과 `:2703`(health)에서 수신 중입니다.

=== "CloudTrail: AssumeRoleForPodIdentity"

    Pod Identity의 CloudTrail `eventSource`는 IRSA(`sts.amazonaws.com`)와 달리 `eks-auth.amazonaws.com`입니다.

    ```bash
    aws cloudtrail lookup-events \
      --lookup-attributes AttributeKey=EventName,AttributeValue=AssumeRoleForPodIdentity \
      --max-items 1 | jq '.Events[] | (.CloudTrailEvent | fromjson) | {
        eventName,
        eventSource,
        nodeRole: .userIdentity.sessionContext.sessionIssuer.userName,
        clusterName: .requestParameters.clusterName
      }'
    ```

=== "ExternalDNS Pod Identity"

    Week 3의 node role 방식 대신 EKS addon `pod_identity_association`으로 ExternalDNS에 전용 IAM role을 부여했습니다.

    ```bash
    aws eks list-pod-identity-associations --cluster-name myeks \
      --query 'associations[?serviceAccount==`external-dns`]' | jq

    kubectl logs -n external-dns -l app.kubernetes.io/name=external-dns --tail=10
    ```

---

## Comparison

IRSA와 Pod Identity를 나란히 배포하고 환경변수, 토큰 경로, 인증 방식의 차이를 비교합니다.

```bash
kubectl apply -f labs/week4/manifests/comparison/side-by-side-pod.yaml
kubectl wait --for=condition=Ready pod/irsa-compare pod/pod-identity-compare --timeout=60s

# IRSA Pod
kubectl exec irsa-compare -- env | grep AWS | sort

# Pod Identity Pod
kubectl exec pod-identity-compare -- env | grep AWS | sort
```

### IRSA vs Pod Identity

| 항목 | IRSA | Pod Identity |
|---|---|---|
| **Auth mechanism** | OIDC Federation + `AssumeRoleWithWebIdentity` | EKS Auth API + `AssumeRoleForPodIdentity` |
| **OIDC registration** | 필요 (IAM에 OIDC Provider 등록) | 불필요 |
| **Trust Policy principal** | OIDC issuer URL (`Federated`) | `pods.eks.amazonaws.com` (`Service`) |
| **SA configuration** | annotation 필요 (`eks.amazonaws.com/role-arn`) | annotation 불필요 |
| **Association management** | SA annotation (etcd) | Pod Identity Association (EKS API) |
| **Environment variables** | `AWS_ROLE_ARN`, `AWS_WEB_IDENTITY_TOKEN_FILE` | `AWS_CONTAINER_CREDENTIALS_FULL_URI`, `AWS_CONTAINER_AUTHORIZATION_TOKEN_FILE` |
| **Token audience** | `sts.amazonaws.com` | `pods.eks.amazonaws.com` |
| **Session tags** | 미지원 | 자동 부여 (cluster, namespace, SA, pod) |
| **Cross-cluster reuse** | Trust Policy 수정 필요 | 그대로 사용 가능 |
| **STS quota** | 호출마다 영향 | STS 직접 호출 없음 |
| **Supported environments** | EKS, EKS Anywhere, ROSA, EC2 | EKS 전용 |
| **CloudTrail event source** | `sts.amazonaws.com` | `eks-auth.amazonaws.com` |

### Four-Way Comparison

Operator → K8s API 경로의 두 방식(ConfigMap, Access Entry)과 Pod → AWS API 경로의 두 방식(IRSA, Pod Identity)을 종합 비교합니다.

| 항목 | aws-auth ConfigMap | Access Entry | IRSA | Pod Identity |
|---|---|---|---|---|
| **Purpose** | Operator → K8s API | Operator → K8s API | Pod → AWS API | Pod → AWS API |
| **Data store** | etcd (ConfigMap) | EKS managed (AWS API) | IAM + SA annotation | EKS managed (AWS API) |
| **Status** | Deprecated | Recommended | Supported | Recommended |
| **Recovery** | 삭제 시 lockout 위험 | AWS API로 복구 가능 | IAM 표준 절차 | IAM 표준 절차 |
| **Configuration** | `kube-system` ConfigMap | `aws eks` CLI / Terraform | IAM role + K8s SA annotation | EKS API + IAM role |
| **Key difference** | K8s 자원으로 관리 | AWS API로 관리 | OIDC 연동 필요 | OIDC 없이 가능 |

---

## Cleanup

```bash
# Kubernetes 리소스 정리
kubectl delete -f labs/week4/manifests/comparison/
kubectl delete -f labs/week4/manifests/pod-identity/
envsubst < labs/week4/manifests/irsa/s3-irsa-sa.yaml | kubectl delete -f -
kubectl delete -f labs/week4/manifests/irsa/s3-irsa-pod.yaml
kubectl delete -f labs/week4/manifests/rbac/

# Terraform 인프라 정리
cd labs/week4
terraform destroy -auto-approve
```
