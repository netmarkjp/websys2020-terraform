# WEBSYS2020 Terraformサンプル

クラウドコンピューティングの講義で利用するTerraformサンプル

## 実行の前提条件

- Terraformがインストールされている
    - Terraform v0.12.25、 provider.aws v2.62.0 でテスト済み
    - https://learn.hashicorp.com/terraform/getting-started/install

## 実行方法

```sh
terraform init
terraform plan
terraform apply

# 終わったら
terraform destroy
```
