#!/usr/bin/env python3
"""
Main CLI to set Codespace port visibility.
Usage: python3 set_port_visibility.py <port> <public|private|org> [codespace_name]
"""

import os
import sys
import subprocess

# Add skill scripts to path
sys.path.insert(0, os.path.join(os.path.dirname(__file__)))
from get_codespace_token import set_github_token_env

def set_port_visibility(port: int, visibility: str, codespace_name: str = None):
    """Set port visibility for a codespace."""
    set_github_token_env()
    
    if not codespace_name:
        codespace_name = os.environ.get('CODESPACE_NAME')
        if not codespace_name:
            raise RuntimeError("CODESPACE_NAME not set")
    
    result = subprocess.run([
        'gh', 'codespace', 'ports', 'visibility',
        f'{port}:{visibility}',
        '-c', codespace_name
    ], capture_output=True, text=True)
    
    if result.returncode != 0:
        raise RuntimeError(f"Failed: {result.stderr}")
    
    return True

def list_ports(codespace_name: str = None):
    """List all ports and their visibility."""
    set_github_token_env()
    
    if not codespace_name:
        codespace_name = os.environ.get('CODESPACE_NAME')
    
    result = subprocess.run([
        'gh', 'codespace', 'ports', '-c', codespace_name
    ], capture_output=True, text=True)
    
    return result.stdout

if __name__ == '__main__':
    if len(sys.argv) < 2:
        print(f"Usage: {sys.argv[0]} <port> <public|private|org> [codespace_name]")
        print(f"       {sys.argv[0]} list [codespace_name]")
        sys.exit(1)
    
    if sys.argv[1] == 'list':
        codespace = sys.argv[2] if len(sys.argv) > 2 else None
        print(list_ports(codespace))
        sys.exit(0)
    
    if len(sys.argv) < 3:
        print(f"Usage: {sys.argv[0]} <port> <public|private|org> [codespace_name]")
        sys.exit(1)
    
    port = int(sys.argv[1])
    visibility = sys.argv[2]
    codespace = sys.argv[3] if len(sys.argv) > 3 else None
    
    set_port_visibility(port, visibility, codespace)
    print(f"Port {port} set to {visibility}")