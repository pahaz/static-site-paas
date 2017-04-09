#!/usr/bin/env bash

set -eo pipefail; [[ $TRACE ]] && set -x

USERNAME=static

install-requirements() {
  echo "--> Ensuring we have the proper dependencies"

  export DEBIAN_FRONTEND=noninteractive

  case "$DISTRO" in
    debian|ubuntu)
      apt-get update -qq > /dev/null
      if [[ "$DISTRO_VERSION" == "12.04" ]]; then
        apt-get -qq -y install python-software-properties
      fi
      apt-get -qq -y install python3-pip
      apt-get -qq -y install sshcommand

      add-apt-repository -y ppa:nginx/stable
      apt-get update -qq > /dev/null
      apt-get install -o Dpkg::Options::="--force-confdef" -o Dpkg::Options::="--force-confold" --force-yes -qq -y nginx dnsutils

      ;;
  esac

  PYTHON=$(which python3)
  $PYTHON -m pip install -U gitreceive
}

setup-user() {
  echo "--> Setting up $USERNAME user"
  getent passwd $USERNAME >/dev/null || useradd -m -s /bin/bash $USERNAME
  mkdir -p "/home/$USERNAME/.ssh"
  touch "/home/$USERNAME/.ssh/authorized_keys"
  chown -R $USERNAME:$USERNAME "/home/$USERNAME/.ssh"
}

setup-sshcommand() {
  echo "--> Ensure proper sshcommand path"
  echo "$(which python3) -m gitreceive" > "/home/$USERNAME/.sshcommand"
}

setup-nginx() {
  case "$DISTRO" in
    debian)
      echo "%$USERNAME ALL=(ALL) NOPASSWD:/usr/sbin/invoke-rc.d nginx reload, /usr/sbin/nginx -t" > /etc/sudoers.d/$USERNAME-nginx
      ;;

    ubuntu)
      echo "%$USERNAME ALL=(ALL) NOPASSWD:/etc/init.d/nginx reload, /usr/sbin/nginx -t" > /etc/sudoers.d/$USERNAME-nginx
      ;;

    opensuse)
      echo "%$USERNAME ALL=(ALL) NOPASSWD:/sbin/service nginx reload, /usr/sbin/nginx -t" > /etc/sudoers.d/$USERNAME-nginx
      ;;

    arch)
      echo "%$USERNAME ALL=(ALL) NOPASSWD:/usr/bin/systemctl reload nginx, /usr/sbin/nginx -t" > /etc/sudoers.d/$USERNAME-nginx
      ;;

    centos)
      echo "%$USERNAME ALL=(ALL) NOPASSWD:/usr/bin/systemctl reload nginx, /usr/sbin/nginx -t" > /etc/sudoers.d/$USERNAME-nginx
      echo "Defaults:$USERNAME !requiretty" >> /etc/sudoers.d/$USERNAME-nginx
      ;;
  esac

  chmod 0440 /etc/sudoers.d/$USERNAME-nginx

  # if $USERNAME.conf has not been created, create it
  if [[ ! -f /etc/nginx/conf.d/$USERNAME.conf ]]; then
    cat<<EOF > /etc/nginx/conf.d/$USERNAME.conf
server {
  server_name ~^(?<domain>.+)\$;
  root /home/$USERNAME/.gitreceive.files/\$domain;

  access_log /var/log/nginx/\$domain-$USERNAME-access.log;

  # error_log can't contain variables, so we'll have to share: http://serverfault.com/a/644898
  error_log /var/log/nginx/$USERNAME-error.log;
}
EOF
  fi

  if [[ -f /etc/nginx/sites-enabled/default ]]; then
    rm /etc/nginx/sites-enabled/default
  fi

  case "$DISTRO" in
    debian)
      NGINX_INIT="/usr/sbin/invoke-rc.d"
      "$NGINX_INIT" nginx start || "$NGINX_INIT" nginx reload
      ;;

    ubuntu)
      NGINX_INIT="/etc/init.d/nginx"
      "$NGINX_INIT" start || "$NGINX_INIT" reload
      ;;

    opensuse)
      NGINX_INIT="/sbin/service"
      "$NGINX_INIT" nginx start || "$NGINX_INIT" nginx reload
      ;;

    arch|centos)
      NGINX_INIT="/usr/bin/systemctl"
      "$NGINX_INIT" start nginx || "$NGINX_INIT" reload nginx
      ;;
  esac

}

main() {
  export DISTRO DISTRO_VERSION
  DISTRO=$(. /etc/os-release && echo "$ID")
  DISTRO_VERSION=$(. /etc/os-release && echo "$VERSION_ID")

  install-requirements
  setup-user
  setup-sshcommand
  setup-nginx
}

main "$@"
