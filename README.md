# .devcontainer

Claude Code を動かすための Dev Container 定義（AlmaLinux 9 ベース）。

VS Code の Dev Containers 拡張がこのディレクトリを読み、`/root/work` にワークスペースを
bind mount したコンテナを起動する。

## 構成

| ファイル | 役割 |
|---------|------|
| `devcontainer.json` | コンテナ定義。mount / DNS / initializeCommand / postCreateCommand |
| `Dockerfile` | AlmaLinux 9-minimal に tmux, git, gh, podman, python3, poppler-utils, jq を導入 |
| `storage.conf` | podman-in-podman 用のストレージ設定（fuse-overlayfs） |
| `.bashrc` | 対話シェル設定。tmux 自動起動 / 履歴共有 / git ブランチ付きプロンプト |
| `.tmux.conf` | prefix を `C-t` に変更、マウス操作を有効化 |

`.bashrc` と `.tmux.conf` は `postCreateCommand` で `~/` にシンボリックリンクされるため、
編集はこのリポジトリ側で行えばコンテナに即反映される。`~/.gitconfig` と `~/.config/gh` も
symlink だが、リンク先は `.container-home/` 側。

## コンテナ生成時に導入される CLI

`postCreateCommand` が `claude` を `https://claude.ai/install.sh` から `~/.local/bin` に
入れる（PATH は `Dockerfile` の `ENV` が通す）。イメージではなくコンテナ生成時に取得する
ため、作り直すたびに最新版になる。`gh` と `git` はイメージ側（`Dockerfile`）に入っている。

`postCreateCommand` をオブジェクト形式で書くと各コマンドは**並列**に実行されるため、互いの
生成物には依存できない。

> **警告:** `Dockerfile` の `ENV PATH` から `~/.local/bin` を外すと、claude のインストーラが
> `~/.bashrc` に PATH ブロックを追記する。`~/.bashrc` はこのリポジトリ内のファイルへの symlink
> なので、コンテナを作るたびにリポジトリが汚れる。`Dockerfile` を反映せず古いイメージのまま
> 使った場合も同じ。

## ホストをまたいで持ち越される状態

ワークスペースが共有ストレージ上にある前提で、コンテナ内のホーム相当のものは
ワークスペース配下の `.container-home/` に置き、別ホストで開いても引き継がれるようにしている。
名前付きボリュームは実体がそのホストのローカルディスクに作られるため使わない。

| コンテナ内 | 実体 | 設定箇所 |
|---|---|---|
| `/root/.claude` | `<workspace>/.container-home/claude` | `mounts` の bind mount |
| `/root/.claude.json` | `<workspace>/.claude.json` | `mounts` の bind mount |
| `~/.gitconfig` | `<workspace>/.container-home/gitconfig` | `postCreateCommand` の symlink |
| `~/.config/gh` | `<workspace>/.container-home/gh` | `postCreateCommand` の symlink |
| `$HISTFILE` | `<workspace>/.container-home/bash_history` | `containerEnv` |

Claude Code の状態は `~/.claude/`（履歴・セッション）と `~/.claude.json`（信頼済みディレクトリ、
MCP の承認など）に分かれているので、両方が要る。

`workspaceFolder` は `/root/work` に固定すること。会話履歴は cwd 由来のスラグ
（`projects/-root-work/`）で引かれるので、コンテナ内パスが変わると別ホストで履歴が繋がらない。

> **警告:** bind mount の source を消すと、podman がそれをディレクトリとして作り直し、
> Claude Code が設定を読めなくなる。`initializeCommand` が `.container-home/claude` と
> `.claude.json`（中身は `{}`）を先に用意しているのはこのため。

> **警告:** 同一のワークスペースを 2 ホストから同時に開くと、`history.jsonl` と `bash_history`
> への追記が調停されず取りこぼしが起きる。`shutdownAction: "none"` でコンテナが生き続けるため、
> 意図せず 2 ホストで生存しやすい（下記「コンテナを明示的に落とす」参照）。

### 認証情報

`~/.gitconfig` の credential helper は VS Code が接続のたびに書き換える。別ホストで書かれた
パスが残っている間は git が `No such file or directory` を吐くが、そのホストで VS Code が
接続すれば直る。`gh` 用の helper のパスは自動では直らないので、その場合は手で直す。

gh のトークンは `~/.config/gh/hosts.yml` に平文で入るため、`.container-home/` 以下は `700`
（`chmod -R go-rwx`）にしている。ブラウザ／デバイスフローの OAuth トークンは
`repo`, `gist`, `read:org`, `workflow` を持つ広いものなので、リポジトリを限定した
fine-grained PAT を `gh auth login --with-token` で入れる方が安全。

## 使い方

このリポジトリをワークスペース root の `.devcontainer/` として配置し、
VS Code で「Reopen in Container」を実行する。

```
<workspace>/
├── .devcontainer/     ← このリポジトリ
├── .container-home/   ← コンテナ内のホーム相当（git 管理外・700）
├── .claude.json       ← Claude Code の設定本体（git 管理外・600）
└── <各プロジェクト>/
```

## コンテナを明示的に落とす

`shutdownAction: "none"` は意図的な設定で、VS Code のウィンドウを閉じてもコンテナを
落とさない（tmux セッションと実行中のジョブを残すため）。VS Code 側の操作では止まらないので、
明示的に落とすには次のどちらかを使う。

- **VS Code**: Remote Explorer（リモートエクスプローラー）の Dev Containers 一覧で
  対象コンテナを右クリック →「Stop Container」。
- **ホストのシェル**: Dev Containers 拡張が付けるラベルで絞り込めるので、
  ワークスペースのパスから一意に止められる。

  ```bash
  podman ps --filter label=devcontainer.local_folder=<workspace の絶対パス>
  podman stop <container id>
  ```

イメージやビルドキャッシュまで捨てて作り直す場合は、VS Code の
「Dev Containers: Rebuild Container」（キャッシュも捨てるなら
「Rebuild Without Cache and Reopen in Container」）を使う。

## 環境依存の設定（fork 時は要変更）

- **DNS**: `runArgs` の `--dns-search=gie.internal` は特定ネットワーク向けの設定。
  別環境では削除するか自分の検索ドメインに置き換える。
- **`--privileged`**: podman-in-podman のためにホストの `/dev`（`/dev/fuse` を含む）を露出する。
  ホストに `/dev/fuse` が無い場合は `storage.conf` の driver を `vfs` に変更する。
- **`HISTFILE` / `mounts` のパス**: `/root/work` 固定を前提に絶対パスで書いている。
  `workspaceFolder` を変える場合は両方を合わせて変更する。
- **認証情報**: Claude Code も gh も共有ストレージ上のファイルで認証する（上記「認証情報」参照）。
  トークンを共有ストレージに置きたくない場合は、`containerEnv` に
  `"GH_TOKEN": "${localEnv:GH_TOKEN}"` を置いてホストの環境変数から渡す方式に切り替える。
