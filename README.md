# dasik-aur

The Arch package for [**dasik**](https://github.com/amt911/dasik) — a declarative
Arch Linux installer: describe the target system in one JSON file, run
`dasik apply`, and get that system. Running the same JSON again changes nothing.

This repository is a PKGBUILD, not the source. It exists so a live ISO can get
dasik in one command, and so a machine dasik installs can carry dasik itself.

| | |
| --- | --- |
| Package | `dasik` (`any` architecture, Python) |
| Source | pinned to the upstream **tag** matching `pkgver` |
| Releases | every tag builds a `.pkg.tar.zst` and publishes it — that artifact is what the ISO installs |
| Not in the AUR | on purpose; `.SRCINFO` is kept valid in case that changes |

---

## Install on a live ISO — the painless path

Boot the Arch ISO, get networking up (`iwctl` for wifi), then:

```sh
curl -fsSL https://raw.githubusercontent.com/amt911/dasik-aur/main/iso-bootstrap.sh -o bootstrap.sh
bash bootstrap.sh
```

Three minutes later you have `dasik`, and your private config cloned to
`/root/config`. Then:

```sh
dasik check /root/config/thinkpad.json    # JSON + schema, touches nothing
dasik plan  /root/config/thinkpad.json    # the dry run: every change, in full
dasik apply /root/config/thinkpad.json    # DESTRUCTIVE from here on
```

**Download the script rather than piping it into bash.** The GitHub login step
needs a terminal, and `curl | bash` does not have one. The script falls back to
`/dev/tty` where it can, but the two-line form above always works.

What it does:

1. `pacman -Sy`, then installs `git`, `github-cli`, `age`.
2. Installs dasik from the latest published `.pkg.tar.zst` (seconds, no build).
   With no published release — or with `--build` — it creates an unprivileged
   `builder` user and runs `makepkg` instead, because **makepkg refuses to run
   as root and a live ISO is root**.
3. Logs into GitHub with a **device code** — eight characters you type on your
   phone. No token typed on the ISO, no SSH key on the pendrive.
4. Clones your private config repo.

Flags: `--config-repo owner/name`, `--dest /path`, `--no-clone`, `--build`.

If anything dies with `ENOSPC`, the ISO's overlay filesystem is full (the
script warns when it starts out below 700 MB):

```sh
mount -o remount,size=75% /run/archiso/cowspace
```

### Without the script

```sh
pacman -Sy
pacman -U https://github.com/amt911/dasik-aur/releases/latest/download/dasik-<version>-1-any.pkg.tar.zst
```

## Install on an existing Arch system

```sh
git clone https://github.com/amt911/dasik-aur.git
cd dasik-aur
makepkg -si
```

On an installed machine dasik defaults to the wrong root — `--target /mnt` is
the install-time default, so day-2 convergence is:

```sh
sudo dasik plan  --target / ~/config/thinkpad.json
sudo dasik apply --target / ~/config/thinkpad.json
sudo dasik sync  ~/config/thinkpad.json      # sync already defaults to /
```

---

## The private config repo

