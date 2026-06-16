<div align="center">

<img src="assets/icon.png" width="140" alt="LiteSSH アイコン">

# LiteSSH

**ネイティブ macOS SSH クライアント — ターミナル、ファイルブラウザ、サーバー間転送をひとつのウィンドウに**

[ダウンロード](#ダウンロード) · [機能](#機能) · [クイックスタート](#クイックスタート) · [アーキテクチャ](#アーキテクチャ) · [DMG ビルド](#dmg-ビルド)

[English](README.md) · [中文](README.zh.md) · **日本語** · [Français](README.fr.md) · [Español](README.es.md) · [한국어](README.ko.md)

</div>

---

## ダウンロード

[**→ 最新リリースをダウンロード**](https://github.com/YOUR_USERNAME/LiteSSH/releases/latest)

macOS 13 Ventura 以降が必要です。`.dmg` を開き、**LiteSSH** をアプリケーションフォルダにドラッグしてください。

---

## 機能

| | |
|---|---|
| **フル機能ターミナル** | SwiftTerm 搭載、完全な ANSI/VT100 対応 — htop、nvtop、vim がそのまま動作 |
| **ファイルブラウザ** | サイドバーのドリルイン式ナビゲーション、アドレスバー・上位ディレクトリ・新規フォルダに対応 |
| **アップロード / ダウンロード** | ローカルファイルをドラッグしてアップロード、リモート項目を右クリックまたはドラッグしてダウンロード — **ファイルとフォルダの両方**に対応 |
| **サーバー間転送** | 複数のファイル／フォルダをチェック → 右クリック → 別のサーバーへ転送、リアルタイムの進捗表示 |
| **PEM / 秘密鍵認証** | パスワード、秘密鍵、AWS `.pem` ファイルに対応。パスフレーズは Keychain から自動供給 |
| **認証情報は一度だけ** | サーバー追加時にパスワードまたはパスフレーズを入力すると、以降の接続・ファイル操作で再入力不要 |
| **バイリンガル UI** | システムロケールに従い、日本語または英語で表示（中国語も対応） |
| **ダーク / ライトモード** | ターミナルのカラーテーマがシステム外観に自動追従 |

---

## クイックスタート

これは純粋な **Swift Package** です — `.xcodeproj` は不要です。

```
1. Xcode で Package.swift を開く
2. 依存関係の解決を待つ（SwiftTerm — github.com へのアクセスが必要）
3. スキームで "LiteSSH" を選択 → ▶ 実行
4. "+" をクリックしてサーバーを追加 — ホスト、ポート、ユーザー名、認証情報を一度だけ入力
```

---

## アーキテクチャ

LiteSSH は SSH プロトコルを自前で実装せず、macOS 標準搭載の OpenSSH（`/usr/bin/ssh`、`/usr/bin/sftp`）に処理を委譲します。

**接続の再利用。** 最初の接続が ControlMaster になります。以降のファイル操作はすべて同じ ControlPath ソケットを共有するため、再認証は不要です。

**認証情報のセキュリティ。** パスワードとパスフレーズは macOS Keychain に保存されます。実行時に `AskPassHelper` が一時的な `SSH_ASKPASS` スクリプトを生成し、ssh/sftp サブプロセスが環境変数経由で非対話的にシークレットを取得します。プロセス引数に平文のパスワードは現れません。

**ファイル転送。** スペースを含むパスのパース問題を回避するため、scp ではなく `sftp -b <batchfile>` を使用します。ディレクトリの再帰転送には `get -r` / `put -r` を使用します。サーバー間転送はローカルの一時ディレクトリを経由します。

**パイプの安全性。** プロセス実行中、stdout と stderr の両パイプを `readabilityHandler` で並行読み取りし、64 KB パイプバッファの詰まりによるデッドロックを防止します。

---

## プロジェクト構成

```
Sources/LiteSSH/
├── Models/
│   ├── ServerProfile.swift          # サーバー設定モデル
│   └── RemoteFile.swift             # リモートファイルエントリ
├── Services/
│   ├── SSHConnection.swift          # 接続コア + ControlMaster 管理
│   ├── ProcessRunner.swift          # サブプロセスラッパー（並行パイプ読み取り）
│   ├── ProfileStore.swift           # 設定の永続化
│   ├── KeychainHelper.swift         # Keychain 読み書き
│   └── AskPassHelper.swift          # SSH_ASKPASS 非対話型認証情報供給
├── ViewModels/
│   ├── SessionStore.swift           # Profile → SSHConnection マッピング
│   └── FileBrowserStore.swift       # ファイルブラウザ状態（パス + 戻りスタック）
├── Views/
│   ├── Sidebar/
│   │   ├── ServerListView.swift     # サイドバー: サーバーリスト + ファイルブラウザ列
│   │   └── ServerEditView.swift     # サーバーの追加 / 編集フォーム
│   ├── Terminal/
│   │   ├── TerminalContainerView.swift
│   │   └── TerminalViewRegistry.swift
│   ├── Files/
│   │   └── CrossTransferSheet.swift # サーバー間転送 UI
│   ├── DetailView.swift
│   └── ContentView.swift
├── Localization.swift               # L10n.s(中国語, English)
└── LiteSSHApp.swift                 # @main エントリーポイント + AppDelegate
```

---

## DMG ビルド

```bash
cd "SSH tool/LiteSSH"
chmod +x build_dmg.sh
./build_dmg.sh
```

プロジェクトルートに `LiteSSH-1.0.dmg` と `LiteSSH.app` が出力されます。スクリプトはリリースバイナリのコンパイル、アプリアイコンの生成、アドホック署名、Applications シンボリックリンク付き DMG のパッケージングを行います。他のマシンへの配布には、アドホック署名を Developer ID 証明書による署名に置き換えてください。

---

## 依存関係

| 依存関係 | バージョン | 役割 |
|---|---|---|
| [SwiftTerm](https://github.com/migueldeicaza/SwiftTerm) | ≥ 1.0 | ターミナルエミュレーター |
| macOS OpenSSH | 標準搭載 | SSH / SFTP プロトコル |
| macOS Keychain | 標準搭載 | 認証情報の安全な保存 |

**動作環境:** macOS 13 Ventura 以降 · Xcode 15+（開発時のみ）

---

## ライセンス

Apache 2.0
