#!/bin/bash
# =========================
# Add User OSX Command Line
# =========================

# An easy add user script for Max OSX.
# Although I wrote this for 10.7 Lion Server, these commands have been the same since 10.5 Leopard.
# It's pretty simple as it uses and strings together the (rustic and ancient) commands that OSX 
# already uses to add users.

if [ "$#" -ne 3 ]; then
    echo "Usage: ./osx-adduser.sh USERNAME FULLNAME PASSWORD"
    exit 255
fi

# === Typically, this is all the info you need to enter ===
USERNAME=$1
FULLNAME=$2
PASSWORD=$3

# ====

# A list of (secondary) groups the user should belong to
# This makes the difference between admin and non-admin users.

SECONDARY_GROUPS="staff"  # for a non-admin user

# ====

# Create a UID that is not currently in use
echo "Creating an unused UID for new user..."

if [[ $UID -ne 0 ]]; then echo "Please run $0 as root." && exit 1; fi

# Find out the next available user ID
MAXID=$(dscl . -list /Users UniqueID | awk '{print $2}' | sort -ug | tail -1)
USERID=$((MAXID+1))


# Create the user account by running dscl (normally you would have to do each of these commands one
# by one in an obnoxious and time consuming way.
echo "Creating necessary files..."

dscl . -create /Users/$USERNAME
dscl . -create /Users/$USERNAME UserShell /bin/bash
dscl . -create /Users/$USERNAME RealName "$FULLNAME"
dscl . -create /Users/$USERNAME UniqueID "$USERID"
dscl . -create /Users/$USERNAME PrimaryGroupID 20
dscl . -create /Users/$USERNAME NFSHomeDirectory /Users/$USERNAME
dscl . -passwd /Users/$USERNAME $PASSWORD


# Add user to any specified groups
echo "Adding user to specified groups..."

for GROUP in $SECONDARY_GROUPS ; do
    dseditgroup -o edit -t user -a $USERNAME $GROUP
done

# Create the home directory
echo "Creating home directory..."
createhomedir -c 2>&1 | grep -v "shell-init"

echo "Created user #$USERID: $USERNAME ($FULLNAME)"
