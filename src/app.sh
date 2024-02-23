#!/usr/bin/env bash

# DEBUG=1

DB_PATH="./db.sqlite3"


__FILE__="$(readlink -f ${BASH_SOURCE[0]})"
__DIR__="${__FILE__%/*}"


function handle_request() {
	local state_read_prelude=0
	local state_read_headers=1
	local state_read_body=2
	local state_write_response=3

	local current_state=$state_read_prelude

	REQUEST_BODY=""
	while read -e -r line; do
		local line="${line%$'\r'}"
		local line_lc="${line,,}"

		if [[ $current_state -eq $state_read_prelude ]]; then
			REQUEST_PATH="${line% *}"
			REQUEST_METHOD="${REQUEST_PATH% *}"
			REQUEST_PATH="${REQUEST_PATH#* }"
			current_state=$state_read_headers
		elif [[ $current_state -eq $state_read_headers ]]; then
			if [[ "${line_lc}" == "content-length:"* ]]; then
				REQUEST_CONTENT_LENGTH="${line_lc#content-length: }"
			elif [[ "${line_lc}" == "" ]]; then
				if [[ ${REQUEST_CONTENT_LENGTH} -gt 0 ]]; then
					current_state=$state_read_body
				else
					current_state=$state_write_response
					break
				fi
			fi
		fi

		if [[ $current_state -eq $state_read_body ]]; then
			read -N${REQUEST_CONTENT_LENGTH} -t1 line
			REQUEST_BODY+="${line}"
			break
		fi
	done

	if [[ $REQUEST_PATH =~ /([0-9]+)/ ]]; then
			CLIENT_ID="${BASH_REMATCH[1]}"
	fi
	REQUEST_ROUTE="${REQUEST_METHOD} ${REQUEST_PATH//${CLIENT_ID}/:id}"

	case ${REQUEST_ROUTE} in
		"GET /clientes/:id/extrato")			handle_GET_extrato $CLIENT_ID ;;
		"POST /clientes/:id/transacoes")	handle_POST_transacoes $CLIENT_ID "${REQUEST_BODY}" ;;
		*)																handle_route_unknown ;;
	esac
}

function http_response() {
	local RESPONSE_STATUS="${1}"
	local RESPONSE_BODY="${2}"

	local _TZ=${TZ}
	local _LC_TIME=${LC_TIME}

	export TZ=GMT
	export LC_TIME=en_US.UTF-8

	printf "HTTP/1.1 %s\r\n" "${RESPONSE_STATUS}"
	printf "Date: %(%a, %d %b %Y %H:%M:%S GMT)T\r\n"
	printf "Server: bash\r\n"
	printf "Content-Type: application/json\r\n"
	printf "Connection: close\r\n"
	printf "Content-Length: %d\r\n" "${#RESPONSE_BODY}"
	printf "\r\n"
	printf "%s" "${RESPONSE_BODY}"

	TZ=${_TZ}
	LC_TIME=${_LC_TIME}

	exit 0
}

function sql() {
	sqlite3 \
		-cmd '.output /dev/null' \
		-cmd 'PRAGMA jounal_mode=WAL;' \
		-cmd 'PRAGMA synchronous=NORMAL;' \
		-cmd 'PRAGMA busy_timeout=5000' \
		-cmd '.timeout 5000' \
		-cmd '.output stdout' \
		"${@}" 2> >(grep -v 'database is locked' >&2)
}

function tap() {
	[[ -n "$DEBUG" ]] && tee -a "${1}" || cat
}

function get_bank_statement() {
	local CLIENT_ID=${1}

	echo "SELECT json_object(
		'saldo', json_object(
			'total', saldo,
			'limite', limite,
			'data_extrato', strftime('%Y-%m-%dT%H:%M:%fZ')
		),
		'ultimas_transacoes', json(ultimas_transacoes)
	) FROM clientes WHERE id = ${CLIENT_ID};" | sql "${DB_PATH}"
}

function insert_transaction() {
	local CLIENT_ID=${1}
	local TX="${2//\'/\'\'}"

	echo "UPDATE clientes 
		SET saldo=saldo + (
			SELECT CASE WHEN tipo == 'd' THEN -valor ELSE valor END as valor FROM (
				SELECT json_extract(value, '$.tipo') tipo, json_extract(value, '$.valor') valor FROM json_each('[${TX}]')
			)
		), ultimas_transacoes=(
			SELECT json_remove(json_group_array(json(value)), '"'$[10]'"') txs FROM (
				SELECT id, value FROM (
					SELECT json_insert(json_group_array(json(value)), '"'$[#]'"', json_set('${TX}', '$.realizada_em', strftime('%Y-%m-%dT%H:%M:%fZ'))) txs FROM (
						SELECT txs.value FROM clientes c, json_each(c.ultimas_transacoes) txs WHERE c.id=${CLIENT_ID} ORDER BY key DESC
					)
				) temp, json_each(temp.txs) ORDER BY key DESC
			)
		) WHERE id=${CLIENT_ID} AND (saldo + (
			SELECT CASE WHEN tipo == 'd' THEN -valor ELSE valor END as valor FROM (
				SELECT json_extract(value, '$.tipo') tipo, json_extract(value, '$.valor') valor FROM json_each('[${TX}]')
			)
		)) >= -limite RETURNING json_object('saldo', saldo, 'limite', limite);" | sql "${DB_PATH}"
}

function check_client_exists() {
	local CLIENT_ID="${1}"

	if (( "${CLIENT_ID}" < 1 || "${CLIENT_ID}" > 5 )); then
		http_response 404 '{"error":"cliente nao encontrado"}'
	fi
}

function check_transaction_request() {
	local TX="${1}"

	RESULT=$(echo "${TX}" | jq '
		(.tipo == "d" or .tipo == "c")
			and ((.valor | type) == "number")
			and ((.valor | trunc) == .valor)
			and .valor > 0
			and (1 <= (.descricao | length) and (.descricao | length) <= 10)
	')
	if [[ "${RESULT}" != "true" ]]; then
		http_response 422 '{"error":""}'
	fi
}

function handle_GET_extrato() {
	local CLIENT_ID="${1}"

	check_client_exists "${CLIENT_ID}"

	local BANK_STATEMENT=$(get_bank_statement "${CLIENT_ID}")

	http_response 200 "${BANK_STATEMENT}"
}

function handle_POST_transacoes() {
	local CLIENT_ID="${1}"
	local TX="${2}"

	check_client_exists "${CLIENT_ID}"
	check_transaction_request "${TX}"

	local RESULT=$(insert_transaction "${CLIENT_ID}" "${TX}")

	if [[ "${RESULT}" == "" ]]; then
		http_response 422 '{ "error": "limite insuficiente" }'
	fi

	http_response "200 OK" "${RESULT}"
}

function handle_route_unknown() {
	http_response 404 '{ "error": "funcionalidade nao encontrada" }'
}


lock_file="/tmp/socat-lock-$(( ( RANDOM % 8 )  + 1 ))"

exec 4< "$lock_file"
flock 4
handle_request
exec 4<&-
