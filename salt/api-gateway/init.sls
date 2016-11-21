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
            # if you upgrade, somewhere down the line the init script
            # used in kong-init-script (which has never been an init script
            # but only a cli tool) will stop working as it does not respond
            # to `status` anymore
            # https://github.com/Mashape/kong/issues/3#issuecomment-249337198
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
    
kong-ulimit:
    file.append:
        # maximum file descriptors is 1024 and Kong complains about it being not optimal
        - name: /etc/security/limits.conf
        - text:
            - "* soft nofile 4096"
            - "* hard nofile 4096"
            - root soft nofile 4096
            - root hard nofile 4096
        - require: 
            - configure-kong-app

kong-ulimit-enable:
    file.append:
        - name: /etc/pam.d/su
        - text:
            - session required pam_limits.so
        - require:
            - kong-ulimit
            
kong-init-script:
    # kong's `kong` file implements the stop/start/restart/reload interface
    file.symlink:
        - name: /etc/init.d/kong
        - target: /usr/local/bin/kong
        - require:
            - pkg: install-kong

kong-api-calls-logs:
    file.directory:
        - name: /var/log/kong
        - dir_mode: 755

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
            - configure-kong-app
            - kong-ulimit-enable
            - kong-init-script
            - postgres_database: kong-db-exists
        - watch:
            # reload if config changes
            - file: configure-kong-app

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
            - kong-service 
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
            - service: kong-service
{% endfor %}

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
# remove API consumers, then add the new ones
# consumers requires plugins (key-auth plugin)
#

{% for name in app.absent_consumers %}
remove-consumer-{{ name }}:
    kong.delete_consumer:
        - name: {{ name }}
        - admin_api: {{ app.admin }}
        - require:
            - service: kong-service
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

