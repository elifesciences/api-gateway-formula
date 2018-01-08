api_gateway:

    admin: http://localhost:8001

    db:
        engine: postgres
        host: "127.0.0.1"
        port: 5432
        name: kong
        username: kong
        password: kong

    # known API endpoints
    # https://getkong.org/docs/0.8.x/admin-api/#add-api
    endpoints:
        echo:
            # taken from the demo
            upstream_url: https://httpbin.org/headers
            request_path: /echo
            strip_request_path: True

        example:
            upstream_url: http://example.com/
            request_path: /example
        
    # APIs that once existed but should not exist any longer
    absent_endpoints: 
        - not_there_anymore

    endpoint_plugins:
        echo:
            key-auth: 
                "config.hide_credentials": true
                "config.key_names": Authorization
            acl:
                "config.whitelist": "admin,user"
            file-log:
                "config.path": "/var/log/kong/echo.log"
        example:
            key-auth: 
                "config.hide_credentials": true
                "config.key_names": Authorization

    # known api consumers and their keys
    consumers:
        # user: key
        anonymous: public
        journal-prod: journal-prod-key
        journal-preview: journal-preview-key

    # api consumers who once existed but should not exist any longer
    absent_consumers:
        - some_old_consumer

    groups:
        journal-prod:
            - user
        journal-preview:
            - admin
            - view-unpublished-content
        anonymous:
            - user

    # groups who once were associated to a consumer but should not be associated any longer
    absent_groups:
        journal-preview:
            - admin
