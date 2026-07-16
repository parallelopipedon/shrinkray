# shrinkray

Available as Python (`shrink.py`) or plain Bash (`shrink.sh`) — same behavior, pick whichever you have handy.

```bash
python3 shrink.py /path/to/folder
```
or
```bash
./shrink.sh /path/to/folder
```

Originals are always left untouched. 

A full mirrored copy (videos shrunk, everything else copied as-is) is written to `folder/shrunk-<timestamp>`.

| Flag | Description |
| --- | --- |
| `folder` | Folder to scan (default: current directory) |
| `--ext` | Extensions to treat as video (default: `mp4 mov mkv avi m4v`) |
