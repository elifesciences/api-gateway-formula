{% set app = pillar.api_gateway %}
{% set osrelease = salt['grains.get']('osrelease') %}

#
# kong
#

install-kong-deps:
    pkg.installed:
        - pkgs:
            {% if osrelease in ['14.04'] %}
            - netcat
            {% else %}
            # https://askubuntu.com/questions/346869/what-are-the-differences-between-netcat-traditional-and-netcat-openbsd
            #- netcat-openbsd
            - netcat-traditional
            {% endif %}
            - openssl
            - libpcre3
            - dnsmasq
            - procps

remove-old-kong-ppa:
    pkgrepo.absent:
        - name: deb https://dl.bintray.com/mashape/kong-ubuntu-trusty-0.9.x trusty main

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
        - name: deb https://kong.bintray.com/kong-community-edition-deb {{ salt['grains.get']('oscodename') }} main
        - require:
            - cmd: install-kong
            - remove-old-kong-ppa

    pkg.installed:
        - name: kong
        - version: 0.10.4
        - refresh: True # ensures pkgrepo is up to date
        - force_yes: True
        - require:
            - pkg: install-kong-deps

# TODO: remove once propagated
# this file had nginx configuration in it but it was never being picked up. we target the kong template directly now
kong-custom-nginx-configuration:
    file.absent:
        - name: /etc/kong/nginx.lua

# TODO: remove once propagated
kong-custom-nginx-configuration-1:
    file.absent:
        - name: /etc/kong/nginx_kong.lua

# target the kong template directly
# original file found can be found here given we're now overwriting it:
#   https://raw.githubusercontent.com/Kong/kong/0.10.4/kong/templates/nginx_kong.lua
# discussion about how everything is confusing and wrong here: 
#   https://github.com/Kong/kong/issues/1699
kong-custom-nginx-configuration-2:
    file.managed:
        - name: /usr/local/share/lua/5.1/kong/templates/nginx_kong.lua
        - source: salt://api-gateway/config/etc-kong-nginx_kong.lua # todo: update this filename
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
        - init_delay: 5 # kong needs a moment :(
        - require:
            - kong-upstart-script
            - kong-systemd-script
            - configure-kong-app
            - kong-ulimit-enable
            - postgres_database: kong-db-exists
            - kong-api-calls-logs
            # require nginx to be running with the nginx->kong proxy configuration 
            # before doing the api calls below
            - proxy 
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
