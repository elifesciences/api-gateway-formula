#!/bin/bash
set -ex

# ping works
[[ $(curl --silent localhost/ping) == "pong" ]]
[[ $(curl --silent --write-out '%{http_code}' --output /dev/null localhost/ping) = 200 ]]

# '/' redirects to '/documentation/'
[[ $(curl --silent --write-out '%{http_code}' --output /dev/null localhost/) = 301 ]]

# '/documentation' redirects to '/documentation/'
[[ $(curl --silent --write-out '%{http_code}' --output /dev/null localhost/documentation) = 301 ]]

# '/documentation/' is successful
[[ $(curl --silent --write-out '%{http_code}' --output /dev/null localhost/documentation/) = 200 ]]

# '/documentation/fooo' is unsuccessful and a telltale image is found in the response
[[ $(curl --silent --write-out '%{http_code}' --output /dev/null localhost/documentation/fooo) = 404 ]]
[[ $(curl --silent localhost/documentation/fooo | grep -o "/errors/404.png" ) == "/errors/404.png" ]]

