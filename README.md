# Ideas

If a scan aborts with a FS error save the partial MANIFEST as `MANIFEST.PARTIAL.json`.

Paths in nested manifests can match in two ways

- relative to themselves
- relative to the scan root

# Commands

| Command         | Summary                       |
| --------------- | ----------------------------- |
| destiny scan    | Scan directories              |
| destiny link    | Link dupes                    |
| destiny conform | Make a file system from bits  |
| destiny satisfy | Export what a remote FS needs |
| destiny help    | Get help                      |

## Global options

| option | description     |
| ------ | --------------- |
| `-q`   | Quiet operation |

## `destiny [global options] scan [scan options] <dir/manifest>...`

Create or update one or more MANIFESTs. When multiple directories / manifests are specified update each individually

| option                 | description                                                           |
| ---------------------- | --------------------------------------------------------------------- |
| `--no-sort`            | Don't sort filenames (default: `--sort`)                              |
| `--use <dir/manifest>` | Additional place to look for matches; may be specified multiple times |
| `--use-nested`         | Add any nested manifests we find to the search path                   |
| `--no-mtime`           | Ignore mtime when matching (default: `--mtime`)                       |
| `--no-perms`           | Ignore permissions when matching (default: `--perms`)                 |

## `destiny link [link options] <dir/manifest>...`

| option        | description                                                                     |
| ------------- | ------------------------------------------------------------------------------- |
| `--strictest` | Use the strictest permissions rather than matching                              |
| `--loosest`   | Use the loosest permissions rather than matching                                |
| `--earliest`  | Choose the alternative with the earliest modification time rather than matching |
| `--latest`    | Choose the alternive with the latest modification time rather than matching     |
| `--dry-run`   | Don't do it yet                                                                 |

# TODO

- read / write JSON
- CLI
- ~~hash files~~
