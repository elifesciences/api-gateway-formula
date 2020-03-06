import requests
import logging
import json
import re

logger = logging.getLogger(__name__)

def post_api(name, admin_api, params={}):
    body = dict(params)
    body['name'] = name
    if _api_exists(admin_api, name):
        response = _patch(admin_api, "/apis/" + name, body)
        return _ret_of_patch(response, name)
    else:
        response = _post(admin_api, "/apis/", body)
        return _ret_of_post(response, name)

def _api_exists(admin_api, name):
    response = _get(admin_api, "/apis/" + name)
    assert response.status_code in [200, 404], "Strange response code: %s" % response
    return response.status_code == 200

def delete_api(name, admin_api):
    response = _delete(admin_api, "/apis/" + name)
    return _ret_of_delete(response, name)

def post_plugin(name, api, admin_api, params={}):
    existing_plugin = _plugin(admin_api, api, name)
    if existing_plugin:
        if existing_plugin['config'] == _plugin_config(params):
            return _ret_noop(name)
        else:
            # there may be another method to update a plugin,
            # but it's not documented in Kong
            path = "/apis/" + api + "/plugins/" + existing_plugin['id']
            assert _delete(admin_api, path).status_code == 204
    body = dict(params)
    body['name'] = name
    response = _post(admin_api, "/apis/" + api + "/plugins/", body)
    return _ret_of_post(response, name)

def _plugin(admin_api, api, name):
    response = _get(admin_api, "/apis/" + api + "/plugins")
    assert response.status_code in [200], "Strange response code: %s" % response
    matching = [plugin for plugin in json.loads(response.content.decode('utf-8'))['data'] if plugin['name'] == name]
    assert len(matching) <= 1
    if len(matching):
        return matching[0]
    else:
        return None

def _plugin_config(params):
    params_related_to_config = [param_key for param_key in list(params.keys()) if re.match(r"^config\..+", param_key)]
    _strip_config_prefix = lambda key: re.sub(r"^config\.", "", key)
    return {_strip_config_prefix(param_key): params[param_key] for param_key in params_related_to_config}

def post_consumer(name, admin_api):
    response = _post(admin_api, "/consumers", {'username': name})
    return _ret_of_post(response, name)

def post_key(name, admin_api, key):
    if _key_exists(admin_api, name, key):
        return _ret_noop(name)
    response = _post(admin_api, "/consumers/" + name + "/key-auth/", {'key': key})
    return _ret_of_post(response, name, [201])

def _key_exists(admin_api, name, key):
    response = _get(admin_api, "/consumers/" + name + "/key-auth/")
    assert response.status_code == 200, "Strange response code: %s" % response
    keys = [k['key'] for k in json.loads(response.content.decode('utf-8'))['data']]
    return key in keys

def post_acl(name, admin_api, group):
    if _acl_exists(admin_api, name, group):
        return _ret_noop(name)
    response = _post(admin_api, "/consumers/" + name + "/acls", {'group': group})
    return _ret_of_post(response, name)

def delete_acl(name, group, admin_api):
    if not _acl_exists(admin_api, name, group):
        return _ret_noop(name)
    response = _delete(admin_api, "/consumers/" + name + "/acls/" + group)
    return _ret_of_delete(response, name)

def _acl_exists(admin_api, name, group):
    response = _get(admin_api, "/consumers/" + name + "/acls")
    assert response.status_code in [200], "Strange response code: %s" % response
    return group in [acl['group'] for acl in json.loads(response.content.decode('utf-8'))['data']]

def delete_consumer(name, admin_api):
    response = _delete(admin_api, "/consumers/" + name)
    return _ret_of_delete(response, name)

def rename(data, pair_list):
    "mutator!"
    for old, new in pair_list:
        if old in data:
            data[new] = data[old]
            del data[old]

def upgrade_body(body):
    rename(body, [('strip_request_path', 'strip_uri'), ('request_path', 'uris')])

def _get(admin_api, path):
    url = admin_api + path
    logger.info("Request: GET %s\n" % url)
    response = requests.get(url)
    _log_response(response)
    return response

def _post(admin_api, path, body):
    url = admin_api + path
    upgrade_body(body)
    logger.info("Request: POST %s\n%s\n" % (url, body))
    response = requests.post(url, data=body)
    _log_response(response)
    return response

def _patch(admin_api, path, body):
    url = admin_api + path
    upgrade_body(body)
    logger.info("Request: PATCH %s\n%s\n" % (url, body))
    response = requests.patch(url, data=body)
    _log_response(response)
    return response

def _delete(admin_api, path):
    url = admin_api + path
    logger.info("Request: DELETE %s\n" % url)
    response = requests.delete(url)
    _log_response(response)
    return response

def _log_response(response):
    logger.info("Response: %d\n%s\n" % (response.status_code, response.content.decode('utf-8')))

def _ret_of_post(response, name, expected_status_codes=None):
    if not expected_status_codes:
        expected_status_codes = [201, 409]
    ret = _ret(response, name)
    ret['changes'] = _changes_of_post(response, name)
    ret['result'] = response.status_code in expected_status_codes
    return ret

def _ret_of_patch(response, name):
    ret = _ret(response, name)
    ret['changes'] = _changes_of_patch(response, name)
    ret['result'] = response.status_code == 200
    return ret

def _ret_of_delete(response, name):
    ret = _ret(response, name)
    ret['changes'] = _changes_of_delete(response, name)
    ret['result'] = response.status_code in [204, 404]
    return ret

def _changes_of_post(response, name):
    old = ''
    new = ''
    if response.status_code == 201:
        old = 'absent' 
        new = 'present'
    elif response.status_code == 409:
        old = 'present'
        new = 'present'
    return {name: {'old': old, 'new': new}}

def _changes_of_patch(response, name):
    old = ''
    new = ''
    if response.status_code == 200:
        old = 'present' 
        new = 'updated'
    elif response.status_code == 404:
        old = 'absent'
        new = 'absent'
    return {name: {'old': old, 'new': new}}

def _changes_of_delete(response, name):
    old = ''
    new = ''
    if response.status_code == 204:
        old = 'present' 
        new = 'absent'
    elif response.status_code == 404:
        old = 'absent'
        new = 'absent'
    return {name: {'old': old, 'new': new}}

def _ret(response, name):
    ret = {}
    ret['name'] = name
    ret['comment'] = "Response: %d" % response.status_code
    return ret

def _ret_noop(name):
    ret = {}
    ret['name'] = name
    ret['comment'] = "Nothing to do"
    ret['changes'] = {}
    ret['result'] = True
    return ret
