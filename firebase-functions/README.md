# ローカルルールテストと旧Functions試作

現在のiOSクライアントはFirestoreへ直接アクセスし、最終ルールで権限を制限するSpark無料構成です。

- `tests/` と開発依存パッケージはローカルのFirestoreルールテスト用です。
- `index.js` は以前のFunctions方式の試作コードです。現在のクライアントから呼び出しません。実行・デプロイ検証の対象ではありません。
- ルートの `firebase.json` はFirestoreルールのみを設定し、Functionsを含みません。
- 無料構成ではFunctionsをデプロイしないでください。Blazeへの変更は不要です。

テスト方法と本番ルールへの切替手順は、ルートのREADMEと `SECURITY_DEPLOYMENT.md` を参照してください。
