#!/usr/bin/with-contenv bashio
# ==============================================================================
# Home Assistant Add-on: Let's Encrypt via All-Inkl KAS (kasserver)
# ==============================================================================
set -e

CONFIG_PATH=/data/options.json
LE_DIR=/data/letsencrypt
SSL_DIR=/ssl

mkdir -p "${LE_DIR}"

# ---- Optionen einlesen ------------------------------------------------------
EMAIL=$(bashio::config 'email')
KAS_USER=$(bashio::config 'kas_user')
KAS_PASSWORD=$(bashio::config 'kas_password')
STAGING=$(bashio::config 'staging')
CERT_NAME=$(bashio::config 'cert_name')
KEY_TYPE=$(bashio::config 'key_type')
PROP_SECONDS=$(bashio::config 'propagation_seconds')
RENEW_INTERVAL=$(bashio::config 'renew_check_interval_hours')
AUTO_RESTART=$(bashio::config 'auto_restart_core')

if bashio::config.is_empty 'kas_user' || bashio::config.is_empty 'kas_password'; then
    bashio::exit.nok "kas_user und kas_password müssen gesetzt sein."
fi

# Domains als Array aus der JSON-Config lesen
mapfile -t DOMAINS < <(jq -r '.domains[]' "${CONFIG_PATH}")
if [ "${#DOMAINS[@]}" -eq 0 ]; then
    bashio::exit.nok "Es muss mindestens eine Domain in 'domains' konfiguriert werden."
fi

DOMAIN_ARGS=()
for d in "${DOMAINS[@]}"; do
    DOMAIN_ARGS+=("-d" "${d}")
done

export KASSERVER_USER="${KAS_USER}"
export KASSERVER_PASSWORD="${KAS_PASSWORD}"

STAGING_ARG=""
if bashio::config.true 'staging'; then
    bashio::log.warning "Staging-Modus aktiv - es werden KEINE vertrauenswürdigen Zertifikate ausgestellt!"
    STAGING_ARG="--staging"
fi

# ---- Hilfsfunktion: certbot ausführen ---------------------------------------
run_certbot() {
    certbot certonly \
        --non-interactive \
        --agree-tos \
        -m "${EMAIL}" \
        --config-dir "${LE_DIR}/config" \
        --work-dir "${LE_DIR}/work" \
        --logs-dir "${LE_DIR}/logs" \
        --cert-name "${CERT_NAME}" \
        --key-type "${KEY_TYPE}" \
        --preferred-challenges dns \
        --manual \
        --manual-auth-hook kasserver-dns-certbot \
        --manual-cleanup-hook kasserver-dns-certbot \
        --manual-public-ip-logging-ok \
        ${STAGING_ARG} \
        "${DOMAIN_ARGS[@]}"
}

# ---- Hilfsfunktion: certbot renew --------------------------------------------
run_certbot_renew() {
    certbot renew \
        --non-interactive \
        --config-dir "${LE_DIR}/config" \
        --work-dir "${LE_DIR}/work" \
        --logs-dir "${LE_DIR}/logs"
}

# ---- Zertifikate nach /ssl kopieren ------------------------------------------
publish_cert() {
    local live_dir="${LE_DIR}/config/live/${CERT_NAME}"
    if [ ! -d "${live_dir}" ]; then
        bashio::log.error "Kein Zertifikat unter ${live_dir} gefunden."
        return 1
    fi

    local fullchain_target="${SSL_DIR}/${CERT_NAME}_fullchain.pem"
    local privkey_target="${SSL_DIR}/${CERT_NAME}_privkey.pem"

    local old_hash=""
    [ -f "${fullchain_target}" ] && old_hash=$(sha256sum "${fullchain_target}" | cut -d' ' -f1)

    cp -L "${live_dir}/fullchain.pem" "${fullchain_target}"
    cp -L "${live_dir}/privkey.pem" "${privkey_target}"
    chmod 600 "${privkey_target}"

    local new_hash
    new_hash=$(sha256sum "${fullchain_target}" | cut -d' ' -f1)

    if [ "${old_hash}" != "${new_hash}" ]; then
        bashio::log.info "Zertifikat wurde aktualisiert (${fullchain_target})."
        if bashio::config.true 'auto_restart_core'; then
            bashio::log.info "Starte Home Assistant Core neu, damit das neue Zertifikat geladen wird..."
            curl -sSf -X POST \
                -H "Authorization: Bearer ${SUPERVISOR_TOKEN}" \
                -H "Content-Type: application/json" \
                http://supervisor/core/restart >/dev/null \
                || bashio::log.warning "Neustart von Home Assistant Core über die Supervisor-API fehlgeschlagen."
        fi
    else
        bashio::log.info "Zertifikat unverändert."
    fi
}

# ---- Erstmaliges Zertifikat, falls noch keins existiert ----------------------
if [ ! -d "${LE_DIR}/config/live/${CERT_NAME}" ]; then
    bashio::log.info "Kein bestehendes Zertifikat gefunden - fordere neues Zertifikat an für: ${DOMAINS[*]}"
    export CERTBOT_DNS_PROPAGATION_SECONDS="${PROP_SECONDS}"
    if run_certbot; then
        publish_cert
    else
        bashio::exit.nok "Zertifikatsanforderung fehlgeschlagen. Siehe Log oberhalb."
    fi
else
    bashio::log.info "Bestehendes Zertifikat gefunden, prüfe auf Erneuerung..."
    run_certbot_renew || bashio::log.warning "certbot renew meldete einen Fehler, versuche es beim nächsten Intervall erneut."
    publish_cert || true
fi

# ---- Dauerschleife: regelmäßig auf Erneuerung prüfen -------------------------
bashio::log.info "Add-on läuft. Erneuerungsprüfung alle ${RENEW_INTERVAL} Stunden."
while true; do
    sleep "$(( RENEW_INTERVAL * 3600 ))"
    bashio::log.info "Prüfe Zertifikatserneuerung..."
    if run_certbot_renew; then
        publish_cert || true
    else
        bashio::log.warning "certbot renew fehlgeschlagen, nächster Versuch in ${RENEW_INTERVAL} Stunden."
    fi
done
