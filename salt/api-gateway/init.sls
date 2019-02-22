{% set app = pillar.api_gateway %}

#
# nginx proxy
# this instance sits in front of kong and proxies all requests back and forth
#
#
api-documentation:
    git.latest:
        - name: git@github.com:elifesciences/api-raml.git
        - identity: {{ pillar.elife.projects_builder.key or '' }}
        - rev: master
        - branch: master
        - target: /srv/api-raml/
        - force_fetch: True
        - force_checkout: True
        - force_reset: True

    file.directory:
        - name: /srv/api-raml
        - user: {{ pillar.elife.deploy_user.username }}
        - group: {{ pillar.elife.deploy_user.username }}
        - recurse:
            - user
            - group
        - require:
            - git: api-documentation

proxy:
    file.managed:
        - name: /etc/nginx/sites-enabled/proxy.conf
        - source: salt://api-gateway/config/etc-nginx-sites-enabled-proxy.conf
        - makedirs: True
        - template: jinja
        - require:
            - api-documentation
        - watch_in:
            - service: nginx-server-service


#
# kong
#

install-kong-deps:
    pkg.installed:
        - pkgs:
            - netcat
            - openssl
            - libpcre3
            - dnsmasq
            - procps

remove-old-kong-ppa:
    pkgrepo.absent:
        - name: deb https://dl.bintray.com/mashape/kong-ubuntu-trusty-0.9.x trusty main

uninstall-old-kong:
    pkg.purged:
        - name: kong

install-kong:
    file.managed:
        - name: /root/bintray.gpg
        - source: salt://api-gateway/config/root-bintray.gpg
        # disabled because of intermittant failures with bintray.com
        #- source: https://bintray.com/user/downloadSubjectPublicKey?username=bintray

    cmd.run:
        - name: apt-key add /root/bintray.gpg
        - require:
            - file: install-kong

    pkgrepo.managed:
        {% if salt['grains.get']('oscodename') == 'xenial' %}
        - name: deb https://kong.bintray.com/kong-community-edition-deb xenial main
        {% else %}
        - name: deb https://kong.bintray.com/kong-community-edition-deb trusty main
        {% endif %}
        - require:
            - cmd: install-kong
            - remove-old-kong-ppa

    pkg.installed:
        - name: kong-community-edition
        - version: 0.11.2 # remember to update kong-migrations too
        - refresh: True # ensure pkgrepo is up to date
        - force_yes: True
        - require:
            - uninstall-old-kong
            - pkg: install-kong-deps

# lsh, 2019-02-19: I have no idea what this file does. It's referenced in the init scripts
kong-custom-nginx-configuration:
    file.managed:
        - name: /etc/kong/nginx.lua
        - source: salt://api-gateway/config/etc-kong-nginx.lua
        - require:
            - install-kong

kong-custom-nginx-configuration-2:
    file.managed:
        - name: /etc/kong/nginx_kong.lua
        - source: salt://api-gateway/config/etc-kong-nginx_kong.lua
        - backup: minion
        - require:
            - install-kong

configure-kong-app:
    file.managed:
        # Kong 0.9.6 causes problems if /etc/kong/kong.conf exists and there is
        # more than one nginx instance running
        # 2019-02-19: this doesn't appear to be a problem with 0.10.4
        # custom-kong.conf renamed back to kong.conf
        - name: /etc/kong/kong.conf
        - source: salt://api-gateway/config/etc-kong-kong.conf
        - template: jinja
        - require:
            - pkg: install-kong
            {% if salt['elife.cfg']('cfn.outputs.DomainName') %}
            - web-ssl-enabled
            {% endif %}
            - kong-custom-nginx-configuration

kong-ulimit:
    file.append:
        # maximum file descriptors is 1024 and Kong complains about it not being optimal
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
            
kong-api-calls-logs:
    file.directory:
        - name: /var/log/kong
        - user: nobody
        - group: root
        - dir_mode: 755
        - recurse:
            - mode

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

# new in 0.11.x: migrations must now be run manually
kong-migrations:
    cmd.run:
        - name: |
            set -e
            service kong stop || echo "kong not running"
            kong migrations up
            touch /root/kong-migrations-0.11.2.flag
            # service start? kong-service.service.running provides this
        - unless:
            - test -f /root/kong-migrations-0.11.2.flag
        - require:
            - kong-db-exists
            - kong-db-user

#
#
#

kong-upstart-script:
    file.managed:
        - name: /etc/init/kong.conf
        - source: salt://api-gateway/config/etc-init-kong.conf
        - template: jinja

kong-systemd-script:
    file.managed:
        - name: /lib/systemd/system/kong.service
        - source: salt://api-gateway/config/lib-systemd-system-kong.service
        - template: jinja

kong-service:
    service.running:
        - name: kong
        - enable: True
        # don't look for 'kong', look for 'nginx -p /usr/local/kong'
        - sig: nginx -p /usr/local/kong
        # supports reloading, but *some* config changes require a restart
        # change the interface from port 8000 to port 80 required a restart
        #- reload: True # disabled 2017-08-15. systemd+graceful reload not figured out yet
        - init_delay: 2 # kong needs a moment :(
        - require:
            - kong-migrations
            - kong-upstart-script
            - kong-systemd-script
            - configure-kong-app
            - kong-ulimit-enable
            - kong-api-calls-logs
        - watch:
            # reload if config changes
            - file: configure-kong-app

kong-checks:
    cmd.run:
        - name: kong check && kong health
        - require:
            - kong-service

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
