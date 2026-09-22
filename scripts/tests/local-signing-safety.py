#!/usr/bin/env python3
"""Exercise production shell functions; only disposable /tmp fixtures are mutated."""
from pathlib import Path
import plistlib
import select
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[2]
PRELUDE = '''set -euo pipefail
source "$1/scripts/lib/local-signing.sh"
source "$1/scripts/lib/local-lock.sh"
source "$1/scripts/lib/codesign-app.sh"
'''
checks = 0


def expect(value, message):
    global checks
    assert value, message
    checks += 1
    print("PASS:", message)


def run(script, *args):
    return subprocess.run(["/bin/bash", "-c", PRELUDE + script, "fixture", str(ROOT), *map(str, args)],
                          capture_output=True, text=True, timeout=5)


def hold(lock, build=False):
    process = subprocess.Popen(["/bin/bash", "-c", PRELUDE + '''
"$3"
island_acquire_lock "$2" fixture
printf 'ready\\n'
IFS= read -r fixture_exit
case "$fixture_exit" in
  HUP|INT|TERM)
    # Invoke the installed production trap body without sending a process signal.
    fixture_trap="$(trap -p "$fixture_exit")"
    fixture_trap="${fixture_trap#trap -- }"
    eval "set -- $fixture_trap"
    eval "$1" ;;
  abandon) trap - EXIT; exit 0 ;; # Simulate an exit which cannot run cleanup.
  *) exit "$fixture_exit" ;;
esac
''', "fixture", str(ROOT), str(lock), "island_trap_build_lock_cleanup" if build else "island_trap_lock_cleanup"], stdin=subprocess.PIPE, stdout=subprocess.PIPE,
                               stderr=subprocess.PIPE, text=True)
    assert select.select([process.stdout], [], [], 5)[0], "lock holder timed out"
    assert process.stdout.readline() == "ready\n"
    return process


def make_app(path):
    xpc = path / "Contents/XPCServices/NotchIslandXPCHelper.xpc"
    for bundle, identifier in [(path, "com.dongfengrui.Airlet"),
                               (xpc, "com.dongfengrui.Airlet.XPCHelper")]:
        (bundle / "Contents/MacOS").mkdir(parents=True)
        (bundle / "Contents/Info.plist").write_bytes(plistlib.dumps({"CFBundleIdentifier": identifier}))
    return xpc


