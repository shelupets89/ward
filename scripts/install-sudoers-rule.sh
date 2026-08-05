#!/usr/bin/env bash
# Optional: let Ward toggle lid sleep without asking for your password.
#
# Grants exactly two commands — nothing else. The only power this confers is
# turning lid sleep on and off, which Ward's menu already does; it does not
# grant general root access.
#
# Why bother: the safety paths (expiry, restore-on-quit) can only run
# unattended if they don't need a password dialog. With this rule installed,
# an expired session restores sleep on its own.
#
# Uninstall:  sudo rm /etc/sudoers.d/ward
# Usage:      bash scripts/install-sudoers-rule.sh

set -euo pipefail

SUDOERS_PATH="/etc/sudoers.d/ward"
STAGED_RULE="$(mktemp)"
trap 'rm -f "${STAGED_RULE}"' EXIT

cat > "${STAGED_RULE}" <<RULE
# Installed by Ward (scripts/install-sudoers-rule.sh).
# Allows toggling lid-close sleep without a password prompt. Nothing else.
${USER} ALL=(root) NOPASSWD: /usr/bin/pmset -a disablesleep 1, /usr/bin/pmset -a disablesleep 0
RULE

echo "The following rule will be installed to ${SUDOERS_PATH}:"
echo
cat "${STAGED_RULE}"
echo
read -r -p "Install it? [y/N] " CONFIRMATION
if [ "${CONFIRMATION}" != "y" ] && [ "${CONFIRMATION}" != "Y" ]; then
    echo "Aborted — nothing changed."
    exit 0
fi

# visudo -c validates before anything lands in /etc/sudoers.d, so a malformed
# rule can never break sudo on this machine.
if ! sudo visudo -c -f "${STAGED_RULE}"; then
    echo "Rule failed validation — refusing to install." >&2
    exit 1
fi

sudo install -m 0440 -o root -g wheel "${STAGED_RULE}" "${SUDOERS_PATH}"
echo "Installed ${SUDOERS_PATH}"

echo
echo "Verifying (should print nothing and exit 0):"
if sudo -n /usr/bin/pmset -a disablesleep 0; then
    echo "✅ Passwordless toggle works."
else
    echo "❌ Still prompting — check ${SUDOERS_PATH}." >&2
    exit 1
fi
