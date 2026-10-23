# ツーリングチャット

バイク仲間とのツーリング中の連絡を、短く・素早く・分かりやすくするiOSグループチャットアプリです。

FirebaseのSpark無料プランを前提とした開発中の構成です。GitHubのコード更新と、Firebaseへの本番反映・App Storeへの公開は別の作業です。

> 運転中のスマートフォン操作は想定していません。必ず安全な場所に停車して操作してください。

## 主な機能

- 6桁の参加コードによるグループ作成・参加
- Firestoreによるリアルタイムチャット
- 出発・到着・遅延・停止などの定型メッセージ送信と編集
- Apple MapsのURLによる現在地共有
- メンバーの到着状況、集合場所と集合時間の管理
- アプリ起動中のローカル通知
- 招待URLの共有、表示名・カラー・アイコンの設定

## 使用技術

- Swift / SwiftUI
- Firebase Authentication（匿名認証）
- Cloud Firestore / Firestore Security Rules
- Core Location / Apple Maps URL
- UserDefaults / Swift Package Manager

## セキュリティと無料構成

`firestore.rules` は更新版アプリ向けの最終ルールです。認証UIDに基づいてグループ参加者だけにアクセスを許可し、設定変更とグループ削除は所有者だけに制限します。参加・退出・到着状態は一括書き込みで人数と整合させます。削除中の新規投稿・参加を停止し、子データから順に削除します。通信失敗後は所有者が削除を再試行できます。

これらの保護は最終ルールをデプロイして初めて有効になります。旧版互換の移行用ルールは同等の保護を提供しません。更新版アプリと本番反映の順序は [SECURITY_DEPLOYMENT.md](SECURITY_DEPLOYMENT.md) を参照してください。

Cloud Functionsは本番利用しません。FCM/APNsによるアプリ終了中のリモートプッシュ通知は利用できません。起動中はFirestoreの変更からローカル通知を表示できます。Sparkの無料枠には上限があり、無制限に利用できる構成ではありません。

6桁コードにはサーバー側の試行回数制限がありません。コードは公開投稿に載せず、参加者へ直接共有してください。匿名認証のアカウントは、再インストール等で端末の認証状態を失うと同じUIDを復元できない場合があります。

## プロジェクト構成

```text
touring app/                    iOSアプリ本体
touring watch app Watch App/    Apple Watch向け試作コード
firebase-functions/             ルールテストとFunctions試作（本番未使用）
firestore.rules                 更新版向け最終ルール
firestore.migration.rules       旧版互換の一時的な移行用ルール
firebase.json                   最終ルールのデプロイ設定（Functionsを含まない）
SECURITY_DEPLOYMENT.md           無料構成・本番切替手順
```

## ローカルでの起動

1. リポジトリをクローンし、`touring app.xcodeproj` をXcodeで開きます。
2. 自分のFirebaseプロジェクトをSparkプランで作成し、匿名認証とFirestoreを有効にします。
3. Firebaseから取得した `GoogleService-Info.plist` を `touring app/` に配置します。項目例は `GoogleService-Info.plist.example` を参照してください。
4. 新規開発環境では自分のTeamとBundle Identifierを設定します。既存アプリを更新する場合は識別子を変更しないでください。
5. 新規のテスト用Firebaseには最終ルールを使用します。既存データがある環境は先に `SECURITY_DEPLOYMENT.md` を確認してください。
6. iPhoneシミュレーターまたは実機で実行します。

Firebase設定、秘密鍵、証明書、個人用Xcodeデータはコミットしないでください。Cloud Functionsをデプロイしたり、Blazeへ変更する必要はありません。

## テスト

ルールテストは実データを使わず、`demo-touring-app` のローカルエミュレーターで実行します。Node.js、Java、Firebase CLIが必要です。CLIとJavaの対応バージョンを合わせてください。

```bash
npm --prefix firebase-functions ci --ignore-scripts
# このリポジトリで検証済みのCLI。Java 11で実行しています。
npx firebase-tools@13.35.1 emulators:exec --only firestore --project demo-touring-app "npm --prefix firebase-functions run test:rules"
npm --prefix firebase-functions run check
npm --prefix firebase-functions run audit:production
```

権限テストは作成・参加・投稿・編集の正常系に加え、未認証アクセス、第三者による閲覧・なりすまし・無断変更、人数の不整合、削除中の新規書き込み、旧形式からの本人移行を検証します。これだけで実機の操作性や本番設定を保証するものではありません。

## スクリーンショットと公開範囲

個人情報・参加コード・位置情報の公開を避けるため、画像の掲載を停止しています。削除前のGit履歴には画像が残る場合があります。

個人開発として企画、要件整理、UI設計、Firebase構築、実装・検証を進めています。生成AIも活用し、提案コードを要件と照らし合わせながら改善しています。

このリポジトリはポートフォリオおよび技術確認を目的として公開しています。オープンソースライセンスは付与していません。無断での再配布、商用利用、アプリの複製はご遠慮ください。

