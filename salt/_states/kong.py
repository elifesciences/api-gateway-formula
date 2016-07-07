import requests
import logging

logger = logging.getLogger(__name__)

def post_api(name, admin_api, params):
    url = admin_api + "/apis/"
    body = dict(params)
    body['name'] = name
    logger.info("Request: POST %s\n%s\n" % (url, body))
    response = requests.post(url, data=body)
    logger.info("Response: %d\n%s\n" % (response.status_code, response.content))
    ret = {}
    ret['name'] = name
    ret['changes'] = {name: {'old': '', 'new':'present'}}
    ret['result'] = response.status_code in [200, 409]
    ret['comment'] = "Response: %d" % response.status_code
    return ret

