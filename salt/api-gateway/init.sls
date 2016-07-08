{% set app = pillar.api_gateway %}

install-kong-deps:
    pkg.installed:
        - pkgs:
            - netcat
            - openssl
            - libpcre3
            - dnsmasq
            - procps

install-kong:
    pkg.installed:
        - sources:
            - kong: https://github.com/Mashape/kong/releases/download/0.8.3/kong-0.8.3.trusty_all.deb
        - unless:
            - dpkg -l kong | grep kong
        - require:
            - pkg: install-kong-deps

configure-kong-app:
    file.managed:
        - name: /etc/kong/kong.yml
        - source: salt://api-gateway/config/etc-kong-kong.yml
        - template: jinja
        - require:
            - pkg: install-kong
    
    cmd.run:
        # default is 1024 this limits memory usage of R processes
        - name: ulimit -n 4096
            
kong-init-script:
    # kong's `kong` file implements the stop/start/restart/reload interface
    file.symlink:
        - name: /etc/init.d/kong
        - target: /usr/local/bin/kong
        - require:
            - pkg: install-kong


#
# db
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
#
#

kong-service:
    service.running:
        - name: kong
        - enable: True
        # supports reloading, but *some* config changes require a restart
        # change the interface from port 8000 to port 80 required a restart
        - reload: True
        - require:
            - file: configure-kong-app
            - file: kong-init-script
            - postgres_database: kong-db-exists
        - watch:
            # reload if config changes
            - file: configure-kong-app


#
# add/remove API endpoints
#

{% for name, params in app.endpoints.items() %}
add-api-endpoint-{{ name }}:
    kong.post_api:
        - name: {{ name }}
        - admin_api: {{ app.admin }}
        - params: {{ params }}
        - require:
            - service: kong-service
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
            - service: kong-service
            - add-api-endpoint-{{ endpoint }}
        - require_in:
            - cmd: all-plugins-installed
    {% endfor %}
{% endfor %}


all-plugins-installed:
    cmd.run:
        - name: echo "done"


#
# add/remove API consumers
# consumers requires plugins (key-auth plugin)
#

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

{% for name in app.absent_endpoints %}
remove-api-endpoint-{{ name }}:
    kong.delete_api:
        - name: {{ name }}
        - admin_api: {{ app.admin }}
        - require:
            - service: kong-service
{% endfor %}

{% for name in app.absent_consumers %}
remove-consumer-{{ name }}:
    kong.delete_consumer:
        - name: {{ name }}
        - admin_api: {{ app.admin }}
        - require:
            - service: kong-service
{% endfor %}

