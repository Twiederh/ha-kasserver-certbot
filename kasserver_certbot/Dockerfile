ARG BUILD_FROM
FROM $BUILD_FROM

# Python + venv, damit certbot/kasserver nicht mit dem System-Python kollidieren
RUN apk add --no-cache \
        python3 \
        py3-pip \
        py3-virtualenv \
        bash \
        curl \
        jq \
        tzdata \
    && python3 -m venv /opt/venv \
    && /opt/venv/bin/pip install --no-cache-dir --upgrade pip \
    && /opt/venv/bin/pip install --no-cache-dir \
        certbot \
        kasserver

ENV PATH="/opt/venv/bin:${PATH}"

COPY run.sh /run.sh
RUN chmod a+x /run.sh

CMD [ "/run.sh" ]
