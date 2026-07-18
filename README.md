# libnode Build Toolchain

Build [Node.js](https://nodejs.org/) as a shared library (`libnode`) for Windows and Linux via GitHub Actions.

## What is libnode?

When Node.js is built with `--shared`, it produces a shared library (`libnode`) instead of the `node` executable. This allows embedding Node.js into other applications.

## Output Artifacts

Each build produces the following archives, uploaded to a GitHub Release:

| Archive | Platform | Contents |
|---------|----------|----------|
| `libnode-linux-x64.tar.gz` | Linux x86_64 | `libnode.so.<NODE_MODULE_VERSION>` |
| `libnode-linux-x86.tar.gz` | Linux x86 (v22 only) | `libnode.so.<NODE_MODULE_VERSION>` |
| `libnode-windows-x64.zip` | Windows x64 | `libnode.dll` + `libnode.lib` |
| `libnode-windows-x86.zip` | Windows x86 (v22 only) | `libnode.dll` + `libnode.lib` |

## Version Requirements

- **Minimum version**: 22
- **Even major only**: 22, 24, 26, ... (odd versions like 23, 25 are rejected)
- **v22**: builds both x64 and x86 for Linux and Windows
- **v24+**: x64 only

## How to Build

### Option 1: Push a tag (recommended for releases)

```bash
git tag v24.18.0
git push origin v24.18.0
```

Supported tag formats:
- `v22.0.0` → build Node.js 22.0.0
- `libnode-22.0.0` → same, alternative prefix

The workflow will build and create a GitHub Release attached to that tag.

### Option 2: Manual trigger (ad-hoc / testing)

Go to **Actions** → **Build libnode** → **Run workflow**, enter the version (e.g. `24.18.0`).

A release will be created with tag `libnode-v{version}` (e.g. `libnode-v24.18.0`).

## How It Works

```
Push tag / Manual input
        │
        ▼
   validate (version check)
        │
        ├── build-linux x64 (ubuntu-24.04)
        ├── build-linux x86 (ubuntu-24.04, v22 only)
        ├── build-windows x64 (windows-2022)
        └── build-windows x86 (windows-2022, v22 only)
        │
        ▼
   release (create GitHub Release + upload archives)
```

### Build details

- **Linux**: `./configure --shared && make`
  - x86 builds use `-m32` with `gcc-multilib` and apply an OpenSSL assembly patch (`%ifdef` → `#ifdef`, `%endif` → `#endif`)
- **Windows**: `vcbuild.bat dll release <arch>`
  - v24+ uses `clang-cl` compiler
  - v26+ installs Rust toolchain for V8 Temporal support

## Repository Structure

```
.github/workflows/build-libnode.yml    — Main workflow
scripts/
├── build-linux.sh                      — Linux build script
└── build-windows.ps1                   — Windows build script
```

## Requirements for Local Build

### Linux
- GCC >= 11, make, python3, nasm
- For x86: `gcc-multilib`, `g++-multilib`

### Windows
- Visual Studio 2022 with "Desktop development with C++"
- Python 3.x, NASM
