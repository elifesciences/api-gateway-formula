import requests
import logging

logger = logging.getLogger(__name__)

def post_api(name, admin_api, params={}):
    body = dict(params)
    body['name'] = name
    response = _post(admin_api, "/apis/", body)
    ret = _ret(response, name)
    ret['changes'] = {name: {'old': '', 'new':'present'}}
    ret['result'] = response.status_code in [201, 409]
    return ret

def delete_api(name, admin_api):
    response = _delete(admin_api, "/apis/" + name)
    ret = _ret(response, name)
    ret['result'] = response.status_code in [200, 404]
    old = 'present' if response.status_code == 200 else 'absent'
    ret['changes'] = {name: {'old': old, 'new':'absent'}}
    return ret

def post_plugin(name, api, admin_api, params={}):
    body = dict(params)
    body['name'] = name
    response = _post(admin_api, "/apis/" + api + "/plugins/", body)
    ret = _ret(response, name)
    ret['changes'] = {name: {'old': '', 'new':'present'}}
    ret['result'] = response.status_code in [201, 409]
    return ret

def post_consumer(name, admin_api):
    response = _post(admin_api, "/apis/" + api + "/plugins/", {'username': name})
    ret = _ret(response, name)
    ret['changes'] = {name: {'old': '', 'new':'present'}}
    ret['result'] = response.status_code in [201, 409]
    return ret

def post_key(name, admin_api, key):
    response = _post(admin_api, "/consumers/" + name + "/key-auth/", {'key': key})
    ret = _ret(response, name)
    ret['changes'] = {name: {'old': '', 'new':'present'}}
    ret['result'] = response.status_code in [201, 409]
    return ret

def delete_consumer(name, admin_api):
    response = _delete(admin_api, "/consumers/" + name)
    ret = _ret(response, name)
    ret['changes'] = {name: {'old': 'present', 'new':'absent'}}
    ret['result'] = response.status_code in [200, 404]
    return ret

def _post(admin_api, path, body):
    url = admin_api + path
    logger.info("Request: POST %s\n%s\n" % (url, body))
    response = requests.post(url, data=body)
    logger.info("Response: %d\n%s\n" % (response.status_code, response.content))
    return response

def _delete(admin_api, path):
    url = admin_api + path
    logger.info("Request: DELETE %s\n" % url)
    response = requests.delete(url)
    logger.info("Response: %d\n%s\n" % (response.status_code, response.content))
    return response

def _ret(response, name):
    ret = {}
    ret['name'] = name
    ret['comment'] = "Response: %d" % response.status_code
    return ret

