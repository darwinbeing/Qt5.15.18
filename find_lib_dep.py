#!/usr/bin/env python3
"""
Rewrite "leaked" absolute dependency paths in a built Qt tree to @loader_path.

When Qt links against libraries we built ourselves (e.g. universal libpq for the
PostgreSQL SQL driver), the resulting .dylib records an absolute path from the
build machine (the CI runner's workspace). On any other machine that path does
not exist, so loading the plugin fails. This rewrites every such dependency to
@loader_path/<name> and copies the needed libs next to the plugins.

Usage:
    find_lib_dep.py <qt_dir> [--deps-lib DIR] [--dry-run]

    <qt_dir>     root of the installed Qt (e.g. .../Qt5.15.19/5.15.19/clang_64)
    --deps-lib   directory holding the universal deps libs (libpq, libssl, ...);
                 matched libs are copied next to each plugin that needs them
    --dry-run    only report, do not modify
"""
import argparse
import os
import shutil
import subprocess

# Prefixes that are fine to keep as-is (system libs or already-relative install names).
SAFE_PREFIXES = ("/usr/lib/", "/System/", "@rpath", "@loader_path", "@executable_path")


def deps_of(path):
    out = subprocess.run(["otool", "-L", path], capture_output=True, text=True).stdout
    # Skip the first line (the file's own name).
    return [ln.strip().split(" ")[0] for ln in out.splitlines()[1:] if ln.strip()]


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("qt_dir")
    ap.add_argument("--deps-lib", default=None)
    ap.add_argument("--dry-run", action="store_true")
    args = ap.parse_args()

    fixed = 0
    for dirpath, _, filenames in os.walk(args.qt_dir):
        for fn in filenames:
            if not (fn.endswith(".dylib") or fn.endswith(".so")):
                continue
            fp = os.path.join(dirpath, fn)
            for dep in deps_of(fp):
                if dep.startswith("/") and not dep.startswith(SAFE_PREFIXES):
                    base = os.path.basename(dep)
                    new = "@loader_path/" + base
                    print(f"{fp}\n    {dep} -> {new}")
                    if not args.dry_run:
                        os.chmod(fp, 0o755)
                        subprocess.run(["install_name_tool", "-change", dep, new, fp], check=True)
                        # Make sure the dependency actually sits next to the plugin.
                        if args.deps_lib:
                            src = os.path.join(args.deps_lib, base)
                            dst = os.path.join(dirpath, base)
                            if os.path.isfile(src) and not os.path.exists(dst):
                                shutil.copy2(src, dst)
                    fixed += 1
    print(f"\n{'Would fix' if args.dry_run else 'Fixed'} {fixed} dependency reference(s).")


if __name__ == "__main__":
    main()
