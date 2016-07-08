import requests
import logging

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
    body = dict(params)
    body['name'] = name
    response = _post(admin_api, "/apis/" + api + "/plugins/", body)
    return _ret_of_post(response, name)

def post_consumer(name, admin_api):
    response = _post(admin_api, "/consumers", {'username': name})
    return _ret_of_post(response, name)

def post_key(name, admin_api, key):
    response = _post(admin_api, "/consumers/" + name + "/key-auth/", {'key': key})
    return _ret_of_post(response, name)

def delete_consumer(name, admin_api):
    response = _delete(admin_api, "/consumers/" + name)
    return _ret_of_delete(response, name)

def _get(admin_api, path):
    url = admin_api + path
    logger.info("Request: GET %s\n" % url)
    response = requests.get(url)
    _log_response(response)
    return response

def _post(admin_api, path, body):
    url = admin_api + path
    logger.info("Request: POST %s\n%s\n" % (url, body))
    response = requests.post(url, data=body)
    _log_response(response)
    return response

def _patch(admin_api, path, body):
    url = admin_api + path
    logger.info("Request: PATCH %s\n%s\n" % (url, body))
    response = requests.post(url, data=body)
    _log_response(response)
    return response

def _delete(admin_api, path):
    url = admin_api + path
    logger.info("Request: DELETE %s\n" % url)
    response = requests.delete(url)
    _log_response(response)
    return response

def _log_response(response):
    logger.info("Response: %d\n%s\n" % (response.status_code, response.content))

def _ret_of_post(response, name):
    ret = _ret(response, name)
    ret['changes'] = _changes_of_post(response, name)
    ret['result'] = response.status_code in [201, 409]
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

