# Ideas

If a scan aborts with a FS error save the intermediate MANIFEST as `MANIFEST.PART.json`.

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

## `destiny [global options] scan [scan options] [<dir/manifest>...]`

Create or update one or more MANIFESTs. Defaults to scanning the current directory. When multiple directories / manifests are specified update each individually

| option                 | description                                                           |
| ---------------------- | --------------------------------------------------------------------- |
| `--no-sort`            | Don't sort filenames (default is `--sort`)                            |
| `--ref <dir/manifest>` | Additional place to look for matches. May be specified multiple times |

# TODO

- read / write JSON
- CLI
- ~~hash files~~