with tempfile.TemporaryDirectory(prefix="notchisland-signing-tests-", dir="/private/tmp") as tmp:
    temporary = Path(tmp)
    lock = temporary / "operation.lock"
    contender = 'island_trap_lock_cleanup; island_acquire_lock "$2" fixture'
    owner = hold(lock, build=True)
    owner_text = (lock / "owner").read_text()
    loser = run(contender, lock)
    expect(loser.returncode != 0 and "is locked" in loser.stderr and
           (lock / "owner").read_text() == owner_text, "concurrent contender refuses without releasing the owner's lock")
    owner.communicate("0\n", timeout=5)
    expect(owner.returncode == 0 and not lock.exists(), "normal exit releases the owned lock")
    expect(run(contender, lock).returncode == 0 and not lock.exists(), "a later operation can acquire the released lock")

    owner = hold(lock)
    owner.communicate("7\n", timeout=5)
    expect(owner.returncode == 7 and not lock.exists(), "failed operation releases lock and preserves exit status")
    for name, code in [("HUP", 129), ("INT", 130), ("TERM", 143)]:
        owner = hold(lock, build=True)
        owner.communicate(name + "\n", timeout=5)
        marker = (lock / "interrupted").read_text()
        expect(owner.returncode == code and f"signal={name}" in marker and f"exit-status={code}" in marker,
               f"build/sign {name} handler retains lock with reason and exit status (no signal sent)")
        loser = run('island_trap_build_lock_cleanup; island_acquire_lock "$2" fixture', lock)
        expect(loser.returncode != 0 and "is locked" in loser.stderr and (lock / "interrupted").read_text() == marker,
               f"later build/sign refuses {name} residue without changing its interruption marker")
        (lock / "owner").unlink()
        (lock / "interrupted").unlink()
        lock.rmdir()

    owner = hold(lock, build=True)
    owner.communicate("7\n", timeout=5)
    expect(owner.returncode == 7 and "nonzero exit; exit-status=7" in (lock / "interrupted").read_text(),
           "nonzero build/sign exit conservatively preserves lock when descendants may remain")
    (lock / "owner").unlink()
    (lock / "interrupted").unlink()
    lock.rmdir()

    owner = hold(lock, build=True)
    owner.communicate("abandon\n", timeout=5)
    loser = run(contender, lock)
    expect(lock.exists() and loser.returncode != 0, "simulated abrupt exit without cleanup leaves a lock which cannot be stolen")
    (lock / "owner").unlink()
    lock.rmdir()
    target = temporary / "other-directory"
    target.mkdir()
    (target / "keep").write_text("keep")
    lock.symlink_to(target, target_is_directory=True)
    loser = run(contender, lock)
    expect(loser.returncode != 0 and "symlink operation lock" in loser.stderr and
           (target / "keep").read_text() == "keep", "symlink lock is rejected without modifying its target")
    lock.unlink()

    owner = hold(lock)
    (lock / "owner").write_text("different-owner\n")
    owner.communicate("0\n", timeout=5)
    expect(lock.is_dir() and (lock / "owner").read_text() == "different-owner\n",
           "cleanup does not remove a lock whose ownership changed")
    (lock / "owner").unlink()
    lock.rmdir()

    project = temporary / "project"
    project.mkdir()
    build_lock = project / "build/.NotchIsland-build.lock"
    build_lock.parent.mkdir()
    owner = hold(build_lock)
    loser = run('island_trap_lock_cleanup; island_acquire_build_lock "$2"', project)
    expect(loser.returncode != 0 and "Build/sign operation is locked" in loser.stderr,
           "build and standalone signing contend for the same canonical output lock")
    owner.communicate("0\n", timeout=5)

    # No native signing endpoints are called: rejection must happen before this sentinel.
    guarded_sign = '''
island_require_signing_identity() { printf 'UNEXPECTED_NATIVE_ACCESS\\n'; exit 91; }
island_signature_is_intact() { return 1; }
island_codesign_app "$2"
'''
    for index, component in enumerate([".", "Contents", "Contents/XPCServices",
                                     "Contents/XPCServices/NotchIslandXPCHelper.xpc"]):
        app = temporary / f"symlink-{index}.app"
        make_app(app)
        selected = app if component == "." else app / component
        relocated = temporary / f"relocated-{index}"
        selected.rename(relocated)
        selected.symlink_to(relocated, target_is_directory=True)
        rejected = run(guarded_sign, app)
        expect(rejected.returncode != 0 and "real bundle directory" in rejected.stderr and
               "UNEXPECTED_NATIVE_ACCESS" not in rejected.stdout,
               f"pre-mutation signing rejects symlink {component}")

    app = temporary / "broken-seal.app"
    xpc = make_app(app)
    rejected = run(guarded_sign, app)
    expect(rejected.returncode != 0 and "Invalid existing signature" in rejected.stderr and
           "clean/rebuild" in rejected.stderr and "UNEXPECTED_NATIVE_ACCESS" not in rejected.stdout,
           "invalid resource seal is refused before identity access, never auto-repaired")
    residue = xpc / "Contents/MacOS/NotchIslandXPCHelper.cstemp"
    residue.write_text("interrupted temporary code")
    rejected = run(guarded_sign, app)
    expect(rejected.returncode != 0 and "Stale signing temporary file" in rejected.stderr and
           residue.read_text() == "interrupted temporary code" and "UNEXPECTED_NATIVE_ACCESS" not in rejected.stdout,
           "stale .cstemp is diagnosed and preserved for explicit clean/rebuild")

    # Extract the actual cleanup function, not a rewritten copy of its transaction logic.
    installer = (ROOT / "scripts/install-local.sh").read_text()
    marker = "island_install_cleanup() {"
    assert installer.count(marker) == 1 and installer.count("\ntrap island_install_cleanup EXIT") == 1
    cleanup = marker + installer.split(marker, 1)[1].split("\ntrap island_install_cleanup EXIT", 1)[0]
    installer_traps = installer.split("\ntrap island_install_cleanup EXIT", 1)[1].split("\nisland_check_destination", 1)[0]
    for committed in [False, True]:
        transaction = temporary / ("committed" if committed else "rollback")
        transaction.mkdir()
        backup = transaction / "backup.app"
        backup.mkdir()
        (backup / "old").write_text("previous version")
        stage = transaction / "stage"
        stage.mkdir()
        (stage / "partial").write_text("incomplete staging")
        if committed:
            (transaction / "destination.app").mkdir()
            (transaction / "destination.app/new").write_text("replacement")
        cleanup_script = cleanup + '''
ISLAND_INSTALL_DESTINATION="$2/destination.app"
ISLAND_BACKUP_PATH="$2/backup.app"
ISLAND_STAGE_DIRECTORY="$2/stage"
ISLAND_OLD_MOVED=true
ISLAND_COMMITTED="$3"
trap island_install_cleanup EXIT
island_acquire_lock "$2/install.lock" fixture
exit 7
'''
        result = run(cleanup_script, transaction, str(committed).lower())
        expect(result.returncode == 7 and not stage.exists() and not (transaction / "install.lock").exists(),
               f"actual installer cleanup releases staging and lock, preserving exit status (committed={committed})")
        if committed:
            expect((backup / "old").read_text() == "previous version" and
                   (transaction / "destination.app/new").read_text() == "replacement",
                   "committed installation keeps the new destination and named old backup")
        else:
            expect(not backup.exists() and (transaction / "destination.app/old").read_text() == "previous version",
                   "failed final rename restores the exact prior application")

    for name, code in [("HUP", 129), ("INT", 130), ("TERM", 143)]:
        transaction = temporary / ("installer-" + name)
        transaction.mkdir()
        (transaction / "backup.app").mkdir()
        (transaction / "backup.app/old").write_text("previous version")
        (transaction / "stage").mkdir()
        cleanup_script = cleanup + '''
ISLAND_INSTALL_DESTINATION="$2/destination.app"
ISLAND_BACKUP_PATH="$2/backup.app"
ISLAND_STAGE_DIRECTORY="$2/stage"
ISLAND_OLD_MOVED=true
ISLAND_COMMITTED=false
trap island_install_cleanup EXIT
''' + installer_traps + '''
island_acquire_lock "$2/install.lock" fixture
fixture_trap="$(trap -p "$3")"
fixture_trap="${fixture_trap#trap -- }"
eval "set -- $fixture_trap"
eval "$1"
'''
        result = run(cleanup_script, transaction, name)
        expect(result.returncode == code and not (transaction / "stage").exists() and
               not (transaction / "install.lock").exists() and
               (transaction / "destination.app/old").read_text() == "previous version",
               f"actual installer {name} trap still rolls back and releases lock (no signal sent)")

expect("island_acquire_build_lock" in (ROOT / "scripts/build.sh").read_text() and
       "island_acquire_build_lock" in (ROOT / "scripts/codesign-local.sh").read_text() and
       "island_trap_build_lock_cleanup" in (ROOT / "scripts/build.sh").read_text() and
       "island_trap_build_lock_cleanup" in (ROOT / "scripts/codesign-local.sh").read_text() and
       'island_codesign_app "$ISLAND_BUILT_APP"' in (ROOT / "scripts/build.sh").read_text() and
       'bash "$ISLAND_PROJECT_ROOT/scripts/codesign-local.sh"' not in (ROOT / "scripts/build.sh").read_text(),
       "build invokes signing inside its existing lock without a nested lock process")
expect(installer.index('island_acquire_lock "$ISLAND_APPLICATIONS/.NotchIsland-install.lock"') <
       installer.index('ISLAND_STAGE_DIRECTORY="$(/usr/bin/mktemp') <
       installer.index('/bin/mv "$ISLAND_INSTALL_DESTINATION" "$ISLAND_BACKUP_PATH"'),
       "installer locks its fixed destination before staging and transactional renames")
print(f"Signing safety checks: {checks} passed (production functions, temporary fixtures only)")
