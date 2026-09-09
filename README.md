# .devcontainer

Claude Code を動かすための Dev Container 定義（AlmaLinux 9 ベース）。

VS Code の Dev Containers 拡張がこのディレクトリを読み、`/root/work` にワークスペースを
bind mount したコンテナを起動する。

## 構成

| ファイル | 役割 |
|---------|------|
| `devcontainer.json` | コンテナ定義。mount / DNS / postCreateCommand |
| `Dockerfile` | AlmaLinux 9-minimal に tmux, git, gh, podman, python3, poppler-utils, jq を導入 |
| `storage.conf` | podman-in-podman 用のストレージ設定（fuse-overlayfs） |
| `.bashrc` | 対話シェル設定。tmux 自動起動 / 履歴共有 / git ブランチ付きプロンプト |
| `.tmux.conf` | prefix を `C-t` に変更、マウス操作を有効化 |

`.bashrc` と `.tmux.conf` は `postCreateCommand` で `~/` にシンボリックリンクされるため、
編集はこのリポジトリ側で行えばコンテナに即反映される。

## コンテナ生成時に導入される CLI

`postCreateCommand` が `claude` を `https://claude.ai/install.sh` から `~/.local/bin` に
入れる（PATH は `Dockerfile` の `ENV` が通す）。イメージではなくコンテナ生成時に取得する
ため、作り直すたびに最新版になる。`gh` と `git` はイメージ側（`Dockerfile`）に入っている。

> **注記:** `postCreateCommand` をオブジェクト形式で書くと各コマンドは**並列**に実行される。
> したがって互いの生成物に依存できない。`~/.local/bin` はインストーラが自分で作る。

> **警告:** `Dockerfile` の `ENV PATH` は単なる利便性ではなく、`~/.bashrc` を保護している。
> claude の公式インストーラは `BIN_DIR` が PATH に無いと `~/.bashrc` へ PATH ブロックを
> 追記するが、この devcontainer では `~/.bashrc` が**このリポジトリ内のファイルへの
> シンボリックリンク**なので、そのままだとコンテナを作るたびにリポジトリが汚れる
> （`.bashrc` に残っていた `# Added by Antigravity CLI installer` の行がまさにこの経路で
> 混入したもの）。`ENV PATH` が `~/.local/bin` を先に通しておくことで、インストーラの
> `add_to_path()` が早期 return してプロファイルに一切触れない。しかも
> `postCreateCommand` は並列実行なので、symlink 作成とインストーラが競合しうる。
>
> したがって **`ENV PATH` を消したり `Dockerfile` を反映せずに古いイメージのまま使うと、
> `.bashrc` が書き換えられる**。

## ホストをまたいで持ち越される状態

ワークスペースが共有ストレージ上にある前提で、コンテナ内のホーム相当のものは
ワークスペース配下の `.container-home/` に置き、別ホストで開いても引き継がれるようにしている。
名前付きボリュームは実体がそのホストのローカルディスクに作られるため使わない。

| コンテナ内 | 実体 | 設定箇所 |
|---|---|---|
| `/root/.claude` | `<workspace>/.container-home/claude` | `mounts` の bind mount |
| `$HISTFILE` | `<workspace>/.container-home/bash_history` | `containerEnv` |

`workspaceFolder` を `/root/work` に固定しているのが前提になっている。Claude Code の会話履歴は
cwd 由来のスラグ（`projects/-root-work/`）で引かれるので、コンテナ内パスが同じでないと
別ホストで履歴が繋がらない。

bind mount の source が存在しないとコンテナ作成に失敗するので、ホスト側でコンテナ作成前に
走る `initializeCommand` で `mkdir -p` している。

> **警告:** 同一のワークスペースを**2 ホストから同時にコンテナとして開かない**こと。
> `history.jsonl` や `bash_history` への追記が調停されない。Claude Code のセッション本体は
> UUID 別ファイルなので衝突はしないが、取りこぼしが起きる。
> `shutdownAction: "none"` で VS Code を閉じてもコンテナが生き続けるため、意図せず
> 2 ホストで生存しやすい点に注意（下記「コンテナを明示的に落とす」参照）。

## 使い方

このリポジトリをワークスペース root の `.devcontainer/` として配置し、
VS Code で「Reopen in Container」を実行する。

```
<workspace>/
├── .devcontainer/     ← このリポジトリ
├── .container-home/   ← コンテナ内のホーム相当（git 管理外）
└── <各プロジェクト>/
```

## コンテナを明示的に落とす

`shutdownAction: "none"` は意図的な設定で、VS Code のウィンドウを閉じてもコンテナを
落とさない（tmux セッションと実行中のジョブを残すため）。裏を返すと VS Code 側の操作では
止まらないので、明示的に落とすには次のどちらかを使う。

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
- **認証情報**: Claude Code の認証は `/root/.claude/.credentials.json`（OAuth）で行い、
  API キーは `containerEnv` で渡していない。共有ストレージ上に置かれる点に注意。
