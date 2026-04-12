# Background

---

## Bearer Tokens and JWT

전통적인 웹 인증 모델은 사용자가 로그인하면 서버가 세션 ID를 발급하고, 이후 요청마다 서버가 자신의 세션 저장소에서 ID를 조회해 사용자를 식별합니다. 이 모델은 단일 서버 환경에서는 잘 동작하지만 분산 환경에서는 문제가 생깁니다. 요청이 들어올 때마다 모든 API 서버가 중앙 세션 저장소를 조회해야 하므로 저장소가 단일 장애점이 되고, 매 요청마다 네트워크 왕복이 추가됩니다.

토큰 기반 인증은 다른 접근을 취합니다. Issuer가 사용자 신원과 만료 시각을 토큰 안에 직접 담고 자신의 개인키로 서명합니다. Verifier는 Issuer의 공개키만 있으면 토큰을 받자마자 독립적으로 검증할 수 있고, 외부 저장소 조회가 필요 없습니다. 

이를 stateless 검증이라고 부르며, Kubernetes API 서버가 여러 노드에 걸쳐 복제되는 환경에서 어느 노드가 요청을 받든 동일한 결과를 리턴해주기 위해서는 토큰 기반의 인증이 필요합니다.

Bearer 토큰은 이 토큰을 HTTP에 실어 보내는 방식의 명칭입니다. RFC 6750이 정의하며, "이 토큰을 보유한(bearer) 자가 토큰이 나타내는 권한을 가진다"는 의미입니다. HTTP Authorization 헤더에 다음과 같이 실립니다.[^k8s-auth]

