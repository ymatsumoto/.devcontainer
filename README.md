# .devcontainer

Claude Code を動かすための Dev Container 定義（AlmaLinux 9 ベース）。

VS Code の Dev Containers 拡張がこのディレクトリを読み、`/root/work` にワークスペースを
bind mount したコンテナを起動する。

## 構成

| ファイル | 役割 |
|---------|------|
| `devcontainer.json` | コンテナ定義。mount / DNS / postCreateCommand / VS Code 拡張 |
| `Dockerfile` | AlmaLinux 9-minimal に tmux, git, gh, podman, python3, poppler-utils, jq を導入 |
| `storage.conf` | podman-in-podman 用のストレージ設定（fuse-overlayfs） |
| `.bashrc` | 対話シェル設定。tmux 自動起動 / 履歴共有 / git ブランチ付きプロンプト |
| `.tmux.conf` | prefix を `C-t` に変更、マウス操作を有効化 |

`.bashrc` と `.tmux.conf` は `postCreateCommand` で `~/` にシンボリックリンクされるため、
編集はこのリポジトリ側で行えばコンテナに即反映される。

## コンテナ生成時に導入される CLI

`postCreateCommand` が以下を `~/.local/bin` に入れる（PATH は `Dockerfile` の `ENV` が通す）。
イメージではなくコンテナ生成時に取得するため、作り直すたびに最新版になる。

| CLI | 取得元 |
|-----|--------|
| `claude` | `https://claude.ai/install.sh` |
| `antigravity` | `https://antigravity.google/cli/install.sh` |
| `codex` | `https://chatgpt.com/codex/install.sh` |

`gh` と `git` はイメージ側（`Dockerfile`）に入っているのでここには含まれない。

> **注記:** `postCreateCommand` をオブジェクト形式で書くと各コマンドは**並列**に実行される。
> したがって互いの生成物に依存できない。`~/.local/bin` は各インストーラが自分で作る。

> **警告:** codex の公式インストーラは既定で対話的に質問し、さらに `~/.bashrc` へ
> `# >>> Codex installer >>>` ブロックを追記しようとする。この devcontainer では `~/.bashrc` が
> **このリポジトリ内のファイルへのシンボリックリンク**なので、そのままだとコンテナを作るたびに
> リポジトリが汚れる（`.bashrc` に残っていた `# Added by Antigravity CLI installer` の行が
> まさにこの経路で混入したもの）。対策は2つとも `postCreateCommand` の外に置いてある:
>
> - `containerEnv` の `CODEX_NON_INTERACTIVE=1` が対話を止める
> - `Dockerfile` の `ENV PATH` が `~/.local/bin` を通すので、インストーラの `add_to_path()` が
>   早期 return してプロファイルに一切触れない
>
> したがって **`ENV PATH` を消したり `Dockerfile` を反映せずに古いイメージのまま使うと、
> `.bashrc` が書き換えられる**。

> **注記:** codex の実体は `~/.codex/packages/standalone/releases/<version>/` に置かれ
> （`codex` 258 MB + `codex-code-mode-host` 69 MB で計 320 MB）、`~/.local/bin/codex` は
> そこへの symlink になる。`~/.codex` は名前付きボリュームではないため、コンテナを
> 作り直すたびに再ダウンロードが発生する。

## 使い方

このリポジトリをワークスペース root の `.devcontainer/` として配置し、
VS Code で「Reopen in Container」を実行する。

```
<workspace>/
├── .devcontainer/    ← このリポジトリ
└── <各プロジェクト>/
```

## 環境依存の設定（fork 時は要変更）

- **DNS**: `runArgs` の `--dns=172.16.0.1` / `--dns=172.16.2.3` / `--dns-search=gie.internal`
  は特定ネットワーク向けの設定。podman/WSL のリゾルバプロキシが単一ラベルのクエリを
  黙って落とし、短い名前の解決に毎回 20 秒かかる問題を回避するために直接指定している。
  別環境では削除するか自分のリゾルバに置き換える。
- **`--privileged`**: podman-in-podman のためにホストの `/dev`（`/dev/fuse` を含む）を露出する。
  ホストに `/dev/fuse` が無い場合は `storage.conf` の driver を `vfs` に変更する。
- **`ANTHROPIC_API_KEY`**: `containerEnv` でホストの環境変数を引き継ぐ。値はリポジトリに含まない。
- **`claude-code-history` volume**: `/root/.claude` を名前付きボリュームに逃がし、
  会話履歴と認証情報をコンテナ再作成後も保持する。
