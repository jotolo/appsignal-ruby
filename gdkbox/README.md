# gdkbox

Spin up a [GitLab Development Kit (GDK)](https://gitlab.com/gitlab-org/gitlab-development-kit)
"in a box" with a single command, then connect to it from **VS Code** and run
**Claude Code** agents against a real GitLab development environment.

`gdkbox` runs GitLab's official GDK image in a Docker container, enables SSH so
VS Code Remote-SSH can attach, and installs Claude Code inside the box for you.

```
gdkbox up myenv         # pull GDK image, start container, wire SSH + Claude Code
gdkbox code myenv       # open the box in VS Code (Remote-SSH)
gdkbox ssh myenv        # drop into a shell inside the box
gdkbox ls               # list your boxes and their status
```

## How it works

```
            gdkbox up demo
                  │
   ┌──────────────┼─────────────────────────────────────────────┐
   │              ▼                                               │
   │   1. docker pull  <official GDK image>                       │
   │   2. docker run   -p 127.0.0.1:2222:22  -p 127.0.0.1:3000:3000
   │   3. provision    install + start sshd, authorize gdkbox key │
   │   4. provision    npm install -g @anthropic-ai/claude-code   │
   │   5. register     Host gdkbox-demo  ->  ~/.gdkbox/ssh_config  │
   └──────────────────────────────────────────────────────────────┘
                  │
      ┌───────────┴────────────┐
      ▼                        ▼
  VS Code Remote-SSH       ssh gdkbox-demo -t claude
  (ssh-remote+gdkbox-demo)  (run agents in the box)
```

- **Infra:** a Docker container per box, ports published to `127.0.0.1`.
- **Image:** GitLab's official GDK-in-a-box image (overridable).
- **Editor:** VS Code Remote-SSH, via a generated `~/.gdkbox/ssh_config`
  that is `Include`d from your `~/.ssh/config`.
- **Agents:** Claude Code is installed inside each box.

## Requirements

- Ruby >= 3.0
- [Docker](https://docs.docker.com/get-docker/) installed and running
- `ssh` and `ssh-keygen` (standard on macOS/Linux)
- [VS Code](https://code.visualstudio.com/) with the **Remote - SSH**
  extension, and the `code` command on your `PATH` (optional, only for
  `gdkbox code`)

## Install

From this directory:

```sh
gem build gdkbox.gemspec
gem install ./gdkbox-0.1.0.gem
```

Or run it straight from a checkout without installing:

```sh
./bin/gdkbox up myenv
```

## Commands

| Command | Description |
| --- | --- |
| `gdkbox up NAME` | Pull the GDK image, start a box, enable SSH, install Claude Code, register VS Code host. |
| `gdkbox ls` | List boxes and their container status. |
| `gdkbox status NAME` | Show container state and connection details. |
| `gdkbox code NAME` | Open the box in VS Code via Remote-SSH. |
| `gdkbox ssh NAME` | Open an interactive SSH session into the box. |
| `gdkbox claude NAME` | Install Claude Code inside the box. |
| `gdkbox start NAME` | Start a stopped box (and re-enable SSH). |
| `gdkbox stop NAME` | Stop a running box. |
| `gdkbox rm NAME` | Remove a box: container, metadata, and SSH entry. |

### `gdkbox up` options

| Option | Default | Description |
| --- | --- | --- |
| `--image` | official GDK image | Override the container image. |
| `--ssh-port` | next free from 2222 | Host port to publish SSH on. |
| `--web-port` | next free from 3000 | Host port to publish the GDK web UI on. |
| `--no-claude` | (Claude installed) | Skip installing Claude Code. |

## Typical workflow

```sh
# 1. Create a box (first run pulls a large image, so give it a few minutes)
gdkbox up demo

# 2. Edit the code with VS Code Remote-SSH
gdkbox code demo

# 3. Inside the box, start GDK and run an agent
gdkbox ssh demo
#   gdk start          # boot the GitLab services
#   claude             # launch a Claude Code agent against the repo

# 4. The GitLab web UI is published locally
open http://127.0.0.1:3000

# 5. Stop or remove the box when you're done
gdkbox stop demo
gdkbox rm demo
```

## Configuration

| Environment variable | Purpose |
| --- | --- |
| `GDKBOX_HOME` | Where gdkbox stores keys, box metadata, and the SSH config (default `~/.gdkbox`). |
| `GDKBOX_IMAGE` | Default image used by `gdkbox up` when `--image` is not given. |

State on disk:

```
~/.gdkbox/
├── boxes/<name>.json     # metadata for each box
├── keys/id_ed25519(.pub) # dedicated keypair authorized into every box
└── ssh_config            # generated; Included from ~/.ssh/config
```

`gdkbox` never touches your personal SSH keys: it creates and uses its own
`id_ed25519` under `~/.gdkbox/keys`.

## Development

```sh
bundle install
bundle exec rspec        # or: ruby -e "require 'rspec/core'; RSpec::Core::Runner.run(['spec'])"
```

The Docker, SSH, and filesystem boundaries are isolated behind small wrapper
classes (`Docker`, `Shell`, `Store`, `SSHConfig`, `SSHKey`, `Provisioner`,
`VSCode`), so the orchestration logic in `Box` is fully unit-tested without
needing a running Docker daemon.

## Notes & limitations

- Ports are published to `127.0.0.1` only, so boxes are reachable from your
  machine but not the wider network.
- Processes started via `docker exec` (like `sshd`) do not survive a container
  restart, so `gdkbox start` re-runs the SSH provisioning step to bring it back.
- Claude Code is installed in the box but still needs your Anthropic
  credentials at runtime — sign in the first time you run `claude` inside it.
