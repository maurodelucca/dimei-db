#!/usr/bin/env bash

#
# Docker entrypoint for firebird-docker images.
#
# Based on works of Jacob Alberty and The PostgreSQL Development Group.
#

#
# About the [Tabs ahead] marker:
#   Some sections of this file use tabs for better readability.
#   When using bash here strings the - option suppresses leading tabs but not spaces.
#



# https://linuxcommand.org/lc3_man_pages/seth.html
#   -E  If set, the ERR trap is inherited by shell functions.
#   -e  Exit immediately if a command exits with a non-zero status.
#   -u  Treat unset variables as an error when substituting
#   -o  Set the variable corresponding to option-name:
#       pipefail     the return value of a pipeline is the status of
#                    the last command to exit with a non-zero status,
#                    or zero if no command exited with a non-zero status
set -Eeuo pipefail

# usage: read_from_file_or_env VAR [DEFAULT]
#    ie: read_from_file_or_env 'DB_PASSWORD' 'example'
# If $(VAR)_FILE var is set, sets VAR value from file contents. Otherwise, uses DEFAULT value if VAR is not set.
read_from_file_or_env() {
    local var="$1"
    local fileVar="${var}_FILE"
    if [ "${!var:-}" ] && [ "${!fileVar:-}" ]; then
        # [Tabs ahead]
        cat >&2 <<-EOL
			-----
			ERROR: Both $var and $fileVar are set.
			
			       Variables %s and %s are mutually exclusive. Remove either one.
			-----
		EOL
        exit 1
    fi

    local def="${2:-}"
    local val="$def"
    if [ "${!var:-}" ]; then
        val="${!var}"
    elif [ "${!fileVar:-}" ]; then
        val="$(< "${!fileVar}")"
    fi

    export "$var"="$val"
    unset "$fileVar"
}

# usage: firebird_config_set KEY VALUE
#    ie: firebird_config_set 'WireCrypt' 'Enabled'
# Set configuration key KEY to VALUE in 'firebird.conf'
firebird_config_set() {
    # Uncomment line
    sed -i "s/^#${1}/${1}/g" /etc/firebird/2.5/firebird.conf

    # Set KEY to VALUE
    sed -i "s~^\(${1}\s*=\s*\).*$~\1${2}~" /etc/firebird/2.5/firebird.conf
}

# Indent multi-line string -- https://stackoverflow.com/a/29779745
indent() {
    sed 's/^/    /';
}

# Set Firebird configuration parameters from environment variables.
set_config() {
    read_from_file_or_env 'FIREBIRD_USE_LEGACY_AUTH'
    if [ "$FIREBIRD_USE_LEGACY_AUTH" == 'true' ]; then
        echo 'Using Legacy_Auth.'

        # Firebird 4+: Uses 'Srp256' before 'Srp'.
        local srp256=''
        [ "$FIREBIRD_MAJOR" -ge "4" ] && srp256='Srp256, '

        # Adds Legacy_Auth and Legacy_UserManager as first options.
        firebird_config_set AuthServer "Legacy_Auth, ${srp256}Srp"
        firebird_config_set AuthClient "Legacy_Auth, ${srp256}Srp"
        firebird_config_set UserManager 'Legacy_UserManager, Srp'

        # Default setting is 'Required'. Reduces it to 'Enabled'.
        firebird_config_set WireCrypt 'Enabled'
    fi

    # FIREBIRD_CONF_* variables: set key in 'firebird.conf'
    local v
    for v in $(compgen -A variable | grep 'FIREBIRD_CONF_'); do
        local key=${v/FIREBIRD_CONF_/}
        firebird_config_set "$key" "${!v}"
    done

    # Output changed settings
    local changed_settings=$(grep -o '^[^#]*' /opt/firebird/firebird.conf)
    if [ -n "$changed_settings" ]; then
        echo "Using settings:"
        echo "$changed_settings" | indent
    fi
}

# Changes SYSDBA password if FIREBIRD_ROOT_PASSWORD variable is set.
set_sysdba() {
    read_from_file_or_env 'FIREBIRD_ROOT_PASSWORD'
    if [ -n "$FIREBIRD_ROOT_PASSWORD" ]; then
        echo 'Changing SYSDBA password.'

        # [Tabs ahead]
        /opt/firebird/bin/isql -b -user SYSDBA security.db <<-EOL
			CREATE OR ALTER USER SYSDBA
			    PASSWORD '$FIREBIRD_ROOT_PASSWORD'
			    USING PLUGIN Srp;
			EXIT;
		EOL

        if [ "$FIREBIRD_USE_LEGACY_AUTH" == 'true' ]; then
            # [Tabs ahead]
            /opt/firebird/bin/isql -b -user SYSDBA security.db <<-EOL
				CREATE OR ALTER USER SYSDBA
				    PASSWORD '$FIREBIRD_ROOT_PASSWORD'
				    USING PLUGIN Legacy_UserManager;
				EXIT;
			EOL
        fi

        rm -rf /opt/firebird/SYSDBA.password
    fi
}

# Requires FIREBIRD_PASSWORD if FIREBIRD_USER is set.
requires_user_password() {
    if [ -n "$FIREBIRD_USER" ] && [ -z "$FIREBIRD_PASSWORD" ]; then
        # [Tabs ahead]
        cat >&2 <<-EOL
			-----
			ERROR: FIREBIRD_PASSWORD variable is not set.
			
			       When using FIREBIRD_USER you must also set FIREBIRD_PASSWORD variable.
			-----
		EOL
        exit 1
    fi
}

# Create Firebird user.
create_user() {
    read_from_file_or_env 'FIREBIRD_USER'
    read_from_file_or_env 'FIREBIRD_PASSWORD'

    if [ -n "$FIREBIRD_USER" ]; then
        requires_user_password
        echo "Creating user '$FIREBIRD_USER'..."

        # [Tabs ahead]
        /opt/firebird/bin/isql -b security.db <<-EOL
			CREATE OR ALTER USER $FIREBIRD_USER
			    PASSWORD '$FIREBIRD_PASSWORD'
			    GRANT ADMIN ROLE;
			EXIT;
		EOL
    fi
}

sigint_handler() {
    echo "Stopping Firebird... [SIGINT received]"
}

sigterm_handler() {
    echo "Stopping Firebird... [SIGTERM received]"
}

run_daemon_and_wait() {
    # Traps SIGINT (handles Ctrl-C in interactive mode)
    trap sigint_handler SIGINT

    # Traps SIGTERM (polite shutdown)
    trap sigterm_handler SIGTERM

    # Firebird version
    echo -n 'Starting '
    /usr/sbin/fb_smp_server -z

    # Run fbguard and wait
    /usr/sbin/fbguard &
    wait $!
}



#
# main()
#
if [ "$1" = 'firebird' ]; then
    #set_config
    #set_sysdba

    #create_user

    run_daemon_and_wait
else
    exec "$@"
fi