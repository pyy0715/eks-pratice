# DNS Record Migration Notes

## Hostname Layout

`nginx.${MyDomain}`
:   기존 ALB (Ingress가 소유)

`gw.${MyDomain}`
:   새 ALB (Gateway가 소유)

두 hostname을 독립 DNS record로 분리하는 이유는 마이그레이션 도중 롤백 여지를 남기기 위함입니다. 같은 이름에 바로 덮어쓰면 External-DNS sync 지연 구간에서 레코드가 깨지는 시점이 생깁니다.

## Verification

```bash
# Ingress와 Gateway가 각각 올바른 ALB로 분기되는지 확인
dig +short nginx.${MyDomain}
dig +short gw.${MyDomain}

# External-DNS 로그
kubectl -n external-dns logs deploy/external-dns --tail=50
```

## Final Cutover

Canary 검증이 끝나면 두 가지 경로 중 하나를 택합니다.

- `nginx.${MyDomain}` hostname을 HTTPRoute로 이관해 기존 Ingress를 삭제
- Route53 weighted record로 두 ALB에 가중치를 분배한 뒤 점진 전환

본 실습은 전자 경로를 사용합니다. `30-canary-shift/httproute-weighted.yaml`를 참고합니다.
