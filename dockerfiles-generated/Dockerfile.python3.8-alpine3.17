FROM python:3.8-alpine3.17

ENV HY_VERSION 0.27.0
ENV HYRULE_VERSION 0.4.0

RUN pip install --no-cache-dir "hy == $HY_VERSION" "hyrule == $HYRULE_VERSION"

CMD ["hy"]
