{% set app = pillar.api_gateway %}
{% set osrelease = salt['grains.get']('osrelease') %}

#
# kong db
#

kong-db-user:
    postgres_user.present:
        - name: {{ app.db.username }}
        - encrypted: True
        - password: {{ app.db.password }}
        - refresh_password: True
        
        - db_user: {{ pillar.elife.db_root.username }}
        - db_password: {{ pillar.elife.db_root.password }}
        - createdb: True

kong-db-exists:
    postgres_database.present:
        - name: {{ app.db.name }}
        - owner: {{ app.db.username }}
        - require:
            - postgres_user: kong-db-user

#
# old kong, config (removal)
#

# target the kong template directly
# original file found can be found here given we're now overwriting it:
#   https://raw.githubusercontent.com/Kong/kong/0.10.4/kong/templates/nginx_kong.lua
# discussion about how everything is confusing and wrong here: 
#   https://github.com/Kong/kong/issues/1699
kong-custom-nginx-configuration-2:
    file.absent:
        - name: /usr/local/share/lua/5.1/kong/templates/nginx_kong.lua

configure-kong-app:
    file.absent:
        - name: /etc/kong/kong.conf

#
# new kong, config (container)
#

kong-config-dir:
    file.directory:
        - user: {{ pillar.elife.deploy_user.username }}
        - name: /opt/kong
        - makedirs: True

# target the kong template directly
# original file found can be found here given we're now overwriting it:
#   https://raw.githubusercontent.com/Kong/kong/0.10.4/kong/templates/nginx_kong.lua
# discussion about how everything is confusing and wrong here: 
#   https://github.com/Kong/kong/issues/1699
kong-config-nginx+lua:
    file.managed:
        - name: /opt/kong/nginx_kong.lua
        - source: salt://api-gateway/config/etc-kong-nginx_kong.lua # todo: update this filename
        - backup: minion
        - require:
            - kong-config-dir

kong-config:
    file.managed:
        - name: /opt/kong/kong.conf
        - source: salt://api-gateway/config/etc-kong-kong.conf
        - template: jinja
        - require:
            - kong-config-dir

kong-docker-compose:
    file.managed:
        - name: /opt/kong/docker-compose.yaml
        - source: salt://api-gateway/config/opt-kong-docker-compose.yaml
        - template: jinja
        - require:
            - kong-config-dir

kong-api-calls-logs:
    file.directory:
        - name: /var/log/kong
        - user: nobody
        - group: root
        - dir_mode: 755
        - recurse:
            - mode

#
# old kong, kong service (disable)
#

# TODO: remove
kong-systemd-script:
    file.absent:
        - name: /lib/systemd/system/kong.service
        - source: salt://api-gateway/config/lib-systemd-system-kong.service
        - template: jinja

# TODO: remove
kong-service:
    service.dead:
        - name: kong
        - enable: False
        # don't look for 'kong', look for 'nginx -p /usr/local/kong'
        - sig: nginx -p /usr/local/kong

#
# new kong, container service
# 

get-kong:
    docker_image.present:
        - name: elifesciences/kong
        - tag: {{ pillar.api_gateway.kong_container.image_tag }}
        - force: true # always check remote
        - require:
            - docker-ready

{% if pillar.elife.env == "dev" %}

# good for development.
# just clone or move the 'kong-container' repository into the root of your builder installation.
build-kong:
    docker_image.present:
        - name: elifesciences/kong
        # if env == dev then this is 'latest' by default
        - tag: {{ pillar.api_gateway.kong_container.image_tag }}
        - build: /vagrant/kong-container
        - force: true
        - require_in:
            - service: kong-container-service
        - watch_in:
            - service: kong-container-service
        - onlyif:
            - test -e /vagrant/kong-container/Dockerfile

{% endif %}

