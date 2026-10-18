#!/usr/bin/env python3
"""Check only Keychain metadata; never request or print credential data."""
import os
import re
import subprocess
import sys

helper = os.path.expanduser('~/Library/Application Support/Bandwagon/BandwagonCredentialBridge')
keychain = os.path.expanduser('~/Library/Keychains/login.keychain-db')
signing = subprocess.run(['codesign', '-d', '--verbose=4', helper],
                         capture_output=True, text=True, timeout=20)
match = re.search(r'CDHash=([0-9a-fA-F]+)', signing.stderr)
if signing.returncode or not match:
    sys.exit('FAIL cannot determine installed helper code hash')
helper_cdhash = match.group(1).lower()

metadata = subprocess.run(['security', 'dump-keychain', '-a', keychain],
                          capture_output=True, text=True, timeout=45)
if metadata.returncode:
    sys.exit('FAIL cannot inspect login Keychain metadata')
text = metadata.stdout

def item(service):
    marker = '"svce"<blob>="' + service + '"'
    position = text.find(marker)
    if position < 0:
        return None
    start = text.rfind('keychain:', 0, position)
    end = text.find('keychain:', position)
    return text[max(start, 0):end if end >= 0 else len(text)]

v3 = item('com.kun.bandwagon.credentials.v3')
v2 = item('com.kun.bandwagon.credentials.v2')
v1 = item('com.kun.bandwagon.credentials')
if not v3 or not v2 or not v1:
    sys.exit('FAIL v3 or preserved legacy Keychain item missing')
partition = re.search(r'authorizations \(1\): partition_id\s+don.t-require-password\s+description: cdhash:([0-9a-fA-F]+)', v3)
if not partition or partition.group(1).lower() != helper_cdhash:
    sys.exit('FAIL v3 partition is not bound to the fixed helper binary')
if f'0: {helper} (OK)' not in v3 or 'description: unsigned:' in v3 or 'description: apple-tool:' in v3:
    sys.exit('FAIL v3 ACL does not restrict decrypt access to the signed helper')
print('PASS v3 ACL pinned to unchanged signed helper; v1/v2 items preserved')
