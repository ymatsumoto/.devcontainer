# .devcontainer

Claude Code を動かすための Dev Container 定義（AlmaLinux 9 / podman）。

## 使い方

ワークスペース root の `.devcontainer/` として配置し、VS Code で「Reopen in Container」を実行する。

```
<workspace>/
├── .devcontainer/     ← このリポジトリ
├── .container-home/   ← コンテナ内のホーム相当（git 管理外・700）
└── <各プロジェクト>/
```

`workspaceFolder` は `/root/work` 固定。変える場合は `mounts` と `HISTFILE` の絶対パスも
合わせて変更する。

## ファイル

| ファイル | 役割 |
|---------|------|
| `devcontainer.json` | コンテナ定義 |
| `Dockerfile` | AlmaLinux 9-minimal に tmux, git, gh, podman, python3, poppler-utils, jq を導入 |
| `storage.conf` | podman-in-podman 用のストレージ設定。bind mount なので変更に再ビルドは不要 |
| `.bashrc` | tmux 自動起動 / 履歴共有 / git ブランチ付きプロンプト |
| `.tmux.conf` | prefix を `C-t` に変更、マウス操作を有効化 |

`.bashrc` と `.tmux.conf` は `~/` に symlink されるので、編集はこのリポジトリ側で行う。
`claude` は `postCreateCommand` が `~/.local/bin` に入れる。

## コンテナ内の状態

ワークスペース配下の `.container-home/` に置き、別ホストで開いても引き継がれるようにしている。

| コンテナ内 | 実体 |
|---|---|
| `/root/.claude` | `<ws>/.container-home/claude` |
| `/root/.claude.json` | `<ws>/.container-home/claude.json` |
| `/root/.ssh` | `<ws>/.container-home/ssh` |
| `~/.gitconfig` | `<ws>/.container-home/gitconfig` |
| `~/.config/gh` | `<ws>/.container-home/gh` |
| `$HISTFILE` | `<ws>/.container-home/bash_history` |

gh のトークンが平文で入るので `.container-home/` は `700` にする。秘密鍵はこのリポジトリでは
なく `<ws>/.container-home/ssh` に置く。同一ワークスペースを複数ホストから同時に開かない。

## 環境ごとに要設定

- **GPU**: `runArgs` の `--device ${localEnv:DEVCONTAINER_GPU:/dev/null}` でホストの GPU を
  CDI デバイスとして渡す。未設定なら GPU 無しで起動する。使う場合はホストに
  nvidia-container-toolkit を入れ、`/etc/cdi/nvidia.yaml` を生成した上で、VS Code
  （Remote-SSH ならリモート側）の環境に次を設定する。ホームを複数ノードで共有している
  場合に GPU の無いノードで外れるよう、CDI spec の有無で分岐させる。

  ```bash
  if ls /etc/cdi/nvidia*.yaml /var/run/cdi/nvidia*.yaml >/dev/null 2>&1; then
      export DEVCONTAINER_GPU=nvidia.com/gpu=all
  fi
  ```

  設定後は VS Code Server を再起動する（Remote-SSH なら「Kill VS Code Server on Host」）。
- **`/dev/fuse` が無いホスト**: `storage.conf` の driver を `vfs` に変更する。
- **`TZ`**: `containerEnv` で `Asia/Tokyo` を指定している。

## コンテナを落とす

`shutdownAction: "none"` なので、VS Code を閉じてもコンテナは残る。

- **VS Code**: Remote Explorer の Dev Containers 一覧で対象を右クリック →「Stop Container」
- **ホストのシェル**:

  ```bash
  podman ps --filter label=devcontainer.local_folder=<workspace の絶対パス>
  podman stop <container id>
  ```

イメージごと作り直す場合は「Dev Containers: Rebuild Container」（キャッシュも捨てるなら
「Rebuild Without Cache and Reopen in Container」）。
