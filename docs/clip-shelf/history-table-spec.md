# clip-shelf - 履歴エンティティ仕様（DB）

> **機能**: [clip-shelf](./index.md)
> **ステータス**: 下書き
> **永続化**: SwiftData（裏で SQLite を生成）

## 概要

clip-shelf のローカル永続化ストア `HistoryStore.sqlite`（SwiftData が内部生成）のスキーマ定義。`HistoryItem` を中心とする SwiftData の `@Model` 構成と、`VersionedSchema` を使ったマイグレーション戦略をまとめる。

> アプリ設定（`historyLimit` 等）は本ストアではなく `UserDefaults` に保存する。設定キー一覧は [settings-spec.md](./settings-spec.md) を参照。

## エンティティ一覧

| エンティティ | 役割 |
|:----------|:-----|
| `HistoryItem` | クリップボード履歴本体。テキスト / 画像 / ファイル参照を 1 つのモデルで表現し、ピン留め状態もフラットに保持する |

ピン留めを別エンティティ（リレーション）にしない理由は、SwiftData では多対 0..1 のリレーションが冗長で、ピン留め状態がアイテム 1 件に対し最大 1 件だけ存在するため、単純なオプショナル属性で十分なため。

## スキーマ（v1）

### HistoryItem

```swift
import SwiftData

enum HistoryKind: String, Codable {
    case text
    case image
    case file
}

@Model
final class HistoryItem {
    @Attribute(.unique) var id: UUID
    var kindRaw: String

    // テキスト系
    var textPayload: String?
    var rtfPayload: Data?

    // 画像系
    var imagePayload: Data?            // PNG/JPEG/TIFF の生バイト
    var imageType: String?             // UTI 文字列 e.g. "public.png"

    // ファイル系
    var filePath: String?

    // 重複判定 / メタ
    var payloadHash: String?           // SHA-256（画像 or 長文テキスト）
    var sourceApp: String?             // コピー元アプリのバンドル ID
    var createdAt: Date
    var lastUsedAt: Date?
    var sizeBytes: Int

    // ピン留め
    var pinnedAt: Date?                // nil = 非ピン
    var pinnedOrder: Int               // 0 = 非ピン、>0 で上位ほど小さい

    init(id: UUID = UUID(),
         kind: HistoryKind,
         createdAt: Date = .now,
         sizeBytes: Int = 0) {
        self.id = id
        self.kindRaw = kind.rawValue
        self.createdAt = createdAt
        self.sizeBytes = sizeBytes
        self.pinnedOrder = 0
    }
}
```

### 属性一覧

| 属性 | 型 | NULL許可 | 説明 |
|:-----|:---|:---------|:-----|
| `id` | `UUID` | NO | 一意キー（`@Attribute(.unique)`） |
| `kindRaw` | `String` | NO | `HistoryKind` の rawValue（`text` / `image` / `file`） |
| `textPayload` | `String?` | YES | プレーンテキスト本文 |
| `rtfPayload` | `Data?` | YES | RTF データ |
| `imagePayload` | `Data?` | YES | 画像生バイト |
| `imageType` | `String?` | YES | UTI 文字列 |
| `filePath` | `String?` | YES | ファイル絶対パス |
| `payloadHash` | `String?` | YES | SHA-256 ハッシュ（画像 or 長文テキスト） |
| `sourceApp` | `String?` | YES | コピー元アプリのバンドル ID |
| `createdAt` | `Date` | NO | 作成日時 |
| `lastUsedAt` | `Date?` | YES | 最終利用日時 |
| `sizeBytes` | `Int` | NO | payload の総バイト数 |
| `pinnedAt` | `Date?` | YES | ピン留め日時。nil = 非ピン |
| `pinnedOrder` | `Int` | NO | ピン留め内の並び順（0 は非ピン扱い） |

### 不変条件（アプリ層で保証）

SwiftData は CHECK 制約をサポートしないため、以下はアプリ層の `HistoryService.add()` で保証する。

| ルール | 内容 |
|:------|:-----|
| `kindRaw` の値 | `HistoryKind.allCases.map(\.rawValue)` のいずれか |
| `kind` と payload の対応 | `.text` → `textPayload` 必須、`.image` → `imagePayload` 必須、`.file` → `filePath` 必須 |
| `imagePayload` 存在時 | `payloadHash` も埋める |
| `pinnedAt == nil` 時 | `pinnedOrder == 0` |

## 検索 / 取得パターン

| ユースケース | 実装 |
|:-----------|:-----|
| 直近 N 件 | `FetchDescriptor<HistoryItem>(sortBy: [.init(\.pinnedAt, order: .reverse), .init(\.createdAt, order: .reverse)])` + `fetchLimit = N` |
| 型フィルタ | `#Predicate { $0.kindRaw == kind.rawValue }` |
| ピン留めのみ | `#Predicate { $0.pinnedAt != nil }` |
| テキスト検索 | `#Predicate { $0.textPayload?.localizedStandardContains(query) ?? false }` |
| 画像重複判定 | `#Predicate { $0.payloadHash == hash && $0.kindRaw == "image" }` |
| 長文テキスト重複判定 | `#Predicate { $0.payloadHash == hash && $0.kindRaw == "text" }` |
| 短文テキスト重複判定 | `#Predicate { $0.textPayload == text }` |

