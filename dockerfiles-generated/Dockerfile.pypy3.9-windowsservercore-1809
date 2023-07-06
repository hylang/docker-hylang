FROM pypy:3.9-windowsservercore-1809

ENV HY_VERSION 0.27.0
ENV HYRULE_VERSION 0.4.0

RUN pip install --no-cache-dir ('hy == {0}' -f $env:HY_VERSION) ('hyrule == {0}' -f $env:HYRULE_VERSION)

CMD ["hy"]