[^k8s-auth]: [Kubernetes — Authenticating](https://kubernetes.io/docs/reference/access-authn-authz/authentication/)

```text
Authorization: Bearer 31ada4fd-adec-460c-809a-9e56ceb75269
```

토큰 자체는 Issuer가 정한 어떤 형식이든 될 수 있습니다. 위처럼 의미 없는 랜덤 바이트열일 수도 있고, 구조를 가진 토큰일 수도 있습니다. Kubernetes ServiceAccount Token, IRSA의 projected volume 토큰은 모두 구조화된 토큰이며 JWT(RFC 7519) 형식을 따릅니다.

!!! warning
    EKS의 `aws eks get-token` 출력은 JWT가 아니라 `GetCallerIdentity`에 대한 Pre-signed URL을 Base64 인코딩한 값입니다. 자세한 구조는 [Operator Authentication](2_operator-auth.md#token-generation-on-the-client)에서 다룹니다.

### Structure

JSON Web Tokens(JWT)는 점(`.`)로 연결된 세 부분으로 구성됩니다.

- Header
- Payload
- Signature

![JWT structure](https://www.jwt.io/_next/image?url=https%3A%2F%2Fcdn.auth0.com%2Fwebsite%2Fjwt%2Fintroduction%2Fdebugger.png&w=3840&q=75)
*[Source: jwt.io — Introduction to JSON Web Tokens](https://jwt.io/introduction)*

일반 Base64는 `+`, `/`, `=` 문자를 사용해 URL에서 충돌을 일으키는데, Base64 URL은 이 문자들을 `-`, `_`로 대체하고 패딩을 생략해 URL-safe하게 만든 변형입니다. 각 파트는 이 Base64 URL 인코딩을 사용하기 때문에 HTTP 헤더, URL 쿼리 파라미터, 쿠키 어디에든 안전하게 전달될 수 있습니다.

세 파트는 각각 다른 역할을 합니다.

- **Header** — 토큰의 타입(`typ`)과 서명 알고리즘(`alg`), 서명에 사용된 키의 식별자(`kid`)를 JSON으로 담습니다. Header가 별도로 분리된 이유는 Payload를 디코딩하기 전에 어떤 알고리즘으로, 어떤 키로 검증할지 결정할 수 있어야 하기 때문입니다.
- **Payload** — 실제로 전달할 claim을 JSON으로 담습니다. 표준 claim에는 `iss`(Issuer), `sub`(Subject), `aud`(Audience), `exp`(Expiration), `iat`(Issued At), `nbf`(Not Before)가 있고, Issuer가 임의의 custom claim을 추가할 수 있습니다.
- **Signature** — Header와 Payload를 이어붙인 문자열에 Header가 지정한 알고리즘을 적용해 만든 서명입니다.

토큰을 검증할 때는 Header를 먼저 읽어 알고리즘을 확인한 뒤, 같은 입력으로 서명을 재계산해 일치하는지 확인합니다. 일치하면 Payload가 변조되지 않았다는 의미가 됩니다.

JWT는 Payload를 암호화하지 않습니다. Base64 URL로 인코딩되어 있을 뿐이라 누구나 디코딩해 claim을 읽을 수 있고, 서명은 변조 여부만 검증할 뿐 내용을 가려 주지 않습니다. 따라서 토큰에는 비밀번호나 API 키 같은 민감 정보를 담지 말고, 사용자 ID나 권한 범위처럼 노출되어도 무방한 데이터만 담아야 합니다.

### Symmetric vs Asymmetric Signing

서명 알고리즘은 두 부류로 나뉩니다.

| Algorithm Family | Examples | Signing Key | Verification Key |
|---|---|---|---|
| Symmetric (HMAC) | `HS256`, `HS384` | 비밀키(shared secret) | 같은 비밀키 |
| Asymmetric (RSA / ECDSA) | `RS256`, `ES256` | Issuer의 개인키 | 공개키 |

대칭 서명(HMAC)은 하나의 비밀키로 서명과 검증을 모두 수행합니다. 즉, 토큰을 발급하는 쪽과 검증하는 쪽이 같은 키를 가지고 있어야 합니다. 토큰을 검증하는 컴포넌트가 여럿이면 그만큼 같은 비밀키의 사본이 여러 곳에 존재하게 되고, 그중 한 곳만 유출되어도 그 키로 새 토큰을 위조할 수 있게 됩니다. 결국 Issuer를 포함한 모든 곳의 키를 한꺼번에 교체할 수밖에 없습니다

비대칭 서명(RSA/ECDSA)은 이 둘을 분리합니다. 서명은 Issuer만 가진 개인키로 만들고, 검증은 공개키만 있으면 누구나 수행할 수 있습니다.

이러한 구조를 기반으로 EKS는 ServiceAccount Token을 RS256으로 서명하고 검증에 필요한 공개키만 외부에 노출합니다. EKS의 개인키는 클러스터 밖으로 나가지 않으므로, 검증하는 공개키가 유출되더라도 EKS의 토큰 발급 권한은 영향을 받지 않습니다.

---

## OAuth 2.0 and OpenID Connect(OIDC)

OAuth 2.0(RFC 6749)은 **권한 위임(delegated authorization)** 프로토콜입니다. 사용자가 비밀번호를 넘겨주지 않고도 서드파티 애플리케이션에 자기 계정의 리소스에 접근할 권한만 위임하는 흐름을 표준화한 것입니다. 이 흐름의 결과로 발급되는 것이 Access Token이며, Access Token은 사용자 신원이 아니라 부여된 접근 범위(scope)를 나타냅니다.

여기에 두 가지 한계가 있습니다.

1. Access Token은 사용자가 누구인지를 직접 알려주지 않습니다. 토큰 형식이 표준화되어 있지 않아서 어떤 Provider는 JWT를, 어떤 Provider는 Provider만 해석할 수 있는 임의의 문자열을 발급합니다. 토큰을 받은 쪽이 사용자 ID를 알려면 Provider의 별도 API(예: `/userinfo`)를 다시 호출해야 합니다.

2. OAuth 2.0 자체는 토큰의 Audience와 Issuer를 표준화하지 않았습니다. 같은 Provider에서 발급한 두 토큰이 서로 다른 애플리케이션을 대상으로 한 것인지 검증할 표준 방법이 없어, 한 애플리케이션을 위해 발급한 토큰이 다른 애플리케이션으로 유입되어도 막을 수단이 없습니다.

OpenID Connect(OIDC)는 OAuth 2.0 위에 인증 계층을 표준화한 프로토콜입니다.

<div class="grid cards" markdown>

- :material-card-account-details: **ID Token**

    ---
    Access Token과 별개로 사용자 신원을 담은 JWT를 발급합니다. 형식은 JWT(RFC 7519)이며 표준 claim(`iss`, `sub`, `aud`, `exp`, `iat`)을 반드시 포함합니다. Provider를 별도로 호출하지 않고도 토큰만으로 사용자 ID를 확인할 수 있습니다.

- :material-compass: **Discovery endpoint**

    ---
    모든 OIDC Provider는 `<issuer>/.well-known/openid-configuration` 경로에 자신의 메타데이터를 JSON으로 공개해야 합니다. 인증 엔드포인트, 토큰 엔드포인트, JWKS URI, 지원 서명 알고리즘이 담겨 있어 Issuer URL만 알면 나머지 정보를 자동으로 받아올 수 있습니다.

- :material-key-chain: **JWKS (JSON Web Key Set)**

    ---
    Provider의 공개키 목록을 JSON 형식으로 제공하는 엔드포인트입니다. 키 회전 시 새 키와 이전 키가 함께 제공되므로 여러 키를 동시에 신뢰할 수 있고, 키 교체 시점에 토큰 검증이 끊기지 않습니다. 엔드포인트 URL은 Discovery 문서의 `jwks_uri` 필드에 명시됩니다.

</div>

### JWKS Discovery

```text
<issuer>/.well-known/openid-configuration   → discovery 문서 (jwks_uri 등 메타데이터)
<issuer>/keys                                → JWKS (공개키 집합)
```

Discovery 문서 예시는 다음과 같은 필드를 포함합니다.

```json
{
  "issuer": "https://oidc.eks.ap-northeast-2.amazonaws.com/id/<id>",
  "jwks_uri": "https://oidc.eks.ap-northeast-2.amazonaws.com/id/<id>/keys",
  "response_types_supported": ["id_token"],
  "id_token_signing_alg_values_supported": ["RS256"]
}
```

JWKS는 Discovery 문서의 `jwks_uri`를 조회해 얻는 RSA 공개키 집합입니다. 키마다 고유한 kid(key ID)가 있고, JWT Header의 kid와 일치하는 공개키를 찾아서 검증에 사용할 키를 선택합니다.

### How IRSA Reuses the OIDC Model

AWS는 2014년부터 IAM에 OIDC Federation을 지원해 왔습니다. AWS STS에 OIDC Provider의 Issuer URL을 등록해 두면, 그 Provider가 발급한 JWT를 신뢰하고 AWS 자격증명으로 교환해 줍니다. 검증 방식은 앞서 설명한 OIDC 표준을 그대로 따릅니다.

EKS는 이 OIDC Federation을 워크로드 신원 증명에 사용합니다. 클러스터마다 OIDC Provider를 호스팅하고, Kubernetes ServiceAccount Token을 그 Provider가 서명한 JWT로 발급하면, AWS STS 입장에서는 여느 OIDC Provider와 다를 게 없으므로 EKS 전용 로직 없이 워크로드 신원을 검증할 수 있습니다. 구체적인 컴포넌트 구성과 런타임 흐름은 [Pod Workload Identity](4_pod-workload-identity.md#iam-roles-for-service-accounts)에서 다룹니다.

---

## Kubernetes Extension via Webhook

Kubernetes는 GKE, EKS, AKS, OpenShift, On-Prem 등 전혀 다른 환경에서 동일한 코드로 동작해야 합니다. 문제는 환경마다 사용자를 식별하고 권한을 판단하는 체계가 다르다는 점입니다. GKE는 Google IAM, EKS는 AWS IAM, On-Prem은 LDAP이나 자체 IdP를 쓰는 식이고, 인가 정책의 형태도 환경마다 제각각입니다.

Kubernetes는 이 문제를 **인터페이스만 정의하고 구현은 외부에 위임**하는 방식으로 해결했습니다. kube-apiserver는 요청 처리 파이프라인의 각 단계에서 판단이 필요할 때 그 내용을 표준 요청 객체로 감싸 외부 HTTP 엔드포인트에 POST하고, 엔드포인트가 돌려주는 응답을 그대로 결정에 사용합니다. 이 외부 엔드포인트를 webhook이라 부르며, 환경별로 달라지는 인증/인가 로직은 모두 webhook 구현체 안에 담깁니다.

![Access Control Pipeline in Kubernetes](https://kubernetes.io/images/docs/admin/access-control-overview.svg)
*[Source: Kubernetes documentation — Controlling Access to the Kubernetes API](https://kubernetes.io/docs/concepts/security/controlling-access/)*

kube-apiserver는 요청을 Authentication → Authorization → Admission Control 세 stage를 거쳐 처리합니다. 이 중 Admission Control은 내부적으로 Mutating → Schema Validation → Validating 세부 단계로 나뉘며, webhook을 등록해 외부 서버에 판단을 위임할 수 있는 단계는 Authentication, Authorization, Mutating Admission, Validating Admission 네 곳입니다.

네 단계 모두 호출 방식은 동일합니다. kube-apiserver가 표준 요청 객체를 JSON으로 POST하고, webhook이 같은 객체의 `status` 필드를 채워 되돌려 주면 kube-apiserver가 그 결과를 받아 다음 단계로 넘어갑니다. 달라지는 건 호출되는 시점과 응답에 담아야 하는 값뿐입니다.

| Stage | API Object | EKS Webhook |
|---|---|---|
| Authentication | `TokenReview` (`authentication.k8s.io/v1`) | `aws-iam-authenticator` — 토큰을 STS에 검증시키고 IAM principal을 Kubernetes subject로 매핑 |
| Authorization | `SubjectAccessReview` (`authorization.k8s.io/v1`) | `EKS Authorizer` — Access Policy를 평가해 Allow/NoOpinion 반환 |
| Mutating Admission | `AdmissionReview` (`admission.k8s.io/v1`) | `Pod Identity Webhook` — IRSA/Pod Identity 대상 Pod의 spec을 mutate |
| Validating Admission | `AdmissionReview` (`admission.k8s.io/v1`) | EKS가 고정적으로 운영하는 webhook은 없음. 사용자가 Kyverno, Gatekeeper 등을 배포해 정책 검증에 사용 |

!!! info
    EKS에서 IAM과 관련된 webhook은 세 단계에 걸쳐 있습니다. Authentication과 Authorization 단계에서는 IAM principal의 인증과 권한 결정이 이루어지고, Mutating Admission 단계에서는 워크로드가 IAM Role을 사용할 수 있도록 Pod spec에 자격 증명 설정을 추가합니다.

!!! note "Static vs Dynamic registration"
    Authentication과 Authorization은 kube-apiserver 프로세스 기동 시 플래그(`--authentication-token-webhook-config-file`, `--authorization-mode=Webhook`)로만 지정할 수 있어, **클러스터 관리자(EKS의 경우 AWS)만 구성할 수 있습니다.** 반면 Mutating/Validating Admission은 `MutatingWebhookConfiguration` / `ValidatingWebhookConfiguration` 객체를 통해 런타임에 동적으로 등록됩니다. 사용자가 `kubectl apply`로 직접 추가할 수도 있고, EKS 애드온이 설치 시점에 자동으로 등록하기도 합니다.

이러한 위임 모델에는 세 가지 비용이 따라옵니다.

1. 외부 호출이 매 요청마다 발생하면 kube-apiserver 응답 지연이 늘어납니다.
2. webhook이 응답하지 않으면 kube-apiserver는 요청을 끝내지 못합니다.
3. webhook이 잘못된 응답을 반환하면 그 결정이 클러스터 전체에 영향을 미칩니다.

Kubernetes는 이 비용을 줄이기 위해 세 가지 장치를 두고 있습니다.

1. **Caching** kube-apiserver는 인증 webhook의 성공 응답을 기본 2분간 캐싱합니다. 같은 토큰으로 짧은 시간에 여러 요청이 들어와도 webhook 호출은 한 번만 발생하며, 이 덕분에 EKS의 aws-iam-authenticator가 사용자 요청마다 STS를 호출하지 않아도 됩니다.

    ```bash
    --authentication-token-webhook-config-file=/etc/kubernetes/aws-iam-authenticator/kubeconfig.yaml
    --authentication-token-webhook-cache-ttl=2m  # (1)
    ```

    1. 인증 성공 응답의 캐시 유지 시간. EKS 기본값은 2분입니다.

2. **Failure policy** Admission webhook은 webhook이 응답하지 않을 때 kube-apiserver가 어떻게 처리할지를 `failurePolicy` 필드로 선언합니다. 보안상 반드시 통과해야 하는 webhook은 `Fail`로 두어 webhook 장애 시 요청을 거부하고, 누락돼도 안전한 webhook은 `Ignore`로 두어 webhook 장애가 클러스터 전체를 멈추지 않도록 합니다.

    ```yaml
    apiVersion: admissionregistration.k8s.io/v1
    kind: MutatingWebhookConfiguration
    metadata:
      name: pod-identity-webhook
    webhooks:
    - name: pod-identity-webhook.amazonaws.com
      failurePolicy: Ignore # (1)
    ```

    1. webhook 장애 시에도 Pod 생성을 허용합니다. IRSA 설정이 누락되더라도 Pod 자체는 정상적으로 기동됩니다.

3. **Authorizer chain** `--authorization-mode=Node,RBAC,Webhook`처럼 authorizer를 나열하면 kube-apiserver는 나열된 순서대로 평가합니다.[^k8s-webhook-mode] 먼저 호출된 authorizer가 Allow를 반환하면 즉시 종료되고, No opinion이면 다음 authorizer로 넘깁니다. 모두 결정을 내리지 못하면 최종적으로 Deny가 반환됩니다. 인가 webhook이 반환할 수 있는 응답은 세 가지입니다.

=== "Allow"

    ```json
    {"apiVersion": "authorization.k8s.io/v1", "kind": "SubjectAccessReview",
     "status": {"allowed": true}}
    ```

=== "No opinion"

    다음 authorizer로 위임합니다.

    ```json
    {"apiVersion": "authorization.k8s.io/v1", "kind": "SubjectAccessReview",
     "status": {"allowed": false, "reason": "..."}}
    ```

=== "Immediate deny"

    후속 authorizer 평가를 차단합니다.

    ```json
    {"apiVersion": "authorization.k8s.io/v1", "kind": "SubjectAccessReview",
     "status": {"allowed": false, "denied": true, "reason": "..."}}
    ```

No opinion과 Immediate deny는 모두 거부이지만 동작이 다릅니다. No opinion은 다음 authorizer에 판단을 넘기고, Immediate deny는 chain을 중단해 다른 authorizer의 Allow까지 차단합니다. EKS Authorizer는 No opinion을 활용해, RBAC이 평가한 사용자 정의 ClusterRoleBinding과 EKS Access Policy가 한 클러스터 안에서 충돌 없이 함께 동작하도록 합니다.

[^k8s-webhook-mode]: [Kubernetes — Webhook Mode, Request payloads](https://kubernetes.io/docs/reference/access-authn-authz/webhook/#request-payloads)

### Admission Control Phases

Admission 단계는 **Mutating → Schema Validation → Validating** 세 부분으로 구성됩니다. Mutating 단계에서는 webhook이 객체를 수정할 수 있고, 그 뒤의 Schema Validation 단계에서는 수정된 객체가 Kubernetes API 스키마에 맞는지 확인하며, 마지막 Validating 단계에서는 수정 없이 통과 여부만 결정합니다. 즉 mutating webhook이 잘못된 형식의 객체를 만들면 validating 단계까지 가기 전에 스키마 단계에서 거부됩니다.

![Admission controller phases](https://kubernetes.io/images/blog/2019-03-21-a-guide-to-kubernetes-admission-controllers/admission-controller-phases.png)
*[Source: A Guide to Kubernetes Admission Controllers — Kubernetes Blog](https://kubernetes.io/blog/2019/03/21/a-guide-to-kubernetes-admission-controllers/)*

Mutating이 Validating보다 먼저 오는 이유는 최종 검증의 대상이 모든 수정이 끝난 후의 객체여야 하기 때문입니다. EKS의 Pod Identity Webhook이 대표적인 예로, IRSA 대상 Pod의 spec에 환경 변수와 토큰 볼륨을 추가합니다. Webhook이 추가하는 구체적인 내용은 [Pod Workload Identity](4_pod-workload-identity.md#iam-roles-for-service-accounts)에서 다룹니다. 이렇게 추가된 내용이 schema 및 validating 단계를 거친 뒤 etcd에 저장됩니다.

---

## AWS Request Signing

AWS API는 매 요청마다 호출자가 누구인지 증명해야 합니다. AWS는 이를 위해 SigV4(Signature Version 4)를 사용합니다. SigV4는 Secret Access Key를 네트워크에 보내지 않고, 그 키에서 유도한 서명을 요청에 포함시키는 방식입니다. AWS 공식 문서는 SigV4가 제공하는 보안 속성 세 가지를 명시합니다.[^sigv4]

<div class="grid cards" markdown>

- :material-account-check: **Verify the identity of the requester**

    ---
    요청에는 Access Key ID가 포함되어 있어 AWS가 요청자를 식별할 수 있고, 서명은 해당 Secret Access Key로만 만들 수 있으므로 요청자가 본인임을 증명합니다.

- :material-shield-lock: **Protect data in transit**

    ---
    요청의 주요 요소(메서드, 경로, 헤더, 본문 해시)로 서명을 계산하므로, 요청이 전송 중 변조되면 서명이 일치하지 않아 AWS가 요청을 거부합니다.

- :material-timer-alert: **Protect against replay attacks**

    ---
    서명된 요청은 타임스탬프 기준 5분 이내에 AWS에 도달해야 합니다. 이 시간이 지나면 동일한 요청을 다시 보내도 AWS가 거부하므로, 유출된 서명의 재사용을 방지합니다.

</div>

[^sigv4]: [AWS — Signature Version 4 for API requests](https://docs.aws.amazon.com/IAM/latest/UserGuide/reference_sigv.html)

서명 과정은 세 단계로 구성됩니다.

![SigV4 key derivation and verification](https://docs.aws.amazon.com/images/AmazonS3/latest/API/images/signing-overview.png)
*[Source: Authenticating Requests (AWS Signature Version 4)](https://docs.aws.amazon.com/AmazonS3/latest/API/sig-v4-authenticating-requests.html)*

1. **String to sign** HTTP 메서드, URI, 헤더, 본문 해시를 정규화해 canonical request를 만들고, 이를 SHA-256으로 해시합니다. 해시 값에 알고리즘, 요청 시각, credential scope를 조합한 결과가 string to sign입니다. 요청 내용이 조금이라도 바뀌면 이 값도 달라지므로 무결성 검증의 기준이 됩니다.
2. **Signing key** Secret Access Key에 date, region, service를 단계별로 HMAC-SHA256에 적용해 signing key를 유도합니다. Secret Access Key를 직접 쓰지 않고 유도하는 이유는, signing key가 특정 date, region, service 조합에서만 유효하기 때문입니다. 키가 유출되더라도 피해 범위가 해당 조합으로 한정됩니다.
3. **Signature** signing key로 string to sign에 HMAC-SHA256을 적용해 최종 서명을 생성합니다. AWS는 Authorization 헤더에서 credential scope를 읽고 동일한 방식으로 서명을 재계산해, 전달받은 서명과 비교합니다.

### Authorization Header vs Pre-signed URL

SigV4 서명 정보는 두 가지 방식으로 요청에 전달할 수 있습니다.

=== "Authorization header"

    일반적인 AWS API 호출에 사용됩니다. 서명 정보가 HTTP `Authorization` 헤더에 들어갑니다.

    ```http
    GET / HTTP/1.1
    Host: ec2.amazonaws.com
    X-Amz-Date: 20260401T123600Z
    Authorization: AWS4-HMAC-SHA256
      Credential=AKIA.../20260401/us-east-1/ec2/aws4_request,
      SignedHeaders=host;x-amz-date,
      Signature=<HMAC-SHA256>
    ```

=== "Query string (Pre-signed URL)"

    같은 서명 정보를 URL의 쿼리 파라미터로 옮겨 담습니다. URL 자체에 서명이 포함되어 있어, URL을 만든 시점에 인증 정보가 모두 결정됩니다. `X-Amz-Expires`는 URL의 유효 시간(초)이며, 최대 7일까지 설정할 수 있습니다.

    ```text
    https://sts.us-east-1.amazonaws.com/?Action=GetCallerIdentity
      &X-Amz-Algorithm=AWS4-HMAC-SHA256
      &X-Amz-Credential=AKIA.../20260401/us-east-1/sts/aws4_request
      &X-Amz-Date=20260401T123600Z
      &X-Amz-Expires=60
      &X-Amz-SignedHeaders=host
      &X-Amz-Signature=<HMAC-SHA256>
    ```

    !!! info "Pre-signed URL과 권한 위임"
        Authorization header 방식에서는 호출자가 직접 Secret Access Key로 서명을 만들어야 하므로, 호출 시점에 키를 가지고 있어야 합니다. Pre-signed URL은 서명을 만드는 주체와 실제 호출하는 주체를 분리할 수 있습니다. 키를 가진 쪽이 서명된 URL을 만들어 다른 컴포넌트에 넘기면, 그 컴포넌트는 키 없이도 URL을 HTTP로 호출해 AWS에 접근할 수 있습니다. 
        
        EKS의 Operator 인증 토큰(`k8s-aws-v1.xxx`)도 이 Pre-signed URL 위임 패턴을 사용합니다. `aws eks get-token`이 `GetCallerIdentity`에 대한 Pre-signed URL을 만들고, kube-apiserver가 그 URL을 STS에 호출해 요청자의 IAM principal을 확인합니다.

---

## Summary

이 문서에서 다룬 두 가지 서명 방식은 EKS에서 서로 다른 단계에 사용됩니다.

| | Asymmetric (RSA) | Symmetric (HMAC) |
|---|---|---|
| **Protocol** | OIDC / JWT | SigV4 |
| **Key** | EKS OIDC Provider의 private key로 서명, public key(JWKS)로 검증 | Secret Access Key에서 유도한 signing key로 서명과 검증 모두 수행 |
| **Purpose** | 워크로드 신원 증명 — "이 Pod이 누구인지" | AWS API 호출 인증 — "이 요청이 유효한지" |

Pod이 AWS API를 호출하기까지 두 서명 방식이 순서대로 사용됩니다.

=== "1. Pod creation"

    Pod Identity Webhook이 Pod spec에 환경 변수와 projected volume을 추가합니다. Pod이 노드에 스케줄되면 kubelet이 `TokenRequest` API를 호출하고, kube-apiserver가 OIDC Provider의 private key로 서명한 JWT를 반환합니다. kubelet은 이 JWT를 Pod 내부 파일로 마운트합니다.

=== "2. Identity verification (asymmetric)"

    AWS SDK가 마운트된 JWT를 읽어 `AssumeRoleWithWebIdentity`를 호출합니다. STS는 OIDC Provider의 JWKS에서 public key를 가져와 JWT 서명을 검증합니다. 서명이 유효하면 임시 자격 증명(Access Key ID, Secret Access Key, Session Token)을 반환합니다.

=== "3. AWS API call (symmetric)"

    SDK는 임시 자격 증명으로 SigV4 서명을 생성해 S3, DynamoDB 등 AWS 서비스를 호출합니다.
