# clip-shelf - 履歴テーブル仕様（DB）

> **機能**: [clip-shelf](./index.md)
> **ステータス**: 下書き
> **DBMS**: SQLite 3（GRDB.swift 経由）

## 概要

clip-shelf のローカル SQLite データベース `history.sqlite` のスキーマ定義。履歴本体・ピン留め・FTS5 全文検索・設定 KV の4テーブルを持つ。

## テーブル一覧

| テーブル名 | 説明 |
|:----------|:-----|
| `history` | クリップボード履歴本体 |
| `pinned_items` | ピン留めされた `history.id` への参照 |
| `history_fts` | `history` のテキスト本文に対する FTS5 仮想テーブル |
| `settings_kv` | アプリ設定の KV ストア |

## スキーマ

### history

| カラム | 型 | NULL許可 | デフォルト | 説明 |
|:-------|:---|:---------|:----------|:-----|
| `id` | TEXT | NO | - | 主キー。UUID 文字列 |
| `kind` | TEXT | NO | - | `'text'` / `'image'` / `'file'` |
| `text_payload` | TEXT | YES | NULL | プレーンテキスト本文 |
| `rtf_payload` | BLOB | YES | NULL | RTF データ |
| `image_payload` | BLOB | YES | NULL | 画像生バイト |
| `image_type` | TEXT | YES | NULL | UTI 文字列 e.g. `public.png` |
| `image_hash` | TEXT | YES | NULL | 画像 payload の SHA-256（重複判定用） |
| `file_path` | TEXT | YES | NULL | ファイル絶対パス |
| `source_app` | TEXT | YES | NULL | コピー元アプリのバンドルID |
| `created_at` | INTEGER | NO | unixepoch() | 作成日時（Unix epoch 秒） |
| `last_used_at` | INTEGER | YES | NULL | 最終利用日時 |
| `size_bytes` | INTEGER | NO | 0 | payload の総バイト数 |

### pinned_items

| カラム | 型 | NULL許可 | デフォルト | 説明 |
|:-------|:---|:---------|:----------|:-----|
| `history_id` | TEXT | NO | - | `history.id` への参照（主キー） |
| `pinned_at` | INTEGER | NO | unixepoch() | ピン留めした時刻 |
| `display_order` | INTEGER | NO | 0 | 上位での並び順（小さいほど上） |

### history_fts（FTS5 仮想テーブル）

```sql
CREATE VIRTUAL TABLE history_fts USING fts5(
    text_payload,
    content='history',
    content_rowid='rowid',
    tokenize='unicode61'
);
```

`history.text_payload` を INSERT / UPDATE / DELETE するトリガーで同期。インデックス対象は本文先頭 1MB に制限。

### settings_kv

| カラム | 型 | NULL許可 | デフォルト | 説明 |
|:-------|:---|:---------|:----------|:-----|
| `key` | TEXT | NO | - | 設定キー（主キー） |
| `value` | BLOB | NO | - | JSON エンコードされた値 |
| `updated_at` | INTEGER | NO | unixepoch() | 更新日時 |

## 制約

| 制約名 | 種別 | 対象 | 説明 |
|:-------|:-----|:-----|:-----|
| `pk_history` | PRIMARY KEY | `history.id` | |
| `ck_history_kind` | CHECK | `history.kind IN ('text','image','file')` | 型の正当性 |
| `ck_history_payload` | CHECK | 型ごとに対応 payload が NOT NULL | text なら text_payload、image なら image_payload、file なら file_path |
| `pk_pinned` | PRIMARY KEY | `pinned_items.history_id` | |
| `fk_pinned_history` | FOREIGN KEY | `pinned_items.history_id → history.id ON DELETE CASCADE` | 履歴削除時にピンも消える |
| `pk_settings` | PRIMARY KEY | `settings_kv.key` | |

`ck_history_payload` の SQL 例:

```sql
CHECK (
    (kind = 'text'  AND text_payload  IS NOT NULL) OR
    (kind = 'image' AND image_payload IS NOT NULL) OR
    (kind = 'file'  AND file_path     IS NOT NULL)
)
```

## インデックス

| インデックス名 | 対象 | 種別 | 用途 |
|:-------------|:----|:-----|:-----|
| `idx_history_created_at` | `history(created_at DESC)` | BTREE | 直近順での一覧取得 |
| `idx_history_kind_created` | `history(kind, created_at DESC)` | BTREE | 型フィルタ付き一覧 |
| `idx_history_image_hash` | `history(image_hash)` | BTREE | 画像の重複判定 |
| `idx_history_text_payload_prefix` | `history(text_payload)` | BTREE | テキスト重複判定（短文用） |
| `idx_pinned_order` | `pinned_items(display_order, pinned_at)` | BTREE | ピン留めの並び順表示 |

長文テキストの重複判定は `text_payload` の長さで分岐:
- 1024 バイト以下 → `idx_history_text_payload_prefix` で直接一致検索
- 1024 バイト超 → SHA-256（`image_hash` カラムを流用、命名は本来 `payload_hash` だが互換維持のため）

## リレーションシップ

