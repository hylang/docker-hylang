FROM {{ .variants[env.variant].from }}

ENV HY_VERSION {{ .version }}
ENV HYRULE_VERSION {{ .hyrule.version }}

{{ if env.variant | contains("windows") then ( -}}
RUN pip install --no-cache-dir ('hy == {0}' -f $env:HY_VERSION) ('hyrule == {0}' -f $env:HYRULE_VERSION)
{{ ) else ( -}}
RUN pip install --no-cache-dir "hy == $HY_VERSION" "hyrule == $HYRULE_VERSION"
{{ ) end -}}

CMD ["hy"]
