#!/bin/bash -e

set -x

HOSTS_CONTENT=$(cat <<EOL
127.0.1.1 pupper
127.0.0.1 localhost

# The following lines are desirable for IPv6 capable hosts
::1 localhost ip6-localhost ip6-loopback
ff02::1 ip6-allnodes
ff02::2 ip6-allrouters
EOL
)

echo "$HOSTS_CONTENT" | sudo tee /etc/hosts > /dev/null
echo "/etc/hosts has been updated successfully!"
