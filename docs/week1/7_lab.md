# Lab: EKS Cluster Setup


실습 코드는 [:octicons-mark-github-16: labs/week1/](https://github.com/pyy0715/eks-pratice/tree/main/labs/week1)에 있습니다.

## Initialize

```bash
cd labs/week1
terraform init
```

## Bootstrapping

### Select Endpoint Access Mode

=== "Public Only"
    ```bash
    terraform apply -var-file=public.tfvars
    ```

=== "Public + Private"
    ```bash
    terraform apply -var-file=public_and_private.tfvars
    ```

=== "Private Only"
    ```bash
    terraform apply -var-file=private.tfvars
    ```

    !!! warning "VPC 외부에서 kubectl 사용 불가"
        퍼블릭 엔드포인트가 없으므로 인터넷에서 API 서버에 직접 접근할 수 없습니다. SSM Session Manager로 워커 노드에 접속한 후 kubectl을 사용합니다.

    SSM으로 워커 노드에 접속합니다.

    ```bash
    # 실행 중인 노드의 Instance ID 조회
    INSTANCE_ID=$(aws ec2 describe-instances \
      --filters "Name=tag:eks:cluster-name,Values=$CLUSTER_NAME" \
                "Name=instance-state-name,Values=running" \
      --query "Reservations[0].Instances[0].InstanceId" \
      --output text)

    # SSM Session Manager로 접속
    aws ssm start-session --target $INSTANCE_ID
    ```

    접속 후 kubeconfig를 설정하고 kubectl을 사용합니다.

    ```bash
    sudo su -
    aws eks update-kubeconfig --region ap-northeast-2 --name $CLUSTER_NAME
    kubectl get nodes
    ```

### Cleanup

=== "Public Only"
    ```bash
    terraform destroy -var-file=public.tfvars
    ```

=== "Public + Private"
    ```bash
    terraform destroy -var-file=public_and_private.tfvars
    ```

=== "Private Only"
    ```bash
    terraform destroy -var-file=private.tfvars
    ```
