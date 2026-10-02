#!/usr/bin/env python3
"""Limit compositor resizing of Feishu notification toolbars, not meeting windows."""
import argparse
import fcntl
import os
from pathlib import Path
import time
from Xlib import X, Xatom, display, error

BACKUP = '_FEISHU_HYPRLAND_ORIGINAL_SIZE_HINTS'
SIZE_FLAGS = 16 | 32  # ICCCM PMinSize | PMaxSize


def prop(win, atom, kind=X.AnyPropertyType):
    return win.get_full_property(atom, kind)


def feishu_process(pid):
    try:
        return Path(f'/proc/{pid}/exe').resolve() == Path('/opt/bytedance/feishu/feishu')
    except (OSError, RuntimeError):
        return False


def scan(d, args):
    atoms = {n: d.intern_atom(n) for n in [
        '_NET_CLIENT_LIST', '_NET_WM_PID', '_NET_WM_NAME',
        '_NET_WM_WINDOW_TYPE', '_NET_WM_WINDOW_TYPE_NOTIFICATION',
        'WM_NORMAL_HINTS', 'WM_SIZE_HINTS', BACKUP,
    ]}
    root = d.screen().root
    clients = prop(root, atoms['_NET_CLIENT_LIST'], Xatom.WINDOW)
    changed = []
    ids = set(int(xid) for xid in clients.value) if clients is not None else set()
    if args.restore:
        ids.update(w.id for w in root.query_tree().children)
    for xid in ids:
        try:
            w = d.create_resource_object('window', int(xid))
            p = prop(w, atoms['_NET_WM_PID'], Xatom.CARDINAL)
            if p is None or not p.value:
                continue
            pid = int(p.value[0])
            if (args.pid and pid != args.pid) or not feishu_process(pid):
                continue
            saved = prop(w, atoms[BACKUP], Xatom.CARDINAL)
            if args.restore:
                if saved is not None:
                    original = list(saved.value)
                    if original and original[0]:
                        w.change_property(atoms['WM_NORMAL_HINTS'], atoms['WM_SIZE_HINTS'], 32, original[1:])
                    else:
                        w.delete_property(atoms['WM_NORMAL_HINTS'])
                    w.delete_property(atoms[BACKUP])
                    changed.append(f'Restored original hints on {hex(int(xid))}')
                continue
            if w.get_wm_class() != ('Meeting', 'Meeting'):
                continue
            title = prop(w, atoms['_NET_WM_NAME'])
            if title is None or bytes(title.value).decode('utf-8', errors='replace') != 'Feishu Meetings':
                continue
            types = prop(w, atoms['_NET_WM_WINDOW_TYPE'], Xatom.ATOM)
            if types is None or atoms['_NET_WM_WINDOW_TYPE_NOTIFICATION'] not in types.value:
                continue
            geometry = w.get_geometry()
            width, height = geometry.width, geometry.height
            # Never freeze a meeting window or a stale, oversized initial layout.
            if not (200 <= width <= 1600 and 20 <= height <= 100):
                continue
            current = prop(w, atoms['WM_NORMAL_HINTS'], atoms['WM_SIZE_HINTS'])
            raw = list(current.value) if current is not None else []
            values = raw + [0] * max(0, 18 - len(raw))
            if args.dry_run:
                changed.append(f'Eligible toolbar {hex(int(xid))}: {width}x{height}')
                continue
            if (values[0] & SIZE_FLAGS) == SIZE_FLAGS and values[5:9] == [width, height, width, height]:
                continue
            if saved is None:
                w.change_property(atoms[BACKUP], Xatom.CARDINAL, 32, [int(current is not None)] + raw)
            values[0] |= SIZE_FLAGS
            values[5:9] = [width, height, width, height]
            w.change_property(atoms['WM_NORMAL_HINTS'], atoms['WM_SIZE_HINTS'], 32, values)
            changed.append(f'Locked toolbar {hex(int(xid))}: {width}x{height}')
        except (error.BadWindow, error.BadAtom, error.BadMatch, OSError):
            continue  # Transient popup closed while being inspected.
    d.sync()
    return changed


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--pid', type=int)
    mode = parser.add_mutually_exclusive_group()
    mode.add_argument('--dry-run', action='store_true')
    mode.add_argument('--restore', action='store_true')
    args = parser.parse_args()
    runtime = Path(f'/run/user/{os.getuid()}')
    lock_fd = os.open(runtime / 'feishu-toolbar-size.lock', os.O_CREAT | os.O_RDWR | os.O_CLOEXEC | os.O_NOFOLLOW, 0o600)
    # Several popups can open together; preserve the original hints exactly once.
    fcntl.flock(lock_fd, fcntl.LOCK_EX)
    d = display.Display()
    d.set_error_handler(lambda e, request: None if isinstance(e, error.BadWindow) else print(f'X11 error: {e}'))
    try:
        # A newly mapped popup may receive its natural size a moment later.
        # This is a bounded startup check, not a background watcher.
        rounds = 1 if args.dry_run or args.restore else 8
        for i in range(rounds):
            for message in scan(d, args):
                print(message, flush=True)
            if i + 1 < rounds:
                time.sleep(0.2)
    finally:
        d.close()
        os.close(lock_fd)


if __name__ == '__main__':
    main()
