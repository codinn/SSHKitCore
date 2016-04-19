rm id*
echo "Encryption Password: lollipop"

ssh-keygen -b 1024 -t dsa -f ./id_dsa -N ""

ssh-keygen -b 2048 -t rsa -f ./id_rsa -N ""
ssh-keygen -b 2048 -t rsa -f ./id_rsa_password -N "lollipop"
ssh-keygen -b 4096 -t rsa -f ./id_rsa_4096 -N ""

ssh-keygen -b 521 -t ecdsa -f ./id_ecdsa -N ""
ssh-keygen -b 521 -t ecdsa -f ./id_ecdsa_password -N "lollipop"

ssh-keygen -t ed25519 -f ./id_ed25519 -N ""
ssh-keygen -t ed25519 -f ./id_ed25519_password -N "lollipop"

# pkcs#8 - dsa
openssl pkcs8 -nocrypt -in ./id_dsa -topk8 -out id_dsa.pkcs8
openssl pkcs8 -in ./id_dsa -topk8 -out id_dsa.pkcs8.password -passout 'pass:lollipop'

# pkcs#8 - rsa
openssl pkcs8 -nocrypt -in ./id_rsa -topk8 -out id_rsa.pkcs8
openssl pkcs8 -in ./id_rsa -topk8 -out id_rsa.pkcs8.password -passout 'pass:lollipop'
