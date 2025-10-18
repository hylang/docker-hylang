#
# NOTE: THIS DOCKERFILE IS GENERATED VIA "apply-templates.sh"
#
# PLEASE DO NOT EDIT IT DIRECTLY.
#

FROM python:3.13-windowsservercore-ltsc2025

ENV HY_VERSION 1.1.0
ENV HYRULE_VERSION 1.0.0

RUN pip install --no-cache-dir ('hy == {0}' -f $env:HY_VERSION) ('hyrule == {0}' -f $env:HYRULE_VERSION)

CMD ["hy"]
