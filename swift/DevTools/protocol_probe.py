#!/usr/bin/env python3
"""One browser-equivalent login, read-only APIs, no secret output or retries."""
import json
import pathlib
import re
import urllib.request
import urllib.parse
import http.cookiejar


def main():
    settings = json.loads((pathlib.Path.home() / 'Library/Application Support/WagongDeck/settings.json').read_text())
    base = settings['XUI_BASE_URL'].rstrip('/')
    origin = urllib.parse.urlsplit(base)
    session = urllib.request.build_opener(urllib.request.HTTPCookieProcessor(http.cookiejar.CookieJar()))
    page = session.open(base + '/', timeout=25).read().decode()
    match = re.search(r'<meta[^>]*name="csrf-token"[^>]*content="([^"]+)"', page)
    if match is None:
        raise ValueError('missing CSRF metadata')
    token = match.group(1)
    headers = {'X-CSRF-Token': token, 'X-Requested-With': 'XMLHttpRequest',
               'Origin': origin.scheme + '://' + origin.netloc, 'Referer': base + '/',
               'Content-Type': 'application/x-www-form-urlencoded; charset=UTF-8'}
    def post(path, fields):
        request = urllib.request.Request(base + path, urllib.parse.urlencode(fields).encode(), headers)
        with session.open(request, timeout=25) as response:
            return json.load(response)
    factor = post('/getTwoFactorEnable', {})
    print('two_factor_enabled=' + str(factor.get('obj')).lower())
    result = post('/login', {'username': settings['XUI_USERNAME'], 'password': settings['XUI_PASSWORD'],
                             'twoFactorCode': settings.get('XUI_TWO_FACTOR', '')})
    print('browser_protocol_login_success=' + str(result.get('success')).lower())
    if result.get('success') is not True:
        return 1
    request = urllib.request.Request(base + '/panel/api/inbounds/list', headers=headers)
    with session.open(request, timeout=25) as response:
        result = json.load(response)
    if result.get('success') is not True or not isinstance(result.get('obj'), list):
        print('read_list_success=false')
        return 1
    print('clients=' + str(sum(len(x.get('clientStats') or []) for x in result['obj'])))
    return 0

if __name__ == '__main__':
    try:
        raise SystemExit(main())
    except Exception as error:
        print('probe_failed=' + type(error).__name__)
        raise SystemExit(1)