> **Coming from a machine you built by hand, with neither tool installed?**
> [Adopt an existing machine](https://github.com/amt911/dasik/wiki/Adopt-an-existing-machine)
> is the guide for that: install both, capture the system into a config from
> `{}`, create the two private repositories, arm the capture for a reinstall,
> and reinstall from it.

Your configs live in a private repository (`amt911/dasik-personal-config`);
nothing about them belongs here. A layout that works:

```
dasik-personal-config/
├── thinkpad.json          # one file per machine
├── desktop.json
├── common/
│   └── packages.json      # shared blocks, pulled in with $include
└── secrets/
    └── andres.hash        # crypt hash, NOT a password
```

dasik's `$include` keeps a config readable and keeps secrets to one line:

```json
"users": [
  { "name": "andres", "hashed_password": { "$include_line": "secrets/andres.hash" } }
]
```

Produce the hash with `dasik hash-password` (it prompts twice and prints the
crypt hash). A crypt hash in a private repo is the same exposure as
`/etc/shadow` on the machine — fine. A plaintext password is not.

**Seeding the repo from a machine you already have** is one command:

```sh
sudo dasik sync ~/config/thinkpad.json      # captures reality INTO the file
dasik check ~/config/thinkpad.json          # a capture the tool then refuses is a broken capture
```

`sync` reads the live system — disks, LUKS layout, packages, units, `/etc`
snippets — and writes it back into the config. Before reusing that on a new
machine, make it generic (drop data disks, turn `wipe`/`format` on, replace
`luks_uuid` with a passphrase): see
[the capture guide](https://github.com/amt911/dasik/blob/main/docs/copy-your-config-and-test.md).

### Carrying dasik itself

dasik is in no pacman repo and no AUR, so a config that wants dasik on the
installed machine points at *this* repository:

```json
"packages": ["dasik", "config-saver"],
"package_sources": {
  "dasik": {
    "type": "pkgbuild-git",
    "url": "https://github.com/amt911/dasik-aur.git",
    "ref": "<full 40-char commit SHA of this repo>",
    "subdir": "."
  }
}
```

The `ref` is a full commit SHA — a branch name is not reproducible, so the
schema refuses one. `git rev-parse HEAD` here gives you the value.

---

## config-saver

[config-saver](https://github.com/amt911/config-saver) backs up the parts of
`$HOME` a config file cannot carry: themes, browser profiles, keyboard layouts,
whole directories. It splits cleanly in two, and the split is the whole trick:

- **The policy** — which configurations exist, whose timer runs, which package
  builds it. dasik owns this. It is in the config file.
- **The payload** — the actual `.tar.gz` of your old `$HOME`. dasik does not,
  and should not, carry this. It has to travel on its own.

### You do not install config-saver on the ISO

dasik builds it **inside the target**, from its PKGBUILD repo, pinned:

```json
"packages": ["config-saver"],
"config_saver": {
  "source": {
    "url": "https://github.com/amt911/config-saver-aur.git",
    "ref": "<full 40-char commit SHA of config-saver-aur>",
    "subdir": "."
  },
  "configs": {
    "home": { "…": "the config-saver document, written to /etc/config-saver/configs/home.json" }
  },
  "timer_users": ["andres"],
  "restore": [
    { "user": "andres", "archive": "/root/home.tar.gz" }
  ]
}
```

So the ISO needs nothing from config-saver. Only the archive does.

### Moving the archive: age + a release asset

On the **old machine**, capture and encrypt:

```sh
config-saver --compress                                      # runs every configuration
config-saver --export-config home --output ~/home.tar.gz.age # pick the latest one out
```

config-saver **encrypts natively**, which is what you want for something a timer
produces while you are asleep — declare it once in the configuration and every
archive comes out encrypted:

```yaml
encrypt:
  method: age
  recipients:
    - age1qz…        # from `age-keygen -o ~/.config/age/key.txt`
```

Keep that private key somewhere the archive is **not** — it cannot live only
inside what it decrypts. `age -p ~/home.tar.gz` (a passphrase) is the manual
alternative when you would rather have nothing to custody; the cost is that an
unattended timer cannot type it, so a plaintext archive waits on disk until you
do.

Upload it to the **private** config repo as a release asset — not as a commit.
Git is bad at 2 GB of browser profile; release assets are exactly this:

```sh
gh release create home-2026-08 ~/home.tar.gz.age \
  -R amt911/dasik-personal-config -n "\$HOME capture"
```

config-saver says it itself: **a plain `.tar.gz` is compressed, not
encrypted**, and this one holds your browser profiles.

> **An encrypted archive must be decrypted before dasik's restore.** dasik runs
> `config-saver --decompress --input <path>` with no `--identity`, which age
> requires. Decrypt it yourself (`age -d -i ~/.config/age/key.txt -o
> /root/home.tar.gz home.tar.gz.age`) and point `restore.archive` at the plain
> file — or restore by hand with `config-saver --decompress -i … --identity …`.

### Restoring `$HOME`

**After the first boot, not during the install.** `restore.archive` is a path
*inside the target*, and the target does not exist until `apply` has already
partitioned and formatted it — there is nowhere to put the file beforehand. So:

```sh
# on the new machine, first boot, logged in as yourself
gh release download home-2026-08 -R amt911/dasik-personal-config
age -d -o /tmp/home.tar.gz home.tar.gz.age
sudo mv /tmp/home.tar.gz /root/home.tar.gz            # the path the config declares

sudo dasik apply --target / ~/config/thinkpad.json    # does only the restore
```

dasik installed everything else on the first pass, so this second `apply` finds
one thing to do. It marks the restore by the archive's **content hash** under
`~/.local/state/dasik/config-saver/`: re-running restores nothing, and dropping
a *newer* capture in the same path restores again — which is the whole point of
a file whose job is to change.

Offline instead? Same thing with the archive on a pendrive: mount it, copy to
`/root/home.tar.gz`, run the second `apply`.

---

## Cutting a version

The upstream tag comes first, then this repo, then CI does the rest:

```sh
# in the dasik checkout
git tag 0.2.0 && git push origin 0.2.0

# here
scripts/bump.sh 0.2.0 --push
```

`bump.sh` refuses a version whose upstream tag does not exist (otherwise the
release builds a package whose every install fails at `git checkout`), edits
`pkgver`, regenerates `.SRCINFO`, commits and tags. Pushing the tag runs
[`.github/workflows/build.yml`](.github/workflows/build.yml), which builds in an
`archlinux:base-devel` container as an unprivileged user, runs `namcap`, smoke
tests the built package (`pacman -U`, `dasik --help`, `dasik check` against a
shipped sample), and publishes the `.pkg.tar.zst` as a release asset.

That asset is what `iso-bootstrap.sh` installs. Cutting a version and the ISO
getting it are the same act.

## Notes

- **`sha256sums=('SKIP')` is deliberate.** GitHub's autogenerated tag tarballs
  are not byte-stable, so a committed checksum can rot with no change on either
  side. The source is a Git clone pinned to the tag instead — the tag is the
  anchor, and a bump edits exactly one line.
- **No license file is installed.** Upstream declares MIT in `pyproject.toml`
  but ships no `LICENSE`, and there is no text to install. Adding one upstream
  is a one-line change to `package()` here.
- **The package installs the sample configs** to `/usr/share/dasik/examples/`,
  which on a live ISO is the fastest way to see a working config.
- `dasik` itself only hard-depends on `python-pydantic` and `python-colorama`.
  Everything it shells out to (`arch-install-scripts`, `gptfdisk`,
  `cryptsetup`, …) is an `optdepends`: `dasik check` and `dasik plan` need none
  of it, and a missing binary is reported by name when a domain reaches for it.