```mermaid
erDiagram
    history ||--o| pinned_items : "0..1"
    history ||--|| history_fts : "1:1 (FTS rowid)"
    history {
        TEXT id PK
        TEXT kind
        TEXT text_payload
        BLOB image_payload
        TEXT image_hash
        TEXT file_path
        INTEGER created_at
        INTEGER last_used_at
    }
    pinned_items {
        TEXT history_id PK_FK
        INTEGER pinned_at
        INTEGER display_order
    }
    history_fts {
        TEXT text_payload
        INTEGER rowid
    }
    settings_kv {
        TEXT key PK
        BLOB value
        INTEGER updated_at
    }
```

| リレーション | 種別 | 削除時の動作 |
|:------------|:-----|:------------|
| `history` ↔ `pinned_items` | 1:0..1 | `ON DELETE CASCADE`（履歴削除でピンも削除） |
| `history` ↔ `history_fts` | 1:1（rowid） | トリガーで同期 |

## トリガー

`history` の INSERT / UPDATE / DELETE で `history_fts` を同期。

```sql
CREATE TRIGGER trg_history_ai AFTER INSERT ON history BEGIN
    INSERT INTO history_fts(rowid, text_payload)
    VALUES (new.rowid, substr(new.text_payload, 1, 1048576));
END;

CREATE TRIGGER trg_history_au AFTER UPDATE OF text_payload ON history BEGIN
    UPDATE history_fts
    SET text_payload = substr(new.text_payload, 1, 1048576)
    WHERE rowid = old.rowid;
END;

CREATE TRIGGER trg_history_ad AFTER DELETE ON history BEGIN
    DELETE FROM history_fts WHERE rowid = old.rowid;
END;
```

## データライフサイクル

| イベント | トリガー | 動作 |
|:--------|:--------|:-----|
| 作成 | `ClipboardMonitor` が変更検知 | `history` に INSERT、`history_fts` に同期 |
| 更新 | `PasteService.touch` 呼び出し | `last_used_at` を現在時刻に UPDATE |
| 重複検知 | 同内容を再コピー | 既存行の `created_at` を UPDATE（最上位に移動）し、新規 INSERT はしない |
| ピン留め | UI 操作 | `pinned_items` に INSERT |
| ピン解除 | UI 操作 | `pinned_items` から DELETE |
| 上限超過 | `add` 完了後 | ピン留めされていない最古行を `LIMIT n` で DELETE |
| 全削除 | 設定画面 | `DELETE FROM history`（オプションで `WHERE id NOT IN (SELECT history_id FROM pinned_items)`） |
| アプリアンインストール | ファイル削除 | `~/Library/Application Support/clip-shelf/` を rm |

## データ整合性

| ルール | 説明 | 強制方法 |
|:-------|:-----|:---------|
| 型と payload の対応 | text 型なら text_payload を必ず持つ など | CHECK 制約 |
| ピン留め参照 | 削除済 ID は参照させない | FOREIGN KEY + CASCADE |
| 画像ハッシュ | 画像 INSERT 時に必ず `image_hash` を埋める | アプリ層で保証（DB の `ck_image_hash_when_image` も任意で追加可能） |
| FTS 同期 | `history` と `history_fts` の差異がない | INSERT/UPDATE/DELETE トリガー |

## マイグレーション

`GRDB.DatabaseMigrator` を起動時に実行。

| 識別子 | 内容 | ロールバック |
|:------|:-----|:----------|
| `v1_initial` | `history`, `pinned_items`, `settings_kv` 作成 | 起動失敗時はファイル削除 |
| `v2_fts` | `history_fts` 仮想テーブル + 同期トリガー | テーブル DROP |
| `v3_image_hash` | `history.image_hash` カラム追加 + インデックス | 個人利用なのでロールバックは不要、再構築可 |

## 初期データ

| テーブル | 初期データ |
|:--------|:----------|
| `settings_kv` | デフォルト設定値を v1 マイグレーションで投入（`historyLimit=500` など） |
| `history` | なし |
| `pinned_items` | なし |

## パフォーマンス考慮

| 観点 | 対策 |
|:-----|:-----|
| 想定レコード数 | 1,000〜10,000 件（個人利用） |
| 主要クエリ | (1) 直近 N 件取得（`created_at DESC LIMIT N`） (2) 型フィルタ (3) FTS 検索 |
| ボトルネック | 画像 BLOB の I/O。`SELECT` の射影で `image_payload` を読み込まないよう、サムネイル一覧では `image_payload` を除外する |
| バキューム | アプリ起動時に `PRAGMA auto_vacuum=INCREMENTAL` を有効化、終了時に `PRAGMA incremental_vacuum` |

## 制限事項

- 画像本体を BLOB で保存するため、巨大画像が大量にあると DB ファイルサイズが膨らむ。50MB 超の画像は履歴化しないことで対処（[clipboard-monitor-spec.md](./clipboard-monitor-spec.md) 参照）
- SQLite なので同時書き込みは 1 接続に直列化される（WAL でも書き込みは直列）。クリップボード監視 + UI 操作は数秒に1回程度なので問題なし
- FTS5 の言語別トークナイザは `unicode61` のみ。日本語の形態素解析はしないため、検索は単純な部分文字列マッチに近い

## 関連仕様

- [persistence-spec.md](./persistence-spec.md) — テーブルを使う `HistoryService` / `SettingsStore`
- [clipboard-monitor-spec.md](./clipboard-monitor-spec.md) — INSERT の発生源
- [history-spec.md](./history-spec.md) — 検索クエリの仕様
- [settings-spec.md](./settings-spec.md) — `settings_kv` のキー一覧
