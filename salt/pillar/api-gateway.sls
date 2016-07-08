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
        bunyip:
            # taken from the demo
            upstream_url: http://mockbin.com/
            request_host: mockbin.com

        example:
            upstream_url: http://example.com/
            request_path: /example
        
    # APIs that once existed but should not exist any longer
    absent_endpoints: 
        - bunyip

    endpoint_plugins:
        bunyip:
            key-auth: {}

    # known api consumers and their keys
    consumers:
        # user: key
        bottersnipe: gumble

    # api consumers who once existed but should not exist any longer
    absent_consumers:
        - bottersnipe
