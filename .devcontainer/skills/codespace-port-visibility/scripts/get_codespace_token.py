#!/usr/bin/env python3
"""
Reusable module to extract GITHUB_TOKEN from vscode-server process environment.
"""

import os
import glob

def get_codespace_token():
    """Extract GITHUB_TOKEN from vscode-server process environment."""
    # Find code-server process
    for pid_path in glob.glob('/proc/*/cmdline'):
        try:
            with open(pid_path, 'rb') as f:
                cmdline = f.read()
                if b'code-server' in cmdline:
                    pid = pid_path.split('/')[2]
                    with open(f'/proc/{pid}/environ', 'rb') as ef:
                        data = ef.read()
                        for entry in data.split(b'\x00'):
                            if entry.startswith(b'GITHUB_TOKEN='):
                                return entry.decode()[len('GITHUB_TOKEN='):]
        except (PermissionError, FileNotFoundError, IndexError):
            continue
    raise RuntimeError("Could not find GITHUB_TOKEN in vscode-server process")

def set_github_token_env():
    """Set GITHUB_TOKEN in os.environ."""
    token = get_codespace_token()
    os.environ['GITHUB_TOKEN'] = token
    return token

if __name__ == '__main__':
    token = set_github_token_env()
    print(f"export GITHUB_TOKEN={token}")