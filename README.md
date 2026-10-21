# .devcontainer

Claude Code を動かすための Dev Container 定義（AlmaLinux 9 / podman）。

## 使い方

ワークスペース root の `.devcontainer/` として配置し、VS Code で「Reopen in Container」を実行する。

```
<workspace>/
├── .devcontainer/     ← このリポジトリ
└── <各プロジェクト>/
```

コンテナ内のホーム相当の状態はワークスペースではなく、開いたユーザのホーム
（`~/.devcontainer-state/` の下）に置く。同じワークスペースを
複数ユーザがそれぞれのコンテナで開ける（後述）。

`workspaceFolder` は `/root/work` 固定。変える場合は `workspaceMount` の `target` も
合わせて変更する。Claude Code のプロジェクト別データ（メモリなど）はこのパスで
区別されるので、変えると引き継がれない。

## ファイル

| ファイル | 役割 |
|---------|------|
| `devcontainer.json` | コンテナ定義 |
| `init.sh` | ホスト側の準備（ワークスペース ID と状態ディレクトリの用意、旧レイアウトからの移行）。`initializeCommand` から毎回実行 |
| `Dockerfile` | AlmaLinux 9-minimal に tmux, git, gh, podman, python3, poppler-utils, jq を導入。他ユーザ所有のファイルでも git が止まらないよう `safe.directory '*'` を設定 |
| `storage.conf` | podman-in-podman 用のストレージ設定。bind mount なので変更に再ビルドは不要 |
| `.bashrc` | tmux 自動起動 / 履歴共有 / git ブランチ付きプロンプト / 定義が更新されたら Rebuild を促す |
| `.tmux.conf` | prefix を `C-t` に変更、マウス操作を有効化 |

`~/.bashrc` はこのリポジトリの `.bashrc` を source するだけのファイル、`~/.tmux.conf` は
symlink なので、編集はこのリポジトリ側で行う。インストーラなどが `~/.bashrc` に追記しても
リポジトリは汚れない（コンテナを作り直すと消える）。

`claude` と `agy`（Antigravity CLI）は `postCreateCommand` が `~/.local/bin` に入れる。
`agy` のインストーラは rc ファイルに PATH を追記するので、一時的な HOME で実行している
（PATH は Dockerfile の `ENV` で通してある）。

## コンテナ内の状態

ホストの `~/.devcontainer-state/<ワークスペース名>-<ID 先頭 8 桁>/`（以下 `<state>`、`700`）に置き、
コンテナには `/root/.state` としてマウントする。ホームが NFS で共有されていれば、
どのノードから開いても引き継がれる。

| コンテナ内 | 実体 |
|---|---|
| `/root/.claude` | `<state>/claude` |
| `/root/.claude.json` | `<state>/claude.json` |
| `/root/.ssh` | `<state>/ssh` |
| `/root/.gemini` | `<state>/gemini`（agy の認証情報と会話） |
| `~/.gitconfig` | `<state>/gitconfig` |
| `~/.config/gh` | `<state>/gh` |
| `$HISTFILE` | `<state>/bash_history` |

秘密鍵はこのリポジトリではなく `<state>/ssh` に置く。同一ユーザが同一ワークスペースを
複数ホストから同時に開かない（`claude.json` やトークン更新が競合する）。別ユーザは可。

`<state>` はワークスペースの ID（`.devcontainer/.workspace-id`、git 管理外、`init.sh` が作る）で
決まる。`devcontainer.json` からはファイルを読めないので、`init.sh` が
`~/.devcontainer-state/.by-path<ワークスペースの絶対パス>` から `<state>` への symlink を張り、
マウントはそれを経由する。

- 同名の別ワークスペースは ID が違うので、別の `<state>` になる。
- ワークスペースを移動しても、ノードごとにマウント先が違っても、ID がついてくるので同じ `<state>` を使う。
- `.devcontainer/` ごと複製したワークスペースは、元のパスに同じ ID が残っていれば複製とみなして
  ID を振り直す（元が見えないノードで開いた場合は判別できず、状態を共有する）。
- 移動や削除で使われなくなった `.by-path` の symlink は残るが、害はない。
- `.workspace-id` は最初に開いた人が作るので、その人は `.devcontainer/` に書き込める必要がある。
- ディレクトリ名に ID を付ける前の版で作った `~/.devcontainer-state/<ワークスペース名>/` も、
  中に ID が記録してあるのでそのまま使われる。

旧レイアウト（ワークスペース直下の `.container-home/`）があれば、自分が所有する分を
`init.sh` が `<state>` にコピーする。旧版のコンテナを全部 Rebuild し終えたら
`.container-home/` は手で消してよい。

## 複数ユーザで共有する

rootless podman はホストの UID / プライマリ GID をコンテナ内の 0/0 にマップするので、
コンテナ内 root はホストからは「本人 / mlab」として読み書きする。ワークスペースは mlab の
グループ権限で共有する。

- rootless podman が前提。rootful の docker / podman ではユーザ間で同じコンテナに相乗りしてしまう。
- コンテナは `--umask 0002` で動くので、新しく作るファイルはグループ書き込み可になる。
- 既存ファイルは各自が自分の所有分に `chgrp mlab` / `chmod g+rwX` する。パスワードファイルなど
  秘密のものは対象から外す（`chmod -R` をワークスペース全体にかけない）。
- 共有する git リポジトリでは `git config core.sharedRepository group` を設定する。
  これが無いと `.git/objects/` 配下が他のメンバーから書けなくなることがある。
- 同じ作業ツリーを同時に触ると `index.lock` の取り合いやブランチ切り替えの事故が起きる。
  共同編集が目的でなければ、各自 `git worktree` か別クローンを開く。
- ワークスペースが NFSv4 の場合、POSIX ACL（`setfacl`）による default ACL は使えない。

### テンプレート更新時

- `.devcontainer/` は 1 人が pull するとそのワークスペースの全員に効く。
- `devcontainer.json` / `Dockerfile` / `init.sh` の変更は各自が Rebuild するまで反映されない。
  ずれている間はシェル起動時に警告が出る。
- `.bashrc` / `.tmux.conf` / `storage.conf` は pull した時点で起動中の全コンテナに効くので、
  旧版のコンテナでも動くように書く。
- 状態のレイアウトを変えるときは、旧パスからの移行を `init.sh` に足す。

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
