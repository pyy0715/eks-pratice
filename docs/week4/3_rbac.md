# Kubernetes RBAC

앞 장에서 다룬 운영자 인증/인가는 EKS Webhook이 IAM principal을 K8s subject로 매핑하는 동작이었습니다. Pod이 K8s API를 호출할 때는 IAM이 사용되지 않습니다. Pod의 신원은 ServiceAccount이고, 권한은 K8s 내부 RBAC으로 결정됩니다. 여기서는 K8s 네이티브 권한 모델을 정리합니다. 다음 페이지의 IRSA와 Pod Identity가 같은 모델을 AWS API 호출로 확장할 때 이 내용을 전제로 삼습니다.

---

## Role-Based Access Control

K8s RBAC은 네 가지 리소스로 구성됩니다.

- **Role / RoleBinding** — 특정 네임스페이스 내에서만 유효한 권한과 바인딩
- **ClusterRole / ClusterRoleBinding** — 클러스터 전체에 걸쳐 유효한 권한과 바인딩

Subject(권한을 부여받는 주체)는 세 가지가 있습니다.

- **User** — IAM principal에서 매핑된 가상 사용자입니다. EKS에서는 [Operator Authentication](2_operator-auth.md#authorization-mapping-access-entries-vs-aws-auth-configmap)에서 본 Access Entry가 이 매핑을 만듭니다.
- **Group** — 사용자 묶음입니다. EKS Webhook이 응답하는 `system:authenticated`나 Access Entry에 지정한 K8s group이 여기에 해당합니다.
- **ServiceAccount** — 클러스터 내 워크로드의 신원입니다. 네임스페이스에 속하며, Pod이 직접 사용합니다.

Role과 RoleBinding의 관계는 다음과 같습니다.

```yaml title="Role + RoleBinding"
apiVersion: rbac.authorization.k8s.io/v1
kind: Role
metadata:
  name: pod-reader
  namespace: dev-team
rules:
- apiGroups: [""]
  resources: ["pods"]
  verbs: ["get", "list", "watch"]
---
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata:
  name: dev-pod-reader
  namespace: dev-team
subjects:
- kind: ServiceAccount
  name: dev-k8s
  namespace: dev-team
roleRef:
  kind: Role
  name: pod-reader
  apiGroup: rbac.authorization.k8s.io
```

Role은 권한 묶음이고, RoleBinding이 그 묶음을 특정 subject에 연결합니다. ClusterRole/ClusterRoleBinding도 같은 구조이며 스코프만 다릅니다.

---

## Verbs and HTTP Methods

K8s RBAC의 verb는 RESTful HTTP 메서드와 직접 대응됩니다. `kubectl get pod -v=8`을 실행하면 어떤 verb가 어떤 HTTP 호출로 변환되는지 직접 확인할 수 있습니다.

| Verb | HTTP Method | Meaning |
|---|---|---|
| `get` | `GET /api/v1/namespaces/<ns>/pods/<name>` | 단일 리소스 조회 |
| `list` | `GET /api/v1/namespaces/<ns>/pods` | 리소스 목록 조회 |
| `watch` | `GET ?watch=true` | 변경 스트림 구독 |
| `create` | `POST` | 신규 생성 |
| `update` | `PUT` | 전체 교체 |
| `patch` | `PATCH` | 부분 수정 |
| `delete` | `DELETE` | 단일 삭제 |
| `deletecollection` | `DELETE` (목록) | 컬렉션 삭제 |

`get`과 `list`는 같은 GET 메서드를 사용하지만 RBAC에서는 별개의 verb로 취급되므로, 단일 조회만 허용하고 목록 조회는 막는 식의 세분화가 가능합니다.

---

## API Groups

K8s API는 두 종류의 path 구조를 사용합니다.

- **Core group** — `/api/v1/...`. Pod, Service, ConfigMap, Namespace 등 가장 오래된 리소스
- **Named group** — `/apis/<group>/<version>/...`. apps, batch, networking.k8s.io 등 그 외 모든 리소스

`kubectl api-resources --api-group=apps`로 그룹 단위로 리소스를 나열할 수 있습니다. RBAC Role의 `apiGroups` 필드는 core group을 빈 문자열 `""`로 표기한다는 점에 주의합니다.

---

## ServiceAccount and Projected Token

모든 Pod은 하나의 ServiceAccount에 바인딩됩니다. Pod spec에 `serviceAccountName`을 명시하지 않으면 네임스페이스의 기본 SA(`default`)가 자동으로 적용됩니다.

Pod 안의 `/var/run/secrets/kubernetes.io/serviceaccount/token` 경로는 Secret 기반이 아니라 Projected Volume입니다. K8s 1.12에 `ProjectedServiceAccountToken` 기능이 도입되었고, K8s 1.22부터 [`BoundServiceAccountTokenVolume`](https://kubernetes.io/docs/reference/access-authn-authz/service-accounts-admin/#bound-service-account-token-volume)이 기본 활성화되었습니다. 그 결과 모든 SA 토큰은 audience, 만료 시각, 서명 키에 바인딩된 OIDC JWT로 발급됩니다.

토큰의 기본 만료는 1시간입니다. Amazon EKS는 구버전 SDK가 새로운 토큰 형식으로 마이그레이션할 수 있도록 만료를 최대 90일까지 연장합니다.[^token-expiry] 90일을 초과한 토큰은 API 서버가 거부합니다. 정상 동작은 클라이언트 SDK가 1시간 이내에 토큰을 자동 갱신하는 것이며, 만료 직전 토큰을 사용하는 클라이언트는 audit log의 `annotations.authentication.k8s.io/stale-token` 필드로 식별할 수 있습니다.

[^token-expiry]: [Grant Kubernetes workloads access to AWS using Kubernetes Service Accounts](https://docs.aws.amazon.com/eks/latest/userguide/service-accounts.html) — Service account tokens 섹션

토큰의 페이로드를 base64 디코딩하면 OIDC JWT 표준 claim이 보입니다.

```json
{
  "aud": ["https://kubernetes.default.svc"],
  "exp": 1716619848,
  "iat": 1685083848,
  "iss": "https://oidc.eks.ap-northeast-2.amazonaws.com/id/<id>",
  "kubernetes.io": {
    "namespace": "default",
    "node":           {"name": "ip-192-168-1-70..."},
    "pod":            {"name": "eks-iam-test2"},
    "serviceaccount": {"name": "default"}
  },
  "sub": "system:serviceaccount:default:default"
}
```

| Field | Meaning |
|---|---|
| `iss` | Issuer. EKS 클러스터의 OIDC Provider URL |
| `aud` | Audience (토큰의 사용 대상 서비스) |
| `exp` | 만료 시각 (Unix timestamp) |
| `iat` | 발급 시각 |
| `sub` | Subject (`system:serviceaccount:<namespace>:<sa-name>`) |
| `kubernetes.io.namespace` | SA가 속한 네임스페이스 |
| `kubernetes.io.pod` | 토큰을 마운트한 Pod 정보 |
| `kubernetes.io.serviceaccount` | SA 정보 |
| `kubernetes.io.node` | Pod이 스케줄된 노드 정보 |

`aud` 값이 `https://kubernetes.default.svc`로 고정되어 있으므로, 이 토큰은 K8s API 서버에서만 검증을 통과합니다. 토큰이 다른 서비스(예: AWS STS)로 전달되어도 audience 불일치로 거부됩니다. 다음 페이지에서 다룰 [IRSA 토큰](4_pod-workload-identity.md#audience-boundary)은 같은 위치에 `sts.amazonaws.com`을, [Pod Identity 토큰](4_pod-workload-identity.md#credential-flow)은 `pods.eks.amazonaws.com`을 사용합니다. audience 분리는 워크로드별로 자격 증명의 영향 범위를 제한합니다.

K8s API를 호출할 필요가 없는 Pod에 대해서는 토큰 마운트 자체를 차단할 수 있습니다.

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: stateless-worker
spec:
  automountServiceAccountToken: false
  containers:
    - name: worker
      image: example/worker:latest
```

`automountServiceAccountToken: false`는 최소 권한 패턴이며, 외부 API만 호출하는 워크로드에 권장됩니다.

---

## Hands-on - RBAC Practice

dev-team과 infra-team 두 네임스페이스에 각각 ServiceAccount(`dev-k8s`, `infra-k8s`)와 네임스페이스 내 모든 권한을 가진 Role을 만든 뒤 RoleBinding으로 연결하면, 각 SA로 실행되는 kubectl Pod이 자신의 네임스페이스 안에서만 동작하는지를 확인할 수 있습니다. 권한 검증은 매번 출력을 읽기보다는 `kubectl auth can-i`로 한 줄에 끝냅니다.

```bash
kubectl auth can-i get pods --as=system:serviceaccount:dev-team:dev-k8s -n dev-team
# yes

kubectl auth can-i get pods --as=system:serviceaccount:dev-team:dev-k8s -n infra-team
# no
```

`--as` 플래그는 impersonation을 사용해 다른 사용자/SA의 권한으로 요청을 시뮬레이션합니다. 이 명령으로 RoleBinding이 의도한 대로 적용되었는지 즉시 확인할 수 있습니다.

???+ info "Krew RBAC Plugins"
    Krew 플러그인 몇 가지가 RBAC 디버깅에 유용합니다.

    - `kubectl rbac-tool whoami` — 현재 인증된 username, groups, 발급된 IAM principal ARN을 한 번에 표시
    - `kubectl rolesum -k Group system:authenticated` — 특정 subject가 가진 모든 정책과 verb 매트릭스를 요약
    - `kubectl access-matrix --namespace dev-team` — 네임스페이스 단위 verb 접근성 매트릭스
    - `kubectl rbac-view` — 브라우저 기반 RBAC 시각화

    설치는 `kubectl krew install rbac-tool rolesum access-matrix rbac-view`로 한 번에 가능합니다.

---

## Admission Control

인증과 인가를 통과한 요청은 etcd에 저장되기 전 admission 단계로 들어갑니다. Mutating → Schema validation → Validating 3단계의 일반 동작은 [Background — Admission Control Phases](0_background.md#kubernetes-extension-via-webhook)에서 다뤘습니다. 여기서는 EKS 클러스터에 등록되는 admission webhook 종류만 정리합니다.

EKS 클러스터에는 기본적으로 여러 개의 MutatingWebhookConfiguration이 등록되어 있습니다.

```bash
kubectl get mutatingwebhookconfigurations
# NAME                              WEBHOOKS   AGE
# aws-load-balancer-webhook         3          ...
# pod-identity-webhook              1          ...
# vpc-resource-mutating-webhook     1          ...
```

`pod-identity-webhook`은 다음 페이지에서 IRSA와 Pod Identity 동작에 사용됩니다. ServiceAccount에 IAM Role 정보가 연결된 Pod이 생성될 때 이 webhook이 Pod spec에 환경 변수와 projected volume을 추가해 SDK가 자격 증명을 받아오도록 합니다.

이 webhook의 `MutatingWebhookConfiguration` 객체는 사용자 클러스터에 등록되어 있지만, 실제 webhook 서버는 EKS 컨트롤 플레인에서 EKS가 관리합니다. 사용자 클러스터에는 webhook의 endpoint와 규칙만 노출되며 검증 로직은 컨트롤 플레인에 분리되어 있습니다.

[Operator Authentication](2_operator-auth.md#worker-node-as-a-client)에서 언급한 `Node Restriction`도 admission plugin의 한 종류입니다. RBAC만으로는 워커 노드가 자신의 노드 오브젝트만 수정하도록 제한할 수 없으므로, K8s는 admission 단계에서 노드의 username(`system:node:<nodename>`)과 수정 대상 오브젝트의 이름을 비교해 일치할 때만 요청을 통과시킵니다.
