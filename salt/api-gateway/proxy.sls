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

{% if pillar.elife.webserver.app == "caddy" %}

# caddy proxy
# this instance sits in front of kong and proxies all requests back and forth

proxy:
    file.managed:
        - name: /etc/caddy/sites.d/api-gateway
        - source: salt://api-gateway/config/etc-caddy-sites.d-api-gateway
        - makedirs: True
        - template: jinja
        - require:
            - api-documentation
        - watch_in:
            - service: caddy-server-service

{% else %}

# nginx proxy
# this instance sits in front of kong and proxies all requests back and forth

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

{% endif %}

smoke-tests:
    file.managed:
        - user: {{ pillar.elife.deploy_user.username }}
        - name: /home/{{ pillar.elife.deploy_user.username }}/smoke-tests.sh
        - source: salt://api-gateway/config/home-deploy-user-smoke-tests.sh
        - mode: 754
        - require:
            - proxy
