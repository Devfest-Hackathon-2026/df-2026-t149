#!/usr/bin/env bash
# Google Cloud の初回セットアップ。何度流しても壊れないように、すでにあるものは飛ばす。
# 使い方: PROJECT_ID=xxx ./scripts/gcp-bootstrap.sh
# Places API のキーを Secret Manager に入れる操作だけは、キーを手元に出さないため含めない（docs/setup.md）。
set -euo pipefail

: "${PROJECT_ID:?PROJECT_ID を指定してください}"
REGION="${REGION:-asia-northeast1}"
GITHUB_REPO="${GITHUB_REPO:-UME0325/DevFest-Hackathon-2026}"
REPO_NAME="uramichi"                       # Artifact Registry のリポジトリ名
RUNTIME_SA="uramichi-api"                  # Cloud Run が実行時に使う
DEPLOY_SA="github-deployer"                # GitHub Actions がデプロイに使う
POOL="github"
PROVIDER="github"

gcloud config set project "$PROJECT_ID" >/dev/null
PROJECT_NUMBER="$(gcloud projects describe "$PROJECT_ID" --format='value(projectNumber)')"

echo "== API を有効にする"
gcloud services enable \
  places.googleapis.com run.googleapis.com artifactregistry.googleapis.com \
  secretmanager.googleapis.com firestore.googleapis.com \
  iamcredentials.googleapis.com sts.googleapis.com \
  cloudbuild.googleapis.com aiplatform.googleapis.com

echo "== Artifact Registry"
gcloud artifacts repositories describe "$REPO_NAME" --location "$REGION" >/dev/null 2>&1 ||
  gcloud artifacts repositories create "$REPO_NAME" --repository-format docker --location "$REGION"

echo "== サービスアカウント"
for sa in "$RUNTIME_SA" "$DEPLOY_SA"; do
  gcloud iam service-accounts describe "$sa@$PROJECT_ID.iam.gserviceaccount.com" >/dev/null 2>&1 ||
    gcloud iam service-accounts create "$sa"
done

bind() { # bind <service-account> <role>
  gcloud projects add-iam-policy-binding "$PROJECT_ID" \
    --member "serviceAccount:$1@$PROJECT_ID.iam.gserviceaccount.com" --role "$2" --condition=None >/dev/null
}
# 実行時: Firestore の読み書き、Secret の参照、Vertex AI の呼び出しだけ
bind "$RUNTIME_SA" roles/datastore.user
bind "$RUNTIME_SA" roles/secretmanager.secretAccessor
bind "$RUNTIME_SA" roles/aiplatform.user # Geminiちゃん（Vertex AI）を呼ぶ
# デプロイ時: イメージを置いて、Cloud Run を更新するだけ
bind "$DEPLOY_SA" roles/artifactregistry.writer
# --allow-unauthenticated は allUsers の設定を伴い、run.developer では足りない（毎回のデプロイが失敗する）
bind "$DEPLOY_SA" roles/run.admin
gcloud iam service-accounts add-iam-policy-binding "$RUNTIME_SA@$PROJECT_ID.iam.gserviceaccount.com" \
  --member "serviceAccount:$DEPLOY_SA@$PROJECT_ID.iam.gserviceaccount.com" \
  --role roles/iam.serviceAccountUser >/dev/null

echo "== Workload Identity Federation（JSON 鍵を使わず GitHub Actions から入る）"
gcloud iam workload-identity-pools describe "$POOL" --location global >/dev/null 2>&1 ||
  gcloud iam workload-identity-pools create "$POOL" --location global --display-name "GitHub Actions"
gcloud iam workload-identity-pools providers describe "$PROVIDER" --location global --workload-identity-pool "$POOL" >/dev/null 2>&1 ||
  gcloud iam workload-identity-pools providers create-oidc "$PROVIDER" \
    --location global --workload-identity-pool "$POOL" \
    --issuer-uri "https://token.actions.githubusercontent.com" \
    --attribute-mapping "google.subject=assertion.sub,attribute.repository=assertion.repository" \
    --attribute-condition "assertion.repository=='$GITHUB_REPO'"
# このリポジトリからだけ、デプロイ用アカウントとして振る舞える
gcloud iam service-accounts add-iam-policy-binding "$DEPLOY_SA@$PROJECT_ID.iam.gserviceaccount.com" \
  --member "principalSet://iam.googleapis.com/projects/$PROJECT_NUMBER/locations/global/workloadIdentityPools/$POOL/attribute.repository/$GITHUB_REPO" \
  --role roles/iam.workloadIdentityUser >/dev/null

cat <<MSG

== 完了。GitHub の Settings > Secrets and variables > Actions > Variables に次の 3 つを登録してください
GCP_PROJECT_ID     = $PROJECT_ID
GCP_DEPLOY_SA      = $DEPLOY_SA@$PROJECT_ID.iam.gserviceaccount.com
GCP_WIF_PROVIDER   = projects/$PROJECT_NUMBER/locations/global/workloadIdentityPools/$POOL/providers/$PROVIDER
MSG