kong-container-service:
    file.managed:
        - name: /lib/systemd/system/kong-container.service
        - source: salt://api-gateway/config/lib-systemd-system-kong-container.service
        - template: jinja

    service.running:
        - name: kong-container
        - enable: True
        - init_delay: 5 # kong needs a moment :(
        - require:
            - proxy
            - service: kong-service # old kong service must be stopped
            - file: kong-container-service
            - get-kong
            - kong-docker-compose
            - kong-config-nginx+lua
            - kong-config
            - kong-db-exists
            - kong-api-calls-logs
        - watch:
            - kong-docker-compose
            - kong-config
            - kong-config-nginx+lua

#
#
#

kong-logrotate:
    file.managed:
        - name: /etc/logrotate.d/kong
        - source: salt://api-gateway/config/etc-logrotate.d-kong

kong-syslog-ng-for-nginx-logs:
    file.managed:
        - name: /etc/syslog-ng/conf.d/kong.conf
        - source: salt://api-gateway/config/etc-syslog-ng-conf.d-kong.conf
        - template: jinja
        - require:
            - syslog-ng
            - kong-container-service 
        - listen_in:
            - service: syslog-ng

#
# remove API endpoints, add the new ones
#

{% for name in app.absent_endpoints %}
remove-api-endpoint-{{ name }}:
    kong.delete_api:
        - name: {{ name }}
        - admin_api: {{ app.admin }}
        - require:
            - service: kong-container-service
{% endfor %}

{% for name, params in app.endpoints.items() %}
add-api-endpoint-{{ name }}:
    kong.post_api:
        - name: {{ name }}
        - admin_api: {{ app.admin }}
        - params: {{ params }}
        - require:
            - service: kong-container-service
{% endfor %}
        


#
# add/remove Kong plugins
# plugins depend on api endpoints
#

{% for endpoint, plugin_list in app.endpoint_plugins.items() %}
    {% for plugin, params in plugin_list.items() %}

add-plugin-{{ plugin }}-for-{{ endpoint }}:
    kong.post_plugin:
        - name: {{ plugin }}
        - api: {{ endpoint }}
        - admin_api: {{ app.admin }}
        - params: {{ params }}
        - require:
            - service: kong-container-service
            - add-api-endpoint-{{ endpoint }}
        - require_in:
            - cmd: all-plugins-installed
    {% endfor %}
{% endfor %}


all-plugins-installed:
    cmd.run:
        - name: echo "done"


#
# remove API consumers, then add the new ones
# consumers requires plugins (key-auth plugin)
#

{% for name in app.absent_consumers %}
remove-consumer-{{ name }}:
    kong.delete_consumer:
        - name: {{ name }}
        - admin_api: {{ app.admin }}
        - require:
            - service: kong-container-service
{% endfor %}


{% for name, key in app.consumers.items() %}
add-consumer-{{ name }}:
    kong.post_consumer:
        - name: {{ name }}
        - admin_api: {{ app.admin }}
        - require:
            - cmd: all-plugins-installed

add-consumer-{{ name }}-key:
    kong.post_key:
        - name: {{ name }}
        - admin_api: {{ app.admin }}
        - key: '{{ key }}'
        - require:
            - cmd: all-plugins-installed
            - kong: add-consumer-{{ name }}
{% endfor %}

{% for user, groups in app.groups.items() %}
{% for group in groups %}
associate-consumer-{{ user }}-to-group-{{ group }}:
    kong.post_acl:
        - name: {{ user }}
        - admin_api: {{ app.admin }}
        - group: {{ group }}
        - require:
            - add-consumer-{{ user }}
{% endfor %}
{% endfor %}

{% for user, groups in app.absent_groups.items() %}
{% for group in groups %}
disassociate-consumer-{{ user }}-from-group-{{ group }}:
    kong.delete_acl:
        - name: {{ user }}
        - admin_api: {{ app.admin }}
        - group: {{ group }}
        - require:
            - add-consumer-{{ user }}
{% endfor %}
{% endfor %}
