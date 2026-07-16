# cli/

CLI-First note. PhotoSweep's core logic (size formatting, storage math, asset
selection) is pure and lives in `Sources/Models`, `Sources/Extensions`, and
`Sources/ViewModels`. Because the data source is PhotoKit (device-only, no headless
mode), the deterministic pipeline check is the fake-backed unit test suite rather than
a standalone binary.

Run it with:

```bash
make integration    # == make test
```

`Tests/PhotoSweepTests` drives the ViewModels with an in-memory `FakeLibrary`, so the
scan → select → delete pipeline is verified without a real photo library or UI.

AI-TODO: if a macOS target is ever added (Photos framework is available on macOS), a
real `cli/` binary could exercise the same services against the Mac photo library.