### 重複判定の長短分岐

`textPayload` の長さで分岐する:

- 1024 バイト以下 → `textPayload` の完全一致比較
- 1024 バイト超 → SHA-256 を `payloadHash` に格納し、ハッシュ一致で重複判定

これにより長文テキストの比較コストを抑える。

## データライフサイクル

| イベント | トリガー | 動作 |
|:--------|:--------|:-----|
| 作成 | `ClipboardMonitor` が変更検知 | `HistoryItem` を `ModelContext.insert` |
| 更新 | `PasteService.touch` 呼び出し | `lastUsedAt` を現在時刻に更新 |
| 重複検知 | 同内容を再コピー | 既存項目の `createdAt` を更新（最上位に移動）し、新規 insert はしない |
| ピン留め | UI 操作 | `pinnedAt = .now`、`pinnedOrder` を採番 |
| ピン解除 | UI 操作 | `pinnedAt = nil`、`pinnedOrder = 0` |
| 上限超過 | `add` 完了後 | `pinnedAt == nil` の中から最古をフェッチして delete |
| 全削除 | 設定画面 | `try modelContext.delete(model: HistoryItem.self, where: ...)`（オプションで `pinnedAt != nil` を残す） |
| アプリアンインストール | ファイル削除 | `~/Library/Application Support/clip-shelf/` を rm |

## マイグレーション

`VersionedSchema` を使ってバージョンを型として表現し、`SchemaMigrationPlan` で繋ぐ。

```swift
enum SchemaV1: VersionedSchema {
    static var versionIdentifier: Schema.Version = .init(1, 0, 0)
    static var models: [any PersistentModel.Type] {
        [HistoryItem.self]
    }
}

enum ClipShelfMigrationPlan: SchemaMigrationPlan {
    static var schemas: [any VersionedSchema.Type] {
        [SchemaV1.self]
    }
    static var stages: [MigrationStage] { [] }
}
```

| 識別子 | 内容 | 種別 |
|:------|:-----|:-----|
| `SchemaV1` | 初版（`HistoryItem`） | 初期スキーマ |

将来追加のステージは:

- **lightweight**: 属性追加 / オプショナル化など、データ変換が不要な変更
- **custom**: データ移行が必要な変更（例: 別エンティティへの分割）

### 起動時の自動適用

```swift
let container = try ModelContainer(
    for: HistoryItem.self,
    migrationPlan: ClipShelfMigrationPlan.self,
    configurations: ModelConfiguration(
        url: storeURL,
        cloudKitDatabase: .none
    )
)
```

マイグレーションに失敗した場合は、ユーザーに「履歴をリセットして起動する」選択肢を提示する（ストアファイル削除 → 再生成）。

## 初期データ

| エンティティ | 初期データ |
|:----------|:----------|
| `HistoryItem` | なし |

アプリ設定の初期値は `UserDefaults.register(defaults:)` で起動時に登録する（[settings-spec.md](./settings-spec.md) 参照）。

## パフォーマンス考慮

| 観点 | 対策 |
|:-----|:-----|
| 想定レコード数 | 1,000〜10,000 件（個人利用） |
| 主要クエリ | (1) 直近 N 件取得 (2) 型フィルタ (3) `localizedStandardContains` 検索 |
| ボトルネック | 画像 BLOB の I/O。サムネイル一覧では `imagePayload` を取らず、必要な属性のみ `propertiesToFetch` で射影する |
| 大量 BLOB | `Data` 属性は SwiftData 内部で外部ファイルに分離されない。サイズ上限を [clipboard-monitor-spec.md](./clipboard-monitor-spec.md) のサイズ制限で抑える |

## 制限事項

- 画像本体を `Data` で保存するため、巨大画像が大量にあるとストアサイズが膨らむ。50MB 超の画像は履歴化しないことで対処（[clipboard-monitor-spec.md](./clipboard-monitor-spec.md) 参照）
- 全文検索は `localizedStandardContains` の部分一致のみ。FTS5 は使わない
- SwiftData の `@Predicate` は SQLite のクエリに変換できる範囲に限られるため、複雑な条件はアプリ側でフィルタする
- ストアファイルは平文 SQLite。暗号化はしない（FileVault に依存）

## 関連仕様

- [persistence-spec.md](./persistence-spec.md) — モデルを使う `HistoryService` の API
- [clipboard-monitor-spec.md](./clipboard-monitor-spec.md) — insert の発生源
- [history-spec.md](./history-spec.md) — 検索クエリの仕様
- [settings-spec.md](./settings-spec.md) — アプリ設定の保存先（UserDefaults）
