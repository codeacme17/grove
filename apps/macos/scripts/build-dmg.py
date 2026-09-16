import subprocess
import sys
from pathlib import Path

import dmgbuild
from ds_store import DSStore
from mac_alias import Bookmark


application, background, bookmark_tool, output = sys.argv[1:]
mount = None


def remember_mount(mount_point, options):
    global mount
    mount = Path(mount_point)


def finish_layout(event):
    if event.get("type") != "operation::finished" or event.get("operation") != "dsstore::create":
        return
    # Use Finder-compatible native bookmarks for the background on current macOS.
    bookmark = subprocess.check_output([bookmark_tool, str(mount / ".background.tiff")])
    with DSStore.open(str(mount / ".DS_Store"), "r+") as store:
        store["."]["pBBk"] = Bookmark.from_bytes(bookmark)
    subprocess.run(
        ["codesign", "--verify", "--deep", "--strict", str(mount / Path(application).name)],
        check=True,
    )


dmgbuild.build_dmg(
    output,
    "Grove",
    settings_file=str(Path(__file__).with_name("dmg-settings.py")),
    settings={"create_hook": remember_mount},
    defines={"app": application, "background": background},
    callback=finish_layout,
)
