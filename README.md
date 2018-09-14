# `api-gateway` formula

This repository contains instructions for installing and configuring the `api-gateway`
project.

This repository should be structured as any Saltstack formula should, but it 
should also conform to the structure required by the [builder](https://github.com/elifesciences/builder) 
project.

See the eLife [builder example project](https://github.com/elifesciences/builder-example-project)
for a reference on how to integrate with the `builder` project.

## Plugins used at eLife

- [key-authentication](https://docs.konghq.com/plugins/key-authentication/) (authenticating with Authorization)
- [acl](https://docs.konghq.com/plugins/acl/) (adding X-Consumer-Groups)
- [file-log](https://docs.konghq.com/plugins/file-log/) (logging requests and responses when needed)
- [cors](https://docs.konghq.com/plugins/cors/) (enabling CORS on selected APIs)
- [request-transformer](https://docs.konghq.com/plugins/request-transformer/) (adding headers to requests such as `Authorization`)
- [response-transformer](https://docs.konghq.com/plugins/response-transformer/) (adding headers to responses such as `Vary`)

## Copyright & Licence

Copyright 2016 eLife Sciences. Licensed under the [MIT license](LICENSE)

This program is free software: you can redistribute it and/or modify
it under the terms of the GNU General Public License as published by
the Free Software Foundation, either version 3 of the License, or
(at your option) any later version.

This program is distributed in the hope that it will be useful,
but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
GNU General Public License for more details.

You should have received a copy of the GNU General Public License
along with this program.  If not, see <http://www.gnu.org/licenses/>.
