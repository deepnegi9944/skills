---
name: maas-image-upload
description: >-
  Login to MAAS CLI and upload custom OS images (e.g. CentOS, Ubuntu) as boot
  resources. Use when the user wants to login to MAAS, upload an image to MAAS,
  list boot resources, check image sync status, or manage MAAS boot images.
---

# MAAS Image Upload

## Prerequisites

The user must provide:
1. **MAAS API key** (format: `consumer_key:token_key:token_secret`)
2. **MAAS URL** (e.g. `http://10.235.0.30:5240/MAAS/`)
3. **Image source**: either an extracted rootfs directory or a pre-built `.tar.gz` tarball

The MAAS CLI must be installed at `~/.local/bin/maas`. Verify with `maas --help`.

## Step 1: Login to MAAS

This MAAS CLI version uses `--apikey` flag with `-p` for profile name. **Do NOT use** the old `maas <profile> <resource>` syntax.

```bash
maas login -p <PROFILE_NAME> --apikey "<API_KEY>" <MAAS_URL>
```

Example:
```bash
maas login -p Admin --apikey "B4t4KFee3z8guZGvXL:vu8vP53fm3cF27Qb6v:XqFxGpWgxsaJGXSqC85HhqQxmfBLUxWX" http://10.235.0.30:5240/MAAS/
```

Alternatively, login with username and password:
```bash
maas login -p Admin http://10.235.0.30:5240/MAAS/ <username> <password>
```

## Step 2: List Existing Boot Resources

This CLI does **not** support `maas <profile> boot-resources read`. Use `maas shell` with python-libmaas instead:

```python
echo '
import asyncio
from maas.client import connect

async def main():
    client = await connect("<MAAS_URL>", apikey="<API_KEY>")
    resources = await client.boot_resources.list()
    for r in resources:
        print(f"ID={r.id}  name={r.name}  arch={r.architecture}  type={r.type}  subarches={r.subarches}")

asyncio.run(main())
' | maas shell
```

## Step 3: Prepare the Image

### If source is an extracted rootfs directory

Repack into a tarball:
```bash
cd /path/to/rootfs && sudo tar czf /path/to/output-image.tar.gz .
```

**Important**: Run `tar` from inside the rootfs directory using `.` so paths are relative.

A 2-3 GB rootfs typically takes 3-5 minutes to compress.

### If source is a pre-built tarball

No preparation needed. Proceed to upload.

## Step 4: Upload Image to MAAS

Use `maas shell` with python-libmaas. The `name` must be in `os/release` format (e.g. `custom/my-image-name`).

```python
echo '
import asyncio
from maas.client import connect

async def main():
    client = await connect("<MAAS_URL>", apikey="<API_KEY>")
    with open("<PATH_TO_TARBALL>", "rb") as f:
        resource = await client.boot_resources.create(
            "custom/<IMAGE_NAME>",
            "amd64/generic",
            f,
            title="<HUMAN_READABLE_TITLE>",
        )
    print("Uploaded: ID=%s name=%s arch=%s" % (resource.id, resource.name, resource.architecture))

asyncio.run(main())
' | maas shell
```

### `boot_resources.create()` signature

```
create(name: str, architecture: str, content: io.IOBase, *, title: str = '', filetype: BootResourceFileType = TGZ, chunk_size=4194304, progress_callback=None)
```

- `name`: **Must** be in `os/release` format with a `/` (e.g. `custom/centos9-stream`)
- `architecture`: e.g. `amd64/generic`
- `content`: file object opened in `rb` mode
- `title`: human-readable display name

**Expect long upload times**: A 2.6 GB image takes 20-30 minutes. Set `block_until_ms` to 900000 (15 min) or higher.

## Step 5: Monitor Sync Progress

After upload, the rack controller syncs the image. Check progress:

```python
echo '
import asyncio, json
from maas.client.bones import SessionAPI

async def main():
    session = SessionAPI.fromProfileName("<PROFILE_NAME>")
    result = await session.BootResource.read(id=<IMAGE_ID>)
    for version, s in result["sets"].items():
        gb = s["size"] / (1024**3)
        print("Version: %s  Progress: %.1f%%  Complete: %s  Size: %.2f GB" % (version, s["progress"], s["complete"], gb))

asyncio.run(main())
' | maas shell
```

The image is ready for deployment when `complete` is `True`.

## Step 6: Verify

List boot resources again (Step 2) to confirm the new image appears.

## Important Notes

- **Do NOT delete existing images** unless explicitly asked by the user.
- The `maas shell` command uses the active profile set during login. Override with `--profile-name NAME`.
- MAAS CLI commands like `maas machines`, `maas nodes`, etc. work directly, but `boot-resources` must go through `maas shell`.
- For the image to be deployable, the distro series name used in AICC's deployment profile `OSImage` field must match the MAAS image name (e.g. `custom/centos9-stream`).

## Troubleshooting

| Error | Cause | Fix |
|-------|-------|-----|
| `invalid choice: 'Admin'` | Using old `maas <profile> <command>` syntax | Use direct commands or `maas shell` |
| `name must be in format os/release; missing '/'` | Image name missing `/` separator | Use `custom/<name>` format |
| `Error: Admin/api/2.0/version/` | Wrong login syntax | Use `-p` flag for profile name |
| Image stuck at "queued for download" | Rack controller syncing from region | Wait; monitor with Step 5 |
